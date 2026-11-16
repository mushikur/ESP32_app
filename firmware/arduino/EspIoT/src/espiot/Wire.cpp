#include "Wire.h"

#include <cerrno>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace espiot {
namespace {

int digit(char ch) {
  if (ch >= '0' && ch <= '9') return ch - '0';
  if (ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
  if (ch >= 'A' && ch <= 'F') return ch - 'A' + 10;
  return -1;
}

bool decimal(char ch) { return ch >= '0' && ch <= '9'; }
bool lower(char ch) { return ch >= 'a' && ch <= 'z'; }

struct Cursor {
  const char* next;
  const char* end;

  char peek() const { return next == end ? '\0' : *next; }
  bool eat(char ch) {
    if (next == end || *next != ch) return false;
    ++next;
    return true;
  }
  void spaces() {
    while (next != end && (*next == ' ' || *next == '\t' || *next == '\r' || *next == '\n')) ++next;
  }
  bool word(const char* text) {
    const size_t length = std::strlen(text);
    if (static_cast<size_t>(end - next) < length || std::memcmp(next, text, length)) return false;
    next += length;
    return true;
  }
};

bool readString(Cursor& cursor, char* output, size_t capacity) {
  if (!cursor.eat('"')) return false;
  size_t used = 0;
  while (cursor.next != cursor.end) {
    unsigned value = static_cast<unsigned char>(*cursor.next++);
    if (value == '"') {
      output[used] = 0;
      return true;
    }
    if (value == '\\') {
      if (cursor.next == cursor.end) return false;
      value = static_cast<unsigned char>(*cursor.next++);
      if (value == 'u') {
        value = 0;
        for (int i = 0; i < 4; ++i) {
          if (cursor.next == cursor.end) return false;
          const int hex = digit(*cursor.next++);
          if (hex < 0) return false;
          value = value * 16 + static_cast<unsigned>(hex);
        }
      } else if (value != '\\' && value != '"' && value != '/') {
        return false;
      }
    }
    if (value < 0x20 || value > 0x7e || used + 1 >= capacity) return false;
    output[used++] = static_cast<char>(value);
  }
  return false;
}

bool readNumber(Cursor& cursor, Field& field) {
  const char* first = cursor.next;
  cursor.eat('-');
  if (!cursor.eat('0')) {
    if (!decimal(cursor.peek())) return false;
    while (decimal(cursor.peek())) ++cursor.next;
  }
  field.integer = !cursor.eat('.');
  if (!field.integer) {
    if (!decimal(cursor.peek())) return false;
    while (decimal(cursor.peek())) ++cursor.next;
  }
  if (cursor.eat('e') || cursor.eat('E')) {
    field.integer = false;
    if (!cursor.eat('+')) cursor.eat('-');
    if (!decimal(cursor.peek())) return false;
    while (decimal(cursor.peek())) ++cursor.next;
  }
  char token[64]{};
  const auto length = static_cast<size_t>(cursor.next - first);
  if (length >= sizeof(token)) return false;
  std::memcpy(token, first, length);
  char* end = nullptr;
  errno = 0;
  field.number = std::strtod(token, &end);
  field.kind = ValueKind::Number;
  return end == token + length && errno != ERANGE && std::isfinite(field.number);
}

bool readValue(Cursor& cursor, Field& field) {
  switch (cursor.peek()) {
    case '"':
      field.kind = ValueKind::String;
      return readString(cursor, field.text, sizeof(field.text));
    case 't':
    case 'f':
      field.kind = ValueKind::Boolean;
      field.boolean = cursor.peek() == 't';
      return cursor.word(field.boolean ? "true" : "false");
    case 'n':
      field.kind = ValueKind::Null;
      return cursor.word("null");
    default:
      return readNumber(cursor, field);
  }
}

}  // namespace

bool hexId(const char* text) {
  if (!text || std::strlen(text) != 32) return false;
  for (const char* next = text; *next; ++next) {
    if (!decimal(*next) && (*next < 'a' || *next > 'f')) return false;
  }
  return true;
}

bool capabilityId(const char* text) {
  if (!text || !lower(*text) || std::strlen(text) > 32) return false;
  for (const char* next = text + 1; *next; ++next) {
    if (!lower(*next) && !decimal(*next) && *next != '_' && *next != '-') return false;
  }
  return true;
}

bool label(const char* text, size_t maxCharacters, bool allowEmpty) {
  if (!text) return false;
  size_t count = 0;
  bool nonSpace = false;
  const auto* next = reinterpret_cast<const unsigned char*>(text);
  while (*next) {
    const unsigned lead = *next++;
    unsigned code = lead;
    unsigned width = 1;
    if (lead >= 0xc2 && lead <= 0xdf) {
      width = 2;
      code &= 0x1f;
    } else if (lead >= 0xe0 && lead <= 0xef) {
      width = 3;
      code &= 0x0f;
    } else if (lead >= 0xf0 && lead <= 0xf4) {
      width = 4;
      code &= 0x07;
    } else if (lead > 0x7f)
      return false;
    for (unsigned i = 1; i < width; ++i) {
      if ((*next & 0xc0) != 0x80) return false;
      code = (code << 6) | (*next++ & 0x3f);
    }
    if ((width == 3 && code < 0x800) || (width == 4 && code < 0x10000) || code > 0x10ffff ||
        (code >= 0xd800 && code <= 0xdfff) || code < 0x20 || (code >= 0x7f && code <= 0x9f) ||
        (code >= 0x2028 && code <= 0x202e) || (code >= 0x2066 && code <= 0x2069) ||
        ++count > maxCharacters)
      return false;
    nonSpace = nonSpace || (code != 0x20 && code != 0xa0 && code != 0x1680 &&
                            !(code >= 0x2000 && code <= 0x200a) && code != 0x202f &&
                            code != 0x205f && code != 0x3000 && code != 0xfeff);
  }
  return allowEmpty || nonSpace;
}

bool WireObject::parse(const char* bytes, size_t length) {
  count_ = 0;
  if (!bytes || !length) return false;
  Cursor cursor{bytes, bytes + length};
  cursor.spaces();
  if (!cursor.eat('{')) return false;
  cursor.spaces();
  if (!cursor.eat('}')) {
    do {
      if (count_ == sizeof(fields_) / sizeof(fields_[0])) return false;
      Field& field = fields_[count_];
      cursor.spaces();
      if (!readString(cursor, field.key, sizeof(field.key))) return false;
      for (size_t i = 0; i < count_; ++i) {
        if (std::strcmp(fields_[i].key, field.key) == 0) return false;
      }
      cursor.spaces();
      if (!cursor.eat(':')) return false;
      cursor.spaces();
      if (!readValue(cursor, field)) return false;
      ++count_;
      cursor.spaces();
    } while (cursor.eat(','));
    if (!cursor.eat('}')) return false;
  }
  cursor.spaces();
  return cursor.next == cursor.end;
}

const Field* WireObject::get(const char* key, ValueKind kind) const {
  for (size_t i = 0; i < count_; ++i) {
    if (fields_[i].kind == kind && std::strcmp(fields_[i].key, key) == 0) return &fields_[i];
  }
  return nullptr;
}

const char* WireObject::string(const char* key) const {
  const Field* field = get(key, ValueKind::String);
  return field ? field->text : nullptr;
}

JsonWriter::JsonWriter(char* output, size_t capacity)
    : output_(output), capacity_(capacity), good_(output && capacity) {
  if (good_) output_[0] = 0;
}

void JsonWriter::append(const char* bytes, size_t length) {
  if (!good_) return;
  if (length >= capacity_ - used_) {
    good_ = false;
    output_[0] = 0;
    return;
  }
  std::memcpy(output_ + used_, bytes, length);
  used_ += length;
  output_[used_] = 0;
}

void JsonWriter::raw(const char* text) { append(text, std::strlen(text)); }

void JsonWriter::string(const char* text) {
  raw("\"");
  for (const char* next = text; *next && good_; ++next) {
    if (*next == '\\' || *next == '"') raw("\\");
    append(next, 1);
  }
  raw("\"");
}

void JsonWriter::number(double value) {
  char token[32];
  const int length = std::snprintf(token, sizeof(token), "%.17g", value);
  if (length > 0 && static_cast<size_t>(length) < sizeof(token)) raw(token);
}

void JsonWriter::integer(uint64_t value) {
  char token[21];
  char* start = token + sizeof(token) - 1;
  *start = 0;
  do {
    *--start = static_cast<char>('0' + value % 10);
    value /= 10;
  } while (value);
  raw(start);
}

}  // namespace espiot
