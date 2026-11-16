#pragma once

#include <cstddef>
#include <cstdint>

namespace espiot {

enum class PairingAttempt { accepted, refused, busy };

class PairingWindow {
 public:
  static constexpr uint32_t durationMs = 60000;
  bool open(const char* code, uint64_t now);
  void close();
  PairingAttempt check(const char* code, uint64_t now);

 private:
  char code_[9]{};
  uint64_t opened_ = 0, lastAttempt_ = 0;
  uint8_t attempts_ = 0;
  bool active_ = false;
};

struct TokenDigest {
  uint8_t bytes[32]{};
};

class TokenLedger {
 public:
  static constexpr size_t capacity = 4;
  using Persist = bool (*)(void*, const TokenDigest*);

  bool load(const TokenDigest* entries);
  bool full() const;
  uint32_t principal(const TokenDigest& digest) const;
  bool hasPrincipal(uint32_t principal) const;
  bool issue(const TokenDigest& digest, Persist persist, void* context);
  bool revoke(uint32_t principal, Persist persist, void* context);
  bool clear(Persist persist, void* context);

 private:
  TokenDigest entries_[capacity]{};
  uint32_t principals_[capacity]{};
  uint32_t latest_ = 0;
};

}  // namespace espiot
