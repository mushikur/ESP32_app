import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:esp_iot/core/protocol/device_command.dart';
import 'package:esp_iot/core/protocol/device_descriptor.dart';
import 'package:esp_iot/core/protocol/device_status.dart';
import 'package:esp_iot/core/transport/lan_transport.dart';
import 'package:esp_iot/features/connection/lan_universal_connector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android protocol models exchange v1 messages with the C++ firmware', () async {
    const executable = String.fromEnvironment('ESP_IOT_FIRMWARE_RUNNER');
    expect(
      executable,
      isNotEmpty,
      reason: 'Run firmware/tests/test-firmware.ps1 -FlutterContract',
    );
    final process = await Process.start(executable, const ['--wire']);
    final output = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final errors = process.stderr.transform(utf8.decoder).join();
    addTearDown(() async {
      await process.stdin.close();
      await output.cancel();
      final result = await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      expect(result, 0, reason: await errors);
    });

    Future<String> exchange(String line) async {
      process.stdin.writeln(line);
      await process.stdin.flush();
      expect(
        await output.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      return output.current;
    }

    final descriptor = DeviceDescriptor.decode(
      utf8.encode(await exchange('descriptor')),
    );
    expect(descriptor.hasEvents, isTrue);
    expect(descriptor.capabilities['temperature']?.unit, '°C');
    expect(descriptor.capabilities['led']?.name, 'LED "test" \\ bench');
    final before = DeviceStatus.parse(
      jsonDecode(await exchange('status')),
      descriptor,
    );
    expect(before.values?['led'], isFalse);
    expect(before.values?['temperature'], 23.5);
    expect(before.values?['fan_speed'], isNull);

    final command = DeviceCommand(descriptor, before, 'led', 'set', true);
    final response = await exchange('command ${command.body}');
    final split = response.indexOf(' ');
    final status = int.parse(response.substring(0, split));
    final reply = LanResponse(
      status,
      'application/json',
      Uint8List.fromList(utf8.encode(response.substring(split + 1))),
    );
    expect(
      readLanAcknowledgement(command, reply),
      DeviceAcknowledgement.applied,
    );
    expect(await exchange('command ${command.body}'), response);
    final after = DeviceStatus.parse(
      jsonDecode(await exchange('status')),
      descriptor,
    );
    expect(after.bootId, before.bootId);
    expect(after.sequence, greaterThan(before.sequence!));
    expect(after.values?['led'], isTrue);

    const nonce = 'abcdeabcdeabcdeabcdeabcdeabcdeab';
    final offer = jsonDecode(
      await exchange(
        'offer ${jsonEncode({'protocol': 'esp-iot', 'version': 1, 'kind': 'discover', 'nonce': nonce})}',
      ),
    ) as Map<String, Object?>;
    expect(offer, {
      'protocol': 'esp-iot',
      'version': 1,
      'kind': 'offer',
      'nonce': nonce,
      'deviceId': descriptor.id,
      'port': 8080,
      'tls': false,
    });
  });
}
