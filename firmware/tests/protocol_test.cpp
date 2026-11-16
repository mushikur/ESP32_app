#include "espiot/Protocol.h"
#include "espiot/Pairing.h"

#include <cassert>
#include <cstdio>
#include <iostream>
#include <limits>
#include <string>

#include "espiot/Wire.h"

namespace {

constexpr const char* deviceId = "11111111111111111111111111111111";
constexpr const char* bootId = "22222222222222222222222222222222";
constexpr const char* firstId = "33333333333333333333333333333333";
constexpr const char* nonce = "44444444444444444444444444444444";
constexpr const char* discovery =
    "{\"protocol\":\"esp-iot\",\"version\":1,\"kind\":\"discover\",\"nonce\":"
    "\"44444444444444444444444444444444\"}";

struct Bench {
  espiot::Protocol protocol;
  char output[espiot::Protocol::outputCapacity]{};
  unsigned switches = 0, ranges = 0, actions = 0, stops = 0;
  bool switchAccepts = true;

  Bench() {
    assert(protocol.addSwitch(
        "led", "LED \"test\" \\ bench",
        [](void* context, bool) {
          auto& bench = *static_cast<Bench*>(context);
          ++bench.switches;
          return bench.switchAccepts;
        },
        this));
    assert(protocol.addRange(
        "fan_speed", "Fan speed", 0, 100, 5, "%",
        [](void* context, double) {
          ++static_cast<Bench*>(context)->ranges;
          return true;
        },
        this));
    assert(protocol.addSensor("temperature", "Temperature",
                              "\xc2\xb0"
                              "C"));
    assert(protocol.addAction(
        "identify", "Identify",
        [](void* context) {
          ++static_cast<Bench*>(context)->actions;
          return true;
        },
        this));
    assert(protocol.addMotionStop(
        "drive", "Drive", espiot::Forward | espiot::Reverse, 500,
        [](void* context) {
          ++static_cast<Bench*>(context)->stops;
          return true;
        },
        this));
    assert(protocol.publishSwitch("led", false));
    assert(protocol.publishNumber("temperature", 23.5));
    assert(protocol.configure("ESP IoT SDK fixture", "controller", 2, deviceId, bootId, true));
  }

  unsigned send(const std::string& command, uint64_t time = 100) {
    const auto reply =
        protocol.command(command.data(), command.size(), time, output, sizeof(output));
    assert(reply.size && reply.size == std::string(output).size());
    return reply.status;
  }

  bool has(const char* text) const { return std::string(output).find(text) != std::string::npos; }
};

std::string message(const std::string& id, const std::string& capability, const std::string& op,
                    const std::string& extra = "", const char* boot = bootId, int revision = 2) {
  return "{\"commandId\":\"" + id + "\",\"bootId\":\"" + boot +
         "\",\"revision\":" + std::to_string(revision) + ",\"capabilityId\":\"" + capability +
         "\",\"op\":\"" + op + "\"" + extra + "}";
}

std::string numbered(unsigned value) {
  char result[33];
  std::snprintf(result, sizeof(result), "%032x", value);
  return result;
}

void testRegistration() {
  espiot::Protocol test;
  assert(!test.addSensor("1invalid", "Invalid", ""));
  assert(!test.addSensor("sensor", "   ", ""));
  assert(!test.addSensor("sensor", "\xc0\xaf", ""));
  assert(!test.addSensor("sensor", "Bad\xe2\x80\xae", ""));
  assert(!test.addSensor("sensor", "Sensor", "12345678901234567"));
  assert(!test.addRange("range", "Range", 0, 10, 3, "", [](void*, double) { return true; }));
  assert(!test.addRange("range", "Range", 0, 10, 0, "", [](void*, double) { return true; }));
  assert(test.addSensor("sensor", "Valid sensor", ""));
  assert(!test.addSensor("sensor", "Duplicate", ""));
  assert(!test.configure("Device", "test", 0, deviceId, bootId, false));
  assert(test.configure("Device", "test", 1, deviceId, bootId, false));
  assert(!test.addSensor("late", "Late registration", ""));
  char output[256];
  assert(test.descriptor(output, sizeof(output)));
  assert(std::string(output).find("\"events\":false") != std::string::npos);
}

void testStatus() {
  Bench bench;
  assert(bench.protocol.descriptor(bench.output, sizeof(bench.output)));
  assert(bench.has("LED \\\"test\\\" \\\\ bench"));
  assert(bench.has("\"maxDurationMs\":500"));
  char tiny[24];
  assert(bench.protocol.snapshot(tiny, sizeof(tiny)) == 0);
  assert(bench.protocol.snapshot(bench.output, sizeof(bench.output)));
  assert(bench.has("\"seq\":1") && bench.has("\"led\":false") && bench.has("\"fan_speed\":null"));
  assert(bench.has("\"temperature\":23.5") && !bench.has("\"identify\""));
  assert(!bench.protocol.publishNumber("temperature", std::numeric_limits<double>::infinity()));
  assert(!bench.protocol.publishNumber("fan_speed", 101));
  assert(bench.protocol.publishUnavailable("temperature"));
  assert(bench.protocol.snapshot(bench.output, sizeof(bench.output)));
  assert(bench.has("\"seq\":2") && bench.has("\"temperature\":null"));
}

void testCommands() {
  Bench bench;
  const auto set = message(firstId, "led", "set", ",\"value\":true");
  assert(bench.send(set, 100) == 200 && bench.has("\"outcome\":\"applied\""));
  assert(bench.has(firstId) && bench.has(bootId) && bench.has(deviceId));
  assert(bench.send(set, 110) == 200 && bench.switches == 1);
  assert(bench.send(message(firstId, "led", "set", ",\"value\":false"), 120) == 409);
  assert(bench.has("command_id_conflict") && bench.switches == 1);
  assert(bench.send(message(numbered(2), "led", "set", ",\"value\":false", deviceId)) == 409 &&
         bench.has("device_restarted"));
  assert(bench.send(message(numbered(2), "led", "set", ",\"value\":false", bootId, 1)) == 409 &&
         bench.has("descriptor_changed"));
  assert(bench.send(message(numbered(2), "temperature", "set", ",\"value\":1")) == 400);
  assert(bench.send(message(numbered(2), "fan_speed", "set", ",\"value\":21")) == 400 &&
         bench.ranges == 0);
  assert(bench.send(message(numbered(2), "fan_speed", "set", ",\"value\":25.0")) == 200 &&
         bench.ranges == 1);
  assert(bench.send(message(numbered(3), "identify", "invoke")) == 200 && bench.actions == 1);
  assert(bench.send(message(numbered(4), "drive", "move",
                            ",\"direction\":\"forward\",\"durationMs\":100,\"leaseId\":"
                            "\"44444444444444444444444444444444\"")) == 409);
  assert(bench.has("unsafe_state") && bench.stops == 0);
  assert(bench.send(message(numbered(5), "drive", "stop")) == 200 && bench.stops == 1);
  bench.switchAccepts = false;
  const auto refused = message(numbered(6), "led", "set", ",\"value\":false");
  assert(bench.send(refused) == 409 && bench.has("unsafe_state"));
  assert(bench.send(refused) == 409 && bench.switches == 2);
  assert(bench.protocol.snapshot(bench.output, sizeof(bench.output)));
  assert(bench.has("\"led\":true") && bench.has("\"fan_speed\":25") &&
         bench.has("\"drive\":\"stopped\""));
}

void testMalformedBodies() {
  Bench bench;
  const char* invalid[] = {
      ",\"value\":true,\"value\":false",
      ",\"value\":true,\"\\u0076alue\":false",
      ",\"value\":{}",
      ",\"value\":NaN",
      ",\"value\":+1",
      ",\"value\":01",
      ",\"value\":1e+",
      ",\"value\":1e9999",
      ",\"value\":true,\"other\":true",
      ",\"value\":\"\\u0000\"",
      ",\"value\":\"\xc0\xaf\"",
  };
  for (const char* fields : invalid)
    assert(bench.send(message(firstId, "led", "set", fields)) == 400);
  const auto valid = message(firstId, "led", "set", ",\"value\":true");
  assert(bench.send(valid + "{}") == 400);
  assert(bench.send(valid + std::string(2048, ' ')) == 400);
  assert(bench.switches == 0);
}

void testCapacity() {
  Bench bench;
  const uint64_t start = UINT32_MAX - 2;
  for (unsigned i = 0; i < 15; ++i)
    assert(bench.send(message(numbered(i), "identify", "invoke"), start) == 200);
  const auto extra = message(numbered(15), "identify", "invoke");
  assert(bench.send(extra, start + 10) == 429 && bench.has("busy") && bench.actions == 15);
  assert(bench.send(message(numbered(16), "drive", "stop"), start + 10) == 200);
  assert(bench.send(message(numbered(17), "drive", "stop"), start + 10) == 200 && bench.stops == 2);
  assert(bench.send(extra, start + espiot::Protocol::acknowledgementWindowMs) == 200 &&
         bench.actions == 16);
}

void testDiscovery() {
  Bench bench;
  const std::string query = discovery;
  assert(
      bench.protocol.offer(query.data(), query.size(), 8080, bench.output, sizeof(bench.output)));
  espiot::WireObject offer;
  assert(offer.parse(bench.output, std::string(bench.output).size()));
  assert(std::string(offer.string("kind")) == "offer");
  assert(std::string(offer.string("nonce")) == nonce);
  assert(std::string(offer.string("deviceId")) == deviceId);
  assert(offer.get("port", espiot::ValueKind::Number)->number == 8080);
  assert(!offer.get("tls", espiot::ValueKind::Boolean)->boolean);
  auto wrong = query;
  wrong[wrong.find(":1") + 1] = '2';
  assert(
      !bench.protocol.offer(wrong.data(), wrong.size(), 8080, bench.output, sizeof(bench.output)));
  const auto oversized = query + std::string(512, ' ');
  assert(!bench.protocol.offer(oversized.data(), oversized.size(), 8080, bench.output,
                               sizeof(bench.output)));
}

void testPairingWindow() {
  espiot::PairingWindow window;
  using espiot::PairingAttempt;
  assert(window.check("11223344", 0) == PairingAttempt::refused);
  assert(!window.open("123", 0));
  assert(window.open("11223344", 100));
  assert(window.check("00000000", 100) == PairingAttempt::refused);
  assert(window.check("11223344", 101) == PairingAttempt::busy);
  assert(window.check("11223344", 850) == PairingAttempt::accepted);
  assert(window.check("11223344", 2000) == PairingAttempt::refused);
  assert(window.open("11223344", 100));
  assert(window.check("11223344", 60100) == PairingAttempt::refused);
  assert(window.open("11223344", 100));
  assert(window.check("11223344", (1ULL << 32) + 110) == PairingAttempt::refused);
  assert(window.open("11223344", 0));
  for (unsigned attempt = 0; attempt < 5; ++attempt) {
    assert(window.check("00000000", attempt * 800) == PairingAttempt::refused);
  }
  assert(window.check("11223344", 5000) == PairingAttempt::refused);
}

struct LedgerFixture {
  espiot::TokenDigest stored[espiot::TokenLedger::capacity]{};
  bool writable = true;
  static bool persist(void* context, const espiot::TokenDigest* entries) {
    auto& self = *static_cast<LedgerFixture*>(context);
    if (!self.writable) return false;
    for (size_t i = 0; i < espiot::TokenLedger::capacity; ++i) self.stored[i] = entries[i];
    return true;
  }
};

void testPairingLedger() {
  LedgerFixture fixture;
  espiot::TokenLedger ledger;
  espiot::TokenDigest first{}, second{};
  first.bytes[0] = 1;
  second.bytes[0] = 2;
  fixture.writable = false;
  assert(!ledger.issue(first, LedgerFixture::persist, &fixture));
  assert(!ledger.principal(first));
  fixture.writable = true;
  assert(ledger.issue(first, LedgerFixture::persist, &fixture));
  const auto previous = ledger.principal(first);
  assert(previous && ledger.hasPrincipal(previous));
  assert(!ledger.issue(first, LedgerFixture::persist, &fixture));
  espiot::TokenLedger rebooted;
  assert(rebooted.load(fixture.stored) && rebooted.principal(first));
  fixture.writable = false;
  assert(!ledger.revoke(previous, LedgerFixture::persist, &fixture));
  assert(ledger.hasPrincipal(previous));
  fixture.writable = true;
  assert(ledger.revoke(previous, LedgerFixture::persist, &fixture));
  assert(!ledger.hasPrincipal(previous));
  assert(ledger.issue(second, LedgerFixture::persist, &fixture));
  assert(ledger.principal(second) != previous);
  assert(ledger.clear(LedgerFixture::persist, &fixture));
  assert(!ledger.principal(second));
}

void testPairedCommands() {
  espiot::Protocol protocol;
  int applies = 0;
  assert(protocol.addAction("identify", "Identify", [](void* context) {
    ++*static_cast<int*>(context);
    return true;
  }, &applies));
  assert(protocol.configure("Secure device", "test", 2, deviceId, bootId, false, true));
  const auto command = message(firstId, "identify", "invoke");
  char output[2048];
  assert(protocol.command(command.data(), command.size(), 100, output, sizeof(output)).status == 401);
  assert(applies == 0);
  assert(protocol.command(command.data(), command.size(), 100, output, sizeof(output), 1).status == 200);
  assert(protocol.command(command.data(), command.size(), 101, output, sizeof(output), 1).status == 200);
  assert(applies == 1);
  assert(protocol.command(command.data(), command.size(), 102, output, sizeof(output), 2).status == 200);
  assert(applies == 2);
  assert(protocol.descriptor(output, sizeof(output)) && std::string(output).find("pairing-token") != std::string::npos);
  assert(protocol.offer(discovery, std::string(discovery).size(), 8443, output, sizeof(output)));
  assert(std::string(output).find("\"tls\":true") != std::string::npos);
}

int wireMode() {
  Bench bench;
  std::string line;
  while (std::getline(std::cin, line)) {
    if (!line.empty() && line.back() == '\r') line.pop_back();
    if (line == "descriptor")
      bench.protocol.descriptor(bench.output, sizeof(bench.output));
    else if (line == "status")
      bench.protocol.snapshot(bench.output, sizeof(bench.output));
    else if (line.compare(0, 8, "command ") == 0)
      std::cout << bench.send(line.substr(8)) << ' ';
    else if (line.compare(0, 6, "offer ") == 0) {
      if (!bench.protocol.offer(line.data() + 6, line.size() - 6, 8080, bench.output,
                                sizeof(bench.output)))
        return 2;
    } else
      return 2;
    std::cout << bench.output << std::endl;
  }
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc == 2 && std::string(argv[1]) == "--wire") return wireMode();
  const struct {
    const char* name;
    void (*run)();
  } tests[] = {
      {"capability validation", testRegistration},
      {"sequenced snapshots", testStatus},
      {"commands and correlated acknowledgements", testCommands},
      {"strict bounded JSON", testMalformedBodies},
      {"command budget and stop", testCapacity},
      {"UDP discovery envelope", testDiscovery},
    {"short-lived and rate-limited pairing", testPairingWindow},
    {"persistent digest slots and revocation", testPairingLedger},
    {"authorized command scopes", testPairedCommands},
  };
  for (const auto& test : tests) {
    test.run();
    std::cout << "PASS " << test.name << '\n';
  }
}
