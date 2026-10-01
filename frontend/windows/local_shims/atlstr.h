// Minimal local shim replacing <atlstr.h> from the (missing) ATL toolset.
// Provides just the conversion helpers used by flutter_secure_storage_windows.
#pragma once
#include <windows.h>
#include <string>
#include <vector>

// CA2W: converts a narrow (UTF-8/ANSI) string to a wide string buffer.
class CA2W {
 public:
  explicit CA2W(const char* s) {
    if (!s || !*s) { buf_.push_back(L'\0'); return; }
    int need = MultiByteToWideChar(CP_UTF8, 0, s, -1, nullptr, 0);
    buf_.resize(need > 0 ? need : 1, L'\0');
    if (need > 0) {
      MultiByteToWideChar(CP_UTF8, 0, s, -1, buf_.data(), need);
    }
  }
  ~CA2W() {}
  operator const wchar_t*() const { return buf_.data(); }
  operator LPWSTR() { return buf_.data(); }
  wchar_t* m_psz = buf_.data();

 private:
  std::vector<wchar_t> buf_;
};

// CW2A: converts a wide string to a narrow (UTF-8) string buffer.
class CW2A {
 public:
  explicit CW2A(const wchar_t* s) {
    if (!s || !*s) { buf_.push_back('\0'); return; }
    int need = WideCharToMultiByte(CP_UTF8, 0, s, -1, nullptr, 0, nullptr, nullptr);
    buf_.resize(need > 0 ? need : 1, '\0');
    if (need > 0) {
      WideCharToMultiByte(CP_UTF8, 0, s, -1, buf_.data(), need, nullptr, nullptr);
    }
  }
  ~CW2A() {}
  operator const char*() const { return buf_.data(); }
  operator LPSTR() { return buf_.data(); }
  char* m_psz = buf_.data();

 private:
  std::vector<char> buf_;
};

// Common ATL convenience aliases used by plugins, kept for completeness.
using CA2WEX = CA2W;
using CW2AEX = CW2A;
