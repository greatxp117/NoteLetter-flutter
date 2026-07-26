import 'dart:convert';
import 'dart:io';

/// Locates the contracts repo (env override for CI) and loads captured
/// fixture suites. Only `captured` suites are mandatory.
String contractsRoot() {
  final env = Platform.environment['NOTELETTER_CONTRACTS'];
  if (env != null && env.isNotEmpty) return env;
  // test/contract/ -> repo root -> sibling contracts repo
  return '${Directory.current.parent.path}/NoteLetter-contracts';
}

Map<String, dynamic> _manifest() =>
    jsonDecode(File('${contractsRoot()}/fixtures/manifest.json').readAsStringSync())
        as Map<String, dynamic>;

/// The version fixtures were last captured at (may legitimately lag the
/// canonical VERSION when later contract versions add no new fixtures).
String manifestContractVersion() => _manifest()['contractVersion'] as String;

/// The canonical contract version — the `VERSION` file, matching the web
/// reference's pin-check (`readFileSync(CONTRACTS, 'VERSION')`). This is what
/// `/conformance` compares the client pin against; `manifestContractVersion`
/// is NOT the pin target (it tracks fixture-capture, and can lag VERSION).
String contractsVersion() =>
    File('${contractsRoot()}/VERSION').readAsStringSync().trim();

/// Returns the suite's parsed cases.json, or null if the suite is not yet
/// `captured` (a client harness never depends on pending-capture).
Map<String, dynamic>? loadSuite(String suiteId) {
  final suites = (_manifest()['suites'] as List).cast<Map<String, dynamic>>();
  final s = suites.firstWhere((x) => x['id'] == suiteId, orElse: () => {});
  if (s.isEmpty || s['status'] != 'captured') return null;
  return jsonDecode(
          File('${contractsRoot()}/fixtures/${s['path']}').readAsStringSync())
      as Map<String, dynamic>;
}

/// Decodes fixture input sentinels: {"\$ts": ms} -> ms (int; tsMs accepts int),
/// {"\$vector": n} -> a placeholder map (embedding is stripped by INV-05).
dynamic decode(dynamic v) {
  if (v is List) return v.map(decode).toList();
  if (v is Map) {
    if (v.containsKey('\$ts')) return v['\$ts'];
    if (v.containsKey('\$vector')) return {'_embedding': v['\$vector']};
    return v.map((k, val) => MapEntry(k, decode(val)));
  }
  return v;
}
