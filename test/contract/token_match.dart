import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// The token comparator every client harness implements identically
/// (`fixtures/normalization.md` + `fixtures/tokens.json`) — a port of the
/// reference's `tests/contract/helpers/match.js`. Deep-compares an [actual]
/// value against an [expected] one that may carry normalization tokens.
///
/// A token is not always the WHOLE value (normalization.md rule 3): a signed
/// URL keeps its path (`…?«sig»`), a gcs path carries `«uuid#1»` in the
/// middle, and a rate-limit countdown is one integer inside a sentence. Until
/// F-28 this port dispatched on `startsWith('«')` alone, so an embedded token
/// fell through to string equality against the token TEXT — green only
/// because no suite here compared such a value.

final _reUuid =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
final _reReqId = RegExp(r'^[0-9a-f]{8}$');
final _reIso = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})$');
const _letterIdSrc = r'.+_\d{8}T\d{6}Z_[0-9a-f]{6}';
final _reLetterId = RegExp('^$_letterIdSrc\$');
const _epochMin = 1577836800000, _epochMax = 2208988800000;
final _reToken = RegExp(r'«[^»]*»');

double _round6(num n) => (n * 1e6).round() / 1e6;

Never _fail(String path, Object? expected, Object? actual, [String why = '']) {
  throw TestFailure('mismatch at $path${why.isNotEmpty ? ' ($why)' : ''}: '
      'expected ${jsonEncode(expected)}, got ${jsonEncode(actual)}');
}

/// Throws a [TestFailure] naming the path on mismatch. [uuids] carries
/// `«uuid#N»` identity within a case — across whole and embedded uses.
void match(dynamic actual, dynamic expected,
    [String path = r'$', Map<String, String>? uuids]) {
  uuids ??= {};
  if (expected is String && expected.startsWith('«') &&
      _reToken.matchAsPrefix(expected)?.end == expected.length) {
    _matchToken(actual, expected, path, uuids);
    return;
  }
  if (expected is String && expected.contains('«')) {
    _matchEmbedded(actual, expected, path, uuids);
    return;
  }
  if (expected is List) {
    if (actual is! List || actual.length != expected.length) {
      _fail(path, expected, actual, 'array length');
    }
    for (var i = 0; i < expected.length; i++) {
      match(actual[i], expected[i], '$path[$i]', uuids);
    }
    return;
  }
  if (expected is Map) {
    if (actual is! Map) _fail(path, expected, actual, 'object');
    final ek = expected.keys.map((e) => e.toString()).toList()..sort();
    final ak = actual.keys.map((e) => e.toString()).toList()..sort();
    if (ek.join(',') != ak.join(',')) _fail(path, ek, ak, 'key set');
    for (final k in ek) {
      match(actual[k], expected[k], '$path.$k', uuids);
    }
    return;
  }
  if (expected is num && actual is num) {
    if (_round6(actual) != _round6(expected)) _fail(path, expected, actual);
    return;
  }
  if (actual != expected) _fail(path, expected, actual);
}

/// The regex a token stands for when it is embedded in a longer string.
String _tokenSource(String token) {
  if (token == '«request_id»') return '[0-9a-f]{8}';
  if (token == '«epoch_ms»') return r'\d+';
  if (token == '«seconds»') return r'\d+';
  if (token == '«iso8601»') return r'\d{4}-\d{2}-\d{2}T[0-9:.+Z-]+';
  if (token.startsWith('«uuid#')) {
    return '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
  }
  if (token == '«sig»') return '.*';
  if (token == '«letter_id»') return _letterIdSrc;
  throw TestFailure('unknown token $token');
}

void _matchEmbedded(
    dynamic actual, String expected, String path, Map<String, String> uuids) {
  if (actual is! String) _fail(path, expected, actual, 'string');
  final tokens = <String>[];
  final source = StringBuffer('^');
  var at = 0;
  for (final m in _reToken.allMatches(expected)) {
    source.write(RegExp.escape(expected.substring(at, m.start)));
    tokens.add(m.group(0)!);
    source.write('(${_tokenSource(m.group(0)!)})');
    at = m.end;
  }
  source.write(RegExp.escape(expected.substring(at)));
  source.write(r'$');
  final m = RegExp(source.toString()).firstMatch(actual);
  if (m == null) _fail(path, expected, actual, 'embedded token');
  // «uuid#N» identity holds across an embedded occurrence too — the same N in
  // a gcs path and in a signed URL is the same document.
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (!token.startsWith('«uuid#')) continue;
    final value = m.group(i + 1)!;
    if (uuids.containsKey(token) && uuids[token] != value) {
      _fail(path, '$token=${uuids[token]}', value, 'uuid identity');
    }
    uuids[token] = value;
  }
}

void _matchToken(
    dynamic actual, String token, String path, Map<String, String> uuids) {
  if (token == '«request_id»') {
    if (actual is! String || !_reReqId.hasMatch(actual)) {
      _fail(path, token, actual);
    }
  } else if (token == '«epoch_ms»') {
    if (actual is! int || actual < _epochMin || actual > _epochMax) {
      _fail(path, token, actual);
    }
  } else if (token == '«iso8601»') {
    if (actual is! String || !_reIso.hasMatch(actual)) {
      _fail(path, token, actual);
    }
  } else if (token.startsWith('«uuid#')) {
    if (actual is! String || !_reUuid.hasMatch(actual)) {
      _fail(path, token, actual);
    }
    if (uuids.containsKey(token) && uuids[token] != actual) {
      _fail(path, '$token=${uuids[token]}', actual, 'uuid identity');
    }
    uuids[token] = actual;
  } else if (token == '«seconds»') {
    if (actual is! String || !RegExp(r'^\d+$').hasMatch(actual)) {
      _fail(path, token, actual);
    }
  } else if (token == '«letter_id»') {
    if (actual is! String || !_reLetterId.hasMatch(actual)) {
      _fail(path, token, actual);
    }
  } else if (token == '«sig»') {
    // signed-url query token: presence of a string is enough
    if (actual is! String) _fail(path, token, actual);
  } else {
    throw TestFailure('unknown token $token at $path');
  }
}
