#include "Protocol.h"

#include <cmath>
#include <cstring>

#include "Wire.h"

namespace espiot {
namespace {

bool equals(const char* actual, const char* expected) {
  return actual && std::strcmp(actual, expected) == 0;
}

bool aligned(double steps) {
  return std::isfinite(steps) && std::fabs(steps - std::round(steps)) < 1e-7;
}

void identity(JsonWriter& writer, const char* deviceId, const char* bootId, int32_t revision) {
  writer.raw("\"deviceId\":");
  writer.string(deviceId);
  writer.raw(",\"bootId\":");
  writer.string(bootId);
  writer.raw(",\"revision\":");
  writer.integer(static_cast<uint64_t>(revision));
}

}  // namespace

bool Protocol::configure(const char* name, const char* type, int32_t revision, const char* deviceId,
                         const char* bootId, bool events, bool pairing) {
  if (revision_ || !label(name, 64) || !capabilityId(type) || revision < 1 || !hexId(deviceId) ||
      !hexId(bootId))
    return false;
  std::strcpy(name_, name);
  std::strcpy(type_, type);
  std::strcpy(deviceId_, deviceId);
  std::strcpy(bootId_, bootId);
  revision_ = revision;
  events_ = events;
  pairing_ = pairing;
  return true;
}

Protocol::Capability* Protocol::find(const char* id) {
  if (!id) return nullptr;
  for (size_t i = 0; i < count_; ++i) {
    if (std::strcmp(capabilities_[i].id, id) == 0) return &capabilities_[i];
  }
  return nullptr;
}

Protocol::Capability* Protocol::add(const char* id, const char* name, Kind kind) {
  if (revision_ || count_ == maxCapabilities || !capabilityId(id) || !label(name, 64) || find(id))
    return nullptr;
  Capability& item = capabilities_[count_++];
  std::strcpy(item.id, id);
  std::strcpy(item.name, name);
  item.kind = kind;
  return &item;
}

bool Protocol::addSwitch(const char* id, const char* name, SwitchHandler handler, void* context,
                         bool confirm) {
  Capability* item = handler ? add(id, name, Kind::Switch) : nullptr;
  if (!item) return false;
  item->switchHandler = handler;
  item->context = context;
  item->confirm = confirm;
  return true;
}

bool Protocol::addRange(const char* id, const char* name, double min, double max, double step,
                        const char* unit, RangeHandler handler, void* context, bool confirm) {
  if (!handler || !std::isfinite(min) || !std::isfinite(max) || !std::isfinite(step) || step <= 0 ||
      min >= max || !label(unit, 16, true))
    return false;
  const double steps = (max - min) / step;
  if (steps < 1 || steps > 10000 || !aligned(steps)) return false;
  Capability* item = add(id, name, Kind::Range);
  if (!item) return false;
  std::strcpy(item->unit, unit);
  item->min = min;
  item->max = max;
  item->step = step;
  item->rangeHandler = handler;
  item->context = context;
  item->confirm = confirm;
  return true;
}

bool Protocol::addSensor(const char* id, const char* name, const char* unit) {
  Capability* item = label(unit, 16, true) ? add(id, name, Kind::Sensor) : nullptr;
  if (!item) return false;
  std::strcpy(item->unit, unit);
  return true;
}

bool Protocol::addAction(const char* id, const char* name, ActionHandler handler, void* context,
                         bool confirm) {
  Capability* item = handler ? add(id, name, Kind::Action) : nullptr;
  if (!item) return false;
  item->actionHandler = handler;
  item->context = context;
  item->confirm = confirm;
  return true;
}

bool Protocol::addMotionStop(const char* id, const char* name, uint8_t directions,
                             uint16_t maxDurationMs, ActionHandler stop, void* context) {
  if (!stop || !directions || (directions & 0xf0) || maxDurationMs < 100 || maxDurationMs > 2000)
    return false;
  Capability* item = add(id, name, Kind::Motion);
  if (!item) return false;
  item->directions = directions;
  item->maxDurationMs = maxDurationMs;
  item->actionHandler = stop;
  item->context = context;
  return true;
}

bool Protocol::publishSwitch(const char* id, bool value) {
  Capability* item = find(id);
  if (!item || item->kind != Kind::Switch) return false;
  item->available = true;
  item->switched = value;
  return true;
}

bool Protocol::publishNumber(const char* id, double value) {
  Capability* item = find(id);
  if (!item || !std::isfinite(value)) return false;
  if (item->kind != Kind::Sensor &&
      (item->kind != Kind::Range || value < item->min || value > item->max))
    return false;
  item->available = true;
  item->number = value;
  return true;
}

bool Protocol::publishUnavailable(const char* id) {
  Capability* item = find(id);
  if (!item || item->kind == Kind::Action) return false;
  item->available = false;
  return true;
}

size_t Protocol::descriptor(char* output, size_t capacity) const {
  if (!revision_) return 0;
  JsonWriter writer(output, capacity);
  writer.raw("{\"protocol\":\"esp-iot\",\"version\":1,\"deviceId\":");
  writer.string(deviceId_);
  writer.raw(",\"revision\":");
  writer.integer(static_cast<uint64_t>(revision_));
  writer.raw(",\"name\":");
  writer.string(name_);
  writer.raw(",\"type\":");
  writer.string(type_);
  writer.raw(",\"auth\":");
  writer.string(pairing_ ? "pairing-token" : "none");
  writer.raw(",\"events\":");
  writer.boolean(events_);
  writer.raw(",\"capabilities\":[");
  constexpr const char* kinds[] = {"switch", "range", "sensor", "action", "motion"};
  constexpr const char* directions[] = {"forward", "reverse", "left", "right"};
  for (size_t i = 0; i < count_; ++i) {
    const Capability& item = capabilities_[i];
    if (i) writer.raw(",");
    writer.raw("{\"id\":");
    writer.string(item.id);
    writer.raw(",\"name\":");
    writer.string(item.name);
    writer.raw(",\"type\":");
    writer.string(kinds[static_cast<unsigned>(item.kind)]);
    if (item.kind == Kind::Switch || item.kind == Kind::Range || item.kind == Kind::Action) {
      writer.raw(",\"confirm\":");
      writer.boolean(item.confirm);
    }
    if (item.kind == Kind::Range || item.kind == Kind::Sensor) {
      writer.raw(",\"unit\":");
      writer.string(item.unit);
    }
    if (item.kind == Kind::Range) {
      writer.raw(",\"min\":");
      writer.number(item.min);
      writer.raw(",\"max\":");
      writer.number(item.max);
      writer.raw(",\"step\":");
      writer.number(item.step);
    }
    if (item.kind == Kind::Motion) {
      writer.raw(",\"directions\":[");
      bool comma = false;
      for (size_t index = 0; index < 4; ++index) {
        if (!(item.directions & (1u << index))) continue;
        if (comma) writer.raw(",");
        writer.string(directions[index]);
        comma = true;
      }
      writer.raw("],\"maxDurationMs\":");
      writer.integer(item.maxDurationMs);
    }
    writer.raw("}");
  }
  writer.raw("]}");
  return writer.size();
}

size_t Protocol::snapshot(char* output, size_t capacity) {
  if (!revision_ || sequence_ >= 9007199254740991ULL) return 0;
  JsonWriter writer(output, capacity);
  writer.raw("{");
  identity(writer, deviceId_, bootId_, revision_);
  writer.raw(",\"seq\":");
  writer.integer(sequence_ + 1);
  writer.raw(",\"values\":{");
  bool comma = false;
  for (size_t i = 0; i < count_; ++i) {
    const Capability& item = capabilities_[i];
    if (item.kind == Kind::Action) continue;
    if (comma) writer.raw(",");
    comma = true;
    writer.string(item.id);
    writer.raw(":");
    if (!item.available)
      writer.raw("null");
    else if (item.kind == Kind::Switch)
      writer.boolean(item.switched);
    else if (item.kind == Kind::Motion)
      writer.string("stopped");
    else
      writer.number(item.number);
  }
  writer.raw("}}");
  if (writer.size()) ++sequence_;
  return writer.size();
}

Reply Protocol::outcome(const char* id, unsigned status, const char* code, char* output,
                        size_t capacity) const {
  JsonWriter writer(output, capacity);
  writer.raw("{");
  if (id) {
    writer.raw("\"commandId\":");
    writer.string(id);
    writer.raw(",");
    identity(writer, deviceId_, bootId_, revision_);
    writer.raw(",\"outcome\":");
    writer.string(code ? "rejected" : "applied");
    if (code) writer.raw(",");
  }
  if (code) {
    writer.raw("\"code\":");
    writer.string(code);
  }
  writer.raw("}");
  return {status, writer.size()};
}

Reply Protocol::command(const char* bytes, size_t length, uint64_t nowMs, char* output,
                        size_t capacity, uint32_t principal) {
  // Require room for a complete acknowledgement before invoking an application callback.
  if (!revision_ || !output || capacity < 320) return {500, 0};
  if (pairing_ && !principal) return outcome(nullptr, 401, "auth_required", output, capacity);
  WireObject data;
  if (length > maxCommandBytes || !data.parse(bytes, length)) {
    return outcome(nullptr, 400, "invalid_command", output, capacity);
  }
  const char* id = data.string("commandId");
  if (!hexId(id)) return outcome(nullptr, 400, "invalid_command", output, capacity);
  const Field* revision = data.get("revision", ValueKind::Number);
  const char* boot = data.string("bootId");
  const char* op = data.string("op");
  const char* capId = data.string("capabilityId");
  if (!hexId(boot) || !revision || !revision->integer || revision->number < 1 ||
      revision->number > 2147483647.0 || !op || !capabilityId(capId)) {
    return outcome(id, 400, "invalid_command", output, capacity);
  }
  if (!equals(boot, bootId_)) return outcome(id, 409, "device_restarted", output, capacity);
  if (revision->number != revision_)
    return outcome(id, 409, "descriptor_changed", output, capacity);
  Capability* item = find(capId);
  if (!item) return outcome(id, 400, "invalid_command", output, capacity);

  Operation operation{};
  double value = 0;
  if (equals(op, "set") && data.count() == 6 && item->kind == Kind::Switch) {
    const Field* field = data.get("value", ValueKind::Boolean);
    if (!field) return outcome(id, 400, "invalid_command", output, capacity);
    operation = Operation::Switch;
    value = field->boolean ? 1 : 0;
  } else if (equals(op, "set") && data.count() == 6 && item->kind == Kind::Range) {
    const Field* field = data.get("value", ValueKind::Number);
    if (!field || field->number < item->min || field->number > item->max ||
        !aligned((field->number - item->min) / item->step)) {
      return outcome(id, 400, "invalid_command", output, capacity);
    }
    operation = Operation::Range;
    value = field->number;
  } else if (equals(op, "invoke") && data.count() == 5 && item->kind == Kind::Action) {
    operation = Operation::Invoke;
  } else if (equals(op, "stop") && data.count() == 5 && item->kind == Kind::Motion) {
    operation = Operation::Stop;
  } else if (equals(op, "move") && item->kind == Kind::Motion) {
    return outcome(id, 409, "unsafe_state", output, capacity);
  } else {
    return outcome(id, 400, "invalid_command", output, capacity);
  }

  Completed* slot = nullptr;
  for (Completed& entry : completed_) {
    if (!entry.id[0] || nowMs - entry.time >= acknowledgementWindowMs) {
      if (!slot) slot = &entry;
    } else if (entry.principal == principal && equals(entry.id, id)) {
      if (entry.capability != item || entry.operation != operation || entry.value != value) {
        return outcome(id, 409, "command_id_conflict", output, capacity);
      }
      return outcome(id, entry.applied ? 200 : 409, entry.applied ? nullptr : "unsafe_state",
                     output, capacity);
    }
  }
  // Reserve capacity for a stop even during a burst of ordinary commands.
  if (operation != Operation::Stop && (!slot || slot == &completed_[15])) {
    return outcome(id, 429, "busy", output, capacity);
  }
  bool applied = false;
  switch (operation) {
    case Operation::Switch:
      applied = item->switchHandler(item->context, value != 0);
      if (applied) publishSwitch(item->id, value != 0);
      break;
    case Operation::Range:
      applied = item->rangeHandler(item->context, value);
      if (applied) publishNumber(item->id, value);
      break;
    case Operation::Invoke:
      applied = item->actionHandler(item->context);
      break;
    case Operation::Stop:
      applied = item->actionHandler(item->context);
      if (applied) item->available = true;
      break;
  }
  if (slot) {
    std::strcpy(slot->id, id);
    slot->capability = item;
    slot->operation = operation;
    slot->value = value;
    slot->time = nowMs;
    slot->principal = principal;
    slot->applied = applied;
  }
  return outcome(id, applied ? 200 : 409, applied ? nullptr : "unsafe_state", output, capacity);
}

size_t Protocol::offer(const char* bytes, size_t length, uint16_t port, char* output,
                       size_t capacity) const {
  WireObject query;
  if (!revision_ || !port || length > maxDiscoveryBytes || !query.parse(bytes, length) ||
      query.count() != 4 || !equals(query.string("protocol"), "esp-iot") ||
      !equals(query.string("kind"), "discover"))
    return 0;
  const Field* version = query.get("version", ValueKind::Number);
  const char* nonce = query.string("nonce");
  if (!version || !version->integer || version->number != 1 || !hexId(nonce)) return 0;
  JsonWriter writer(output, capacity);
  writer.raw("{\"protocol\":\"esp-iot\",\"version\":1,\"kind\":\"offer\",\"nonce\":");
  writer.string(nonce);
  writer.raw(",\"deviceId\":");
  writer.string(deviceId_);
  writer.raw(",\"port\":");
  writer.integer(port);
  writer.raw(",\"tls\":");
  writer.boolean(pairing_);
  writer.raw("}");
  return writer.size();
}

}  // namespace espiot
