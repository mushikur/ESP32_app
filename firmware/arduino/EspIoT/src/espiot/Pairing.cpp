#include "Pairing.h"

#include <cstring>

namespace espiot {
namespace {

bool digits(const char* code) {
  if (!code || std::strlen(code) != 8) return false;
  for (size_t i = 0; i < 8; ++i)
    if (code[i] < '0' || code[i] > '9') return false;
  return true;
}

bool same(const TokenDigest& a, const TokenDigest& b) {
  uint8_t difference = 0;
  for (size_t i = 0; i < sizeof(a.bytes); ++i) difference |= a.bytes[i] ^ b.bytes[i];
  return difference == 0;
}

bool empty(const TokenDigest& digest) { return same(digest, TokenDigest{}); }

}  // namespace

bool PairingWindow::open(const char* code, uint64_t now) {
  if (!digits(code)) return false;
  std::memcpy(code_, code, sizeof(code_));
  opened_ = now;
  attempts_ = 0;
  active_ = true;
  return true;
}

void PairingWindow::close() {
  active_ = false;
  std::memset(code_, 0, sizeof(code_));
}

PairingAttempt PairingWindow::check(const char* code, uint64_t now) {
  if (!active_ || now - opened_ >= durationMs) {
    close();
    return PairingAttempt::refused;
  }
  if (attempts_ && now - lastAttempt_ < 750) return PairingAttempt::busy;
  lastAttempt_ = now;
  ++attempts_;
  bool matched = false;
  if (digits(code)) {
    unsigned difference = 0;
    for (size_t i = 0; i < 8; ++i) difference |= static_cast<unsigned>(code_[i] ^ code[i]);
    matched = difference == 0;
  }
  if (matched || attempts_ >= 5) close();
  return matched ? PairingAttempt::accepted : PairingAttempt::refused;
}

bool TokenLedger::load(const TokenDigest* entries) {
  if (!entries || latest_) return false;
  for (size_t i = 0; i < capacity; ++i) {
    if (empty(entries[i])) continue;
    for (size_t j = 0; j < i; ++j)
      if (same(entries[i], entries[j])) return false;
  }
  for (size_t i = 0; i < capacity; ++i) {
    entries_[i] = entries[i];
    if (!empty(entries[i])) principals_[i] = ++latest_;
  }
  return true;
}

bool TokenLedger::full() const {
  for (uint32_t principal : principals_)
    if (!principal) return false;
  return true;
}

uint32_t TokenLedger::principal(const TokenDigest& digest) const {
  uint32_t match = 0;
  for (size_t i = 0; i < capacity; ++i) {
    if (same(entries_[i], digest)) match = principals_[i];
  }
  return match;
}

bool TokenLedger::hasPrincipal(uint32_t principal) const {
  if (!principal) return false;
  for (uint32_t entry : principals_)
    if (entry == principal) return true;
  return false;
}

bool TokenLedger::issue(const TokenDigest& digest, Persist persist, void* context) {
  if (!persist || latest_ == UINT32_MAX || empty(digest) || principal(digest)) return false;
  for (size_t i = 0; i < capacity; ++i) {
    if (principals_[i]) continue;
    TokenDigest next[capacity];
    std::memcpy(next, entries_, sizeof(next));
    next[i] = digest;
    if (!persist(context, next)) return false;
    entries_[i] = digest;
    principals_[i] = ++latest_;
    return true;
  }
  return false;
}

bool TokenLedger::revoke(uint32_t principal, Persist persist, void* context) {
  if (!principal || !persist) return false;
  for (size_t i = 0; i < capacity; ++i) {
    if (principals_[i] != principal) continue;
    TokenDigest next[capacity];
    std::memcpy(next, entries_, sizeof(next));
    next[i] = {};
    if (!persist(context, next)) return false;
    entries_[i] = {};
    principals_[i] = 0;
    return true;
  }
  return false;
}

bool TokenLedger::clear(Persist persist, void* context) {
  TokenDigest emptyEntries[capacity]{};
  if (!persist || !persist(context, emptyEntries)) return false;
  for (size_t i = 0; i < capacity; ++i) {
    entries_[i] = {};
    principals_[i] = 0;
  }
  return true;
}

}  // namespace espiot
