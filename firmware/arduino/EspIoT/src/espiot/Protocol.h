#pragma once

#include <cstddef>
#include <cstdint>

namespace espiot {

using SwitchHandler = bool (*)(void*, bool);
using RangeHandler = bool (*)(void*, double);
using ActionHandler = bool (*)(void*);

enum Direction : uint8_t { Forward = 1, Reverse = 2, Left = 4, Right = 8 };

struct Reply {
  unsigned status;
  size_t size;
};

class Protocol {
 public:
  Protocol() = default;
  Protocol(const Protocol&) = delete;
  Protocol& operator=(const Protocol&) = delete;
  static constexpr size_t maxCapabilities = 16;
  static constexpr size_t maxCommandBytes = 2048;
  static constexpr size_t maxDiscoveryBytes = 512;
  static constexpr size_t outputCapacity = 16384;
  static constexpr uint32_t acknowledgementWindowMs = 30000;

  bool configure(const char* name, const char* type, int32_t revision, const char* deviceId,
                 const char* bootId, bool events, bool pairing = false);
  const char* deviceId() const { return deviceId_; }
  bool events() const { return events_; }

  bool addSwitch(const char* id, const char* name, SwitchHandler handler, void* context = nullptr,
                 bool confirm = false);
  bool addRange(const char* id, const char* name, double min, double max, double step,
                const char* unit, RangeHandler handler, void* context = nullptr,
                bool confirm = true);
  bool addSensor(const char* id, const char* name, const char* unit);
  bool addAction(const char* id, const char* name, ActionHandler handler, void* context = nullptr,
                 bool confirm = true);
  bool addMotionStop(const char* id, const char* name, uint8_t directions, uint16_t maxDurationMs,
                     ActionHandler stop, void* context = nullptr);

  bool publishSwitch(const char* id, bool value);
  bool publishNumber(const char* id, double value);
  bool publishUnavailable(const char* id);

  size_t descriptor(char* output, size_t capacity) const;
  size_t snapshot(char* output, size_t capacity);
  Reply command(const char* bytes, size_t length, uint64_t nowMs, char* output, size_t capacity,
                uint32_t principal = 0);
  size_t offer(const char* bytes, size_t length, uint16_t port, char* output,
               size_t capacity) const;

 private:
  enum class Kind { Switch, Range, Sensor, Action, Motion };
  enum class Operation { Switch, Range, Invoke, Stop };

  struct Capability {
    char id[33]{};
    char name[257]{};
    char unit[65]{};
    Kind kind{};
    bool confirm = false;
    bool available = false;
    bool switched = false;
    uint8_t directions = 0;
    uint16_t maxDurationMs = 0;
    double min = 0, max = 0, step = 0, number = 0;
    SwitchHandler switchHandler = nullptr;
    RangeHandler rangeHandler = nullptr;
    ActionHandler actionHandler = nullptr;
    void* context = nullptr;
  };

  struct Completed {
    char id[33]{};
    const Capability* capability = nullptr;
    Operation operation{};
    double value = 0;
    uint64_t time = 0;
    uint32_t principal = 0;
    bool applied = false;
  };

  Capability* add(const char* id, const char* name, Kind kind);
  Capability* find(const char* id);
  Reply outcome(const char* id, unsigned status, const char* code, char* output,
                size_t capacity) const;

  Capability capabilities_[maxCapabilities]{};
  Completed completed_[16]{};
  size_t count_ = 0;
  char name_[257]{};
  char type_[33]{};
  char deviceId_[33]{};
  char bootId_[33]{};
  int32_t revision_ = 0;
  uint64_t sequence_ = 0;
  bool events_ = false;
  bool pairing_ = false;
};

}  // namespace espiot
