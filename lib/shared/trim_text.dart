/// Whitespace is what JavaScript trims (5.89.0, ADR-270).
///
/// The web reference's `trim()` and `\s` are the rule, and the server trims
/// and tests with the same set (`core_http.py` `_trim`/`_SPACE_CLASS`):
/// ECMAScript's WhiteSpace and LineTerminator. Dart's `String.trim()` also
/// strips U+0085 (Unicode White_Space), so a value web and the server accept
/// was refused or altered here. **U+001C–U+001F and U+0085 are text.**
///
/// Every text value this client checks before it sends — its emptiness, its
/// bound, the value itself — goes through [trimText], never `trim()`. The set
/// is written out, not borrowed: a library's idea of whitespace is the one
/// thing here that would move under us. Dart's `RegExp` `\s` already agrees,
/// so a pattern needs no change.
library;

/// Whether [c] (a UTF-16 code unit) is ECMAScript whitespace: U+0009–U+000D,
/// U+0020, U+00A0, U+1680, U+2000–U+200A, U+2028, U+2029, U+202F, U+205F,
/// U+3000, U+FEFF. Every one is in the BMP, so a code unit decides it.
bool isJsSpace(int c) =>
    (c >= 0x09 && c <= 0x0D) ||
    c == 0x20 ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000 ||
    c == 0xFEFF;

/// [s] without its leading and trailing ECMAScript whitespace — JavaScript's
/// `String.prototype.trim`, byte for byte.
String trimText(String s) {
  var start = 0;
  var end = s.length;
  while (start < end && isJsSpace(s.codeUnitAt(start))) {
    start++;
  }
  while (end > start && isJsSpace(s.codeUnitAt(end - 1))) {
    end--;
  }
  return (start == 0 && end == s.length) ? s : s.substring(start, end);
}
