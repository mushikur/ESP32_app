#pragma once

#include <cstddef>
#include <cstdint>

namespace espiot {

bool hexId(const char* text);
bool capabilityId(const char* text);
bool label(const char* text, size_t maxCharacters, bool allowEmpty = false);

enum class ValueKind { String, Number, Boolean, Null };

struct Field {
  char key[20];
  char text[40];
  ValueKind kind;
  double number;
  bool boolean;
  bool integer;
};

// v1 command and discovery envelopes have scalar fields and ASCII identifiers.
class WireObject {
 public:
  bool parse(const char* bytes, size_t length);
  const Field* get(const char* key, ValueKind kind) const;
  const char* string(const char* key) const;
  size_t count() const { return count_; }

 private:
  Field fields_[9]{};
  size_t count_ = 0;
};

class JsonWriter {
 public:
  JsonWriter(char* output, size_t capacity);
  void raw(const char* text);
  void string(const char* text);
  void number(double value);
  void integer(uint64_t value);
  void boolean(bool value) { raw(value ? "true" : "false"); }
  size_t size() const { return good_ ? used_ : 0; }

 private:
  void append(const char* bytes, size_t length);
  char* output_;
  size_t capacity_;
  size_t used_ = 0;
  bool good_;
};

}  // namespace espiot
