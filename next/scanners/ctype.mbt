// The <ctype.h>/<wctype.h> classification functions that the C scanners call,
// as they behave in the default "C" locale (the reference programs never call
// setlocale).
//
// Verified with a C program on this machine (macOS, arm64): in the "C" locale
// libc's iswspace/iswalpha/iswalnum/iswdigit/iswlower/iswupper return 0 for
// every code point >= 128, and iswspace is true only for 9-13 and 32. Negative
// arguments (e.g. a decode error, -1, which is WEOF) are false as well.
// glibc's "C" locale behaves the same.

///|
fn iswspace(c : Int32) -> Bool {
  c == ' ' || (c >= '\t' && c <= '\r')
}

///|
fn iswdigit(c : Int32) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn isdigit(c : Int32) -> Bool {
  iswdigit(c)
}

///|
fn iswlower(c : Int32) -> Bool {
  c >= 'a' && c <= 'z'
}

///|
fn iswupper(c : Int32) -> Bool {
  c >= 'A' && c <= 'Z'
}

///|
fn iswalpha(c : Int32) -> Bool {
  iswlower(c) || iswupper(c)
}

///|
fn iswalnum(c : Int32) -> Bool {
  iswalpha(c) || iswdigit(c)
}

///|
/// C `(char)c` on this platform: `char` is signed on Darwin arm64, so the
/// result is the low byte sign-extended to an `int`.
fn to_c_char(c : Int32) -> Int32 {
  ((c & 0xFF) ^ 0x80) - 0x80
}

///|
/// `TREE_SITTER_SERIALIZATION_BUFFER_SIZE`.
const SERIALIZATION_BUFFER_SIZE : Int32 = 1024

///|
fn iswxdigit(c : Int32) -> Bool {
  iswdigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
/// `towupper` in the "C" locale maps only 'a'-'z' (verified on macOS); every
/// other value, including WEOF, maps to itself.
fn towupper(c : Int32) -> Int32 {
  if iswlower(c) {
    c - 'a' + 'A'
  } else {
    c
  }
}
