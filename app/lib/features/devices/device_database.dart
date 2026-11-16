import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'device_registration.dart';

abstract interface class RegistrationStore {
  Future<String?> load();
  Future<void> save(String data);
}

enum ActivityKind {
  registered('Device registered'),
  verified('Address verified'),
  connected('Connected'),
  disconnected('Connection lost'),
  offline('Device unreachable'),
  authorization('Authorization required'),
  failed('Connection check failed'),
  applied('Command acknowledged'),
  rejected('Command rejected'),
  unconfirmed('Command unconfirmed');

  const ActivityKind(this.label);
  final String label;
}

typedef ActivityEntry = ({
  String registrationId,
  ActivityKind kind,
  DateTime time,
});
typedef DeviceUsage = ({DateTime? lastSeen, DateTime? lastOpened});

class DeviceHistory {
  const DeviceHistory(this.activity, this.usage);
  final List<ActivityEntry> activity;
  final Map<String, DeviceUsage> usage;
}

abstract interface class DeviceHistoryStore {
  Future<DeviceHistory> history();
  Future<void> record(
    DeviceRegistration device,
    DateTime time, {
    ActivityKind? kind,
    DateTime? seen,
    bool opened = false,
  });
}

class DeviceDatabase implements RegistrationStore, DeviceHistoryStore {
  DeviceDatabase(
    this._factory,
    this._legacyData, {
    this.path,
    this.clearLegacyData,
  });

  final DatabaseFactory _factory;
  final Future<String?> Function() _legacyData;
  final String? path;
  final Future<void> Function()? clearLegacyData;
  Future<Database>? _opening;
  static const _activityLimit = 300;

  Future<Database> get _database async {
    final opening = _opening ??= _open();
    try {
      return await opening;
    } on Object {
      if (identical(_opening, opening)) _opening = null;
      rethrow;
    }
  }

  Future<Database> _open() async {
    final databasePath =
        path ?? '${await _factory.getDatabasesPath()}/esp_iot.db';
    final db = await _factory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await db.execute('''CREATE TABLE devices (
          registration_id TEXT PRIMARY KEY NOT NULL,
          origin TEXT UNIQUE NOT NULL,
          device_id TEXT UNIQUE,
          sort_order INTEGER NOT NULL,
          payload TEXT NOT NULL,
          last_seen INTEGER,
          last_opened INTEGER
        )''');
          await db.execute('''CREATE TABLE activity (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          registration_id TEXT NOT NULL REFERENCES devices(registration_id) ON DELETE CASCADE,
          kind TEXT NOT NULL,
          occurred_at INTEGER NOT NULL
        )''');
          await db.execute(
            'CREATE INDEX activity_device ON activity(registration_id)',
          );
          await db.execute(
            'CREATE TABLE removed_devices (registration_id TEXT PRIMARY KEY NOT NULL, payload TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE migrations (name TEXT PRIMARY KEY NOT NULL)',
          );
        },
      ),
    );
    try {
      const migration = 'device_registry_v1';
      final applied = await db.query(
        'migrations',
        where: 'name = ?',
        whereArgs: [migration],
      );
      if (applied.isEmpty) {
        final previous = await _legacyData();
        final entries = previous == null
            ? const <DeviceRegistration>[]
            : decodeRegistrations(previous);
        await db.transaction((txn) async {
          final existing = await txn.query(
            'migrations',
            where: 'name = ?',
            whereArgs: [migration],
          );
          if (existing.isNotEmpty) return;
          for (final (index, device) in entries.indexed) {
            await txn.insert('devices', _row(device, index));
          }
          await txn.insert('migrations', {'name': migration});
        });
      }
      try {
        await clearLegacyData?.call();
      } on Exception {
        // The import is committed. Retry preference cleanup on the next open.
      }
      return db;
    } on Object {
      await db.close();
      rethrow;
    }
  }

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }

  @override
  Future<String> load() async {
    final rows = await (await _database).query(
      'devices',
      columns: ['payload'],
      orderBy: 'sort_order',
    );
    return '[${rows.map((row) => row['payload']).join(',')}]';
  }

  @override
  Future<void> save(String data) async {
    final entries = decodeRegistrations(data);
    final ids = entries.map((device) => device.registrationId).toSet();
    final db = await _database;
    await db.transaction((txn) async {
      final existing = {
        for (final row in await txn.query('devices'))
          row['registration_id'] as String: row,
      };
      for (final entry in existing.entries.where(
        (entry) => !ids.contains(entry.key),
      )) {
        await txn.insert('removed_devices', {
          'registration_id': entry.key,
          'payload': entry.value['payload'],
        });
        await txn.delete(
          'devices',
          where: 'registration_id = ?',
          whereArgs: [entry.key],
        );
      }
      var changedActivity = false;
      for (final (index, device) in entries.indexed) {
        final row = _row(device, index);
        final old = existing[device.registrationId];
        if (old == null) {
          await txn.insert('devices', row);
          await _addActivity(
            txn,
            device.registrationId,
            device.checkedAt,
            ActivityKind.registered,
          );
          changedActivity = true;
        } else if (row['payload'] != old['payload'] ||
            row['sort_order'] != old['sort_order']) {
          await txn.update(
            'devices',
            row,
            where: 'registration_id = ?',
            whereArgs: [device.registrationId],
          );
          final previous = DeviceRegistration.fromJson(
            jsonDecode(old['payload'] as String),
          );
          if (previous.checkedAt != device.checkedAt ||
              previous.endpoint != device.endpoint) {
            await _addActivity(
              txn,
              device.registrationId,
              device.checkedAt,
              ActivityKind.verified,
            );
            changedActivity = true;
          }
        }
      }
      if (changedActivity) await _trimActivity(txn);
    });
  }

  Map<String, Object?> _row(DeviceRegistration device, int order) => {
    'registration_id': device.registrationId,
    'origin': device.endpoint.origin,
    'device_id': device.deviceId,
    'sort_order': order,
    'payload': jsonEncode(device.toJson()),
  };

  Future<List<DeviceRegistration>> pendingRemovals() async {
    final rows = await (await _database).query(
      'removed_devices',
      columns: ['payload'],
    );
    return [
      for (final row in rows)
        DeviceRegistration.fromJson(jsonDecode(row['payload'] as String)),
    ];
  }

  Future<void> completeRemoval(String id) async {
    await (await _database).delete(
      'removed_devices',
      where: 'registration_id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<DeviceHistory> history() async {
    final db = await _database;
    return db.transaction((txn) async {
      final events = await txn.query(
        'activity',
        orderBy: 'id DESC',
        limit: _activityLimit,
      );
      final rows = await txn.query(
        'devices',
        columns: ['registration_id', 'last_seen', 'last_opened'],
      );
      DateTime? at(Object? value) => value is int
          ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)
          : null;
      return DeviceHistory(
        List.unmodifiable([
          for (final row in events)
            (
              registrationId: row['registration_id'] as String,
              kind: ActivityKind.values.byName(row['kind'] as String),
              time: at(row['occurred_at'])!,
            ),
        ]),
        Map.unmodifiable({
          for (final row in rows)
            row['registration_id'] as String: (
              lastSeen: at(row['last_seen']),
              lastOpened: at(row['last_opened']),
            ),
        }),
      );
    });
  }

  @override
  Future<void> record(
    DeviceRegistration device,
    DateTime time, {
    ActivityKind? kind,
    DateTime? seen,
    bool opened = false,
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      const where = 'registration_id = ? AND origin = ?';
      final args = [device.registrationId, device.endpoint.origin];
      final rows = await txn.query(
        'devices',
        columns: ['last_seen', 'last_opened'],
        where: where,
        whereArgs: args,
      );
      if (rows.isEmpty) return;
      final row = rows.single;
      final updates = <String, int>{};
      if (seen != null &&
          seen.millisecondsSinceEpoch > (row['last_seen'] as int? ?? 0)) {
        updates['last_seen'] = seen.millisecondsSinceEpoch;
      }
      if (opened &&
          time.millisecondsSinceEpoch > (row['last_opened'] as int? ?? 0)) {
        updates['last_opened'] = time.millisecondsSinceEpoch;
      }
      if (updates.isNotEmpty) {
        await txn.update('devices', updates, where: where, whereArgs: args);
      }
      if (kind != null) {
        await _addActivity(txn, device.registrationId, time, kind);
        await _trimActivity(txn);
      }
    });
  }

  Future<void> _addActivity(
    Transaction txn,
    String id,
    DateTime time,
    ActivityKind kind,
  ) async {
    await txn.insert('activity', {
      'registration_id': id,
      'kind': kind.name,
      'occurred_at': time.millisecondsSinceEpoch,
    });
  }

  Future<void> _trimActivity(Transaction txn) async {
    await txn.rawDelete(
      'DELETE FROM activity WHERE id < (SELECT id FROM activity ORDER BY id DESC LIMIT 1 OFFSET ?)',
      [_activityLimit - 1],
    );
  }
}

final deviceDatabaseProvider = Provider<DeviceDatabase>((ref) {
  final preferences = SharedPreferencesAsync();
  final database = DeviceDatabase(
    databaseFactory,
    () => preferences.getString('device_registry_v1'),
    clearLegacyData: () => preferences.remove('device_registry_v1'),
  );
  ref.onDispose(() => unawaited(database.close().onError((_, _) {})));
  return database;
});
final deviceHistoryStoreProvider = Provider<DeviceHistoryStore>(
  (ref) => ref.watch(deviceDatabaseProvider),
);
final deviceHistoryProvider = FutureProvider<DeviceHistory>(
  (ref) => ref.watch(deviceHistoryStoreProvider).history(),
  retry: (_, _) => null,
);
