import '../../models/cloud_file.dart';
import '../../shared/upload_types.dart';

/// The sentences the cloud surfaces owe since contracts 4.89.0–4.92.0 (the
/// cloud-sync audit, ADR-123..126), as pure functions so the contract suite can
/// read them without mounting a screen. Each mirrors the web reference
/// (`NoteLetter-web@12daabd`) word for word; the function names are web's.

/// Where a reader removes NoteLetter at each provider (ADR-123 §5).
const _revokeWhere = <String, String>{
  'google_drive': 'in your Google Account’s third-party access settings',
  'dropbox': 'in Dropbox’s Connected apps settings',
  'onedrive': 'at account.microsoft.com',
  'notion': 'under Connections in your Notion workspace’s settings',
};

/// What the §18 disconnect confirm says about the grant (4.89.0, ADR-123 §5).
///
/// Google and Dropbox offer a revocation an app can call and the backend asks
/// for it — best-effort, so the confirm says it will ASK, never that it is
/// done. OneDrive and Notion offer none, and a confirm must not promise one:
/// the reader removes NoteLetter there themselves. Web: `disconnectRevokeCopy`.
String? disconnectRevokeCopy(String provider, String name) {
  switch (provider) {
    case 'google_drive':
    case 'dropbox':
      return 'NoteLetter also asks $name to revoke its access, and tells you '
          'if $name does not confirm it.';
    case 'onedrive':
      return 'Microsoft does not let an app revoke its own access, so '
          'NoteLetter stays listed on your Microsoft account until you remove '
          'it ${_revokeWhere['onedrive']}.';
    case 'notion':
      return 'Notion does not let an app revoke its own access, so NoteLetter '
          'stays listed until you remove it ${_revokeWhere['notion']}.';
  }
  return null;
}

/// The consequences half of the confirm (4.90.0, ADR-124 §7): only imports
/// that have not reached the pipeline stop (held, waiting, downloading); a
/// file already downloaded finishes, so "every import stops" would be a
/// promise the backend does not keep.
String disconnectConsequences(String name) =>
    'Imports from $name that are waiting for your review or not yet '
    'downloaded stop; files already downloaded finish importing. The folders '
    'it organized are archived, and its suggestions expire.';

/// The disconnect's answer, said once it has happened. `revoked` is
/// `true` · `false` · `null` (confirmed · asked and refused or unreachable ·
/// the provider has none). Anything else (`CloudNotifier`'s `revokedAbsent`)
/// means a backend that never asked —
/// nothing about the grant is known, so nothing about it is said.
/// Web: `disconnectOutcome`.
String disconnectOutcome(String provider, String name, Object? revoked) {
  final where = _revokeWhere[provider];
  if (revoked == true) {
    return '$name is disconnected, and $name confirmed NoteLetter’s access is '
        'revoked.';
  }
  if (revoked == false) {
    return '$name is disconnected, but $name did not confirm that NoteLetter’s '
        'access was revoked${where != null ? ' — you can remove it $where' : ''}.';
  }
  if (revoked == null) {
    return '$name is disconnected. $name keeps NoteLetter listed until you '
        'remove it${where != null ? ' $where' : ' there'}.';
  }
  return '$name is disconnected.';
}

/// Why a listed FILE cannot be imported, or null (4.91.0, ADR-125 §1).
///
/// A direct `file_ids` import asks the SAME closed classifier an upload asks,
/// on the metadata, before anything is downloaded — so a file no import can
/// read is offered no checkbox, and says why in the classifier's own words.
/// Only the TYPE is asked: size is the worker's separate `size_limit` skip, so
/// it is withheld (0). A Google-native document is exported as PDF
/// (`exportable`) and a Notion page is read as text; neither goes through the
/// upload rule. `null` is not a promise — the worker still decides, and its
/// `unsupported_type` row says so if it disagrees. Web: `cloudFileRefusal`.
String? cloudFileRefusal(String provider, CloudFile file) {
  if (file.isFolder) return null;
  if (file.exportable || provider == 'notion') return null;
  return uploadRejection(
    name: file.name,
    size: 0,
    mimeType: file.mimeType ?? '',
  );
}

/// A triage batch's `skipped` count, said (4.90.0, ADR-124 §7). `skipped` is no
/// longer only "triaged elsewhere" — an approve for a provider that is no
/// longer connected lands there too, and the response does not say which. Both
/// are named, so neither is asserted.
String reviewSkippedNote(int n) =>
    '$n ${n == 1 ? 'file was' : 'files were'} left alone — already handled in '
    'another tab or device, or ${n == 1 ? 'its service is' : 'their service is'} '
    'no longer connected.';

/// What one executed reorganization operation came to (4.92.0, ADR-126 §10 —
/// organization.md §fn_execute_reorganization). `created_without_artifact` is
/// a NoteLetter document with no file at the provider, and `artifact_reason`
/// says why; it used to read `created` with nothing to say the file was never
/// written. The vocabulary stays open: an unknown result is said as the server
/// wrote it. Web: `operationOutcome`.
String operationOutcome(Map op, List sections) {
  String title = 'A section';
  for (final s in sections) {
    if (s is Map && s['section_id'] == op['section_id']) {
      final t = s['title'];
      if (t is String && t.isNotEmpty) title = t;
      break;
    }
  }
  final d = op['destination'];
  final dest = d is Map ? destinationLabel(d) : 'its destination';
  switch (op['result']) {
    case 'appended':
      return '$title → added to $dest.';
    case 'created':
      return '$title → a new document, and a file in $dest.';
    case 'created_without_artifact':
      final reason = op['artifact_reason'];
      return '$title → a new document in your library, but no file was '
          'written to $dest'
          '${reason is String && reason.isNotEmpty ? ' — $reason' : ''}.';
    default:
      final r = op['result'];
      return '$title → ${r is String && r.isNotEmpty ? r : 'no result recorded'}.';
  }
}

/// A plan destination as the sheet names it: a folder by its path, a document
/// by its title.
String destinationLabel(Map d) => d['kind'] == 'folder'
    ? (d['path'] as String? ?? 'folder')
    : (d['title'] as String? ?? 'document');
