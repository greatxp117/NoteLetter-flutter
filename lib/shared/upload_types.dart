/// The upload allowlist, client side (contract 4.10.0, ADR-046; per-type cap
/// 4.13.0, ADR-049).
///
/// The backend's `fn_create_upload_session` is the authority and rejects with a
/// 400 — this file exists so the picker can filter and so a rejected file can
/// fail **instantly, in the same words**, not to replace that check. Every call
/// site must still surface the server's message: the extension filter is
/// advisory (a share sheet and a paste bypass it entirely), and a `null` from
/// [uploadRejection] is **not** an accept — it means "worth sending".
///
/// Spec: `NoteLetter-contracts/spec/api/uploads.md` §The accepted set is
/// closed. Gated both ways by `harness/upload_set_check.py`, which reads the
/// `_EXTS` lists below and compares them to the spec table and to `main.py` —
/// so a class added here and nowhere else fails the commit, and so does one
/// added there and not here.
///
/// **The set was declared three times with the spec eight extensions behind**
/// and nothing noticed, because under-declaring breaks the *picker*, not any
/// request (4.11.1). That is the whole reason this file is parsed rather than
/// trusted.
library;

const List<String> audioExts = [
  'm4a', 'mp3', 'wav', 'aac', 'm4b', 'ogg', 'oga', 'opus',
  'flac', 'caf', 'aiff', 'aif', 'wma', 'amr',
];

const List<String> imageExts = [
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp',
  'tif', 'tiff', 'avif',
];

const List<String> textExts = ['txt', 'text', 'md', 'markdown', 'rst'];

/// 4.13.0 (ADR-049). `mp4`/`webm`/`3gp` live on **both** this list and the
/// audio branch — the MIME separates `audio/mp4` from `video/mp4` — and they
/// are absent from [audioExts] so the extension fallback below resolves them to
/// video, which is what they overwhelmingly are. `ts` is deliberately absent:
/// it is a real transport-stream container and also TypeScript, which
/// [_codeExts] claims first.
const List<String> videoExts = [
  'mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi', 'wmv', 'flv',
  '3gp', 'mpg', 'mpeg', 'mts', 'm2ts', 'ogv',
];

/// Source files decode as valid UTF-8, so they would produce a *correct*
/// document — this is a product rule, not a defect fix, and the message says so
/// rather than calling a readable text file "unsupported".
const Set<String> _codeExts = {
  'py', 'pyw', 'ipynb', 'js', 'mjs', 'cjs', 'jsx', 'ts', 'tsx', 'json', 'jsonl',
  'yaml', 'yml', 'toml', 'ini', 'cfg', 'env', 'css', 'scss', 'sass', 'less',
  'html', 'htm', 'xml', 'svg', 'vue', 'svelte', 'sh', 'bash', 'zsh', 'fish',
  'ps1', 'bat', 'cmd', 'sql', 'graphql', 'proto', 'java', 'kt', 'kts', 'swift',
  'm', 'mm', 'rb', 'go', 'rs', 'c', 'h', 'cpp', 'cc', 'hpp', 'cs', 'php',
  'pl', 'pm', 'lua', 'r', 'jl', 'scala', 'clj', 'ex', 'exs', 'erl', 'hs',
  'dart', 'gradle', 'cmake', 'mk', 'dockerfile', 'tf', 'patch', 'diff', 'lock',
};

/// Every accepted extension, for `FilePicker`'s `allowedExtensions`.
///
/// The picker is `FileType.custom` with this list — it was `FileType.image`,
/// which offered a reader **nothing but photographs** on a screen whose own
/// copy promises PDFs, Word, PowerPoint, text, audio and video. That is not a
/// refusal a user can see and argue with; it is six document classes that
/// appear not to exist.
List<String> get uploadAllowedExtensions => [
      'pdf',
      'docx',
      'pptx',
      ...imageExts,
      ...textExts,
      ...audioExts,
      ...videoExts,
    ];

/// Human copy for the drop zone — kept beside the list so they cannot drift.
const String uploadAcceptHelp =
    'PDF, Word, PowerPoint, Markdown, plain text, images, audio recordings, '
    'or video';

/// The cap is **per type** (4.13.0, ADR-049). A client that checks a flat
/// 100 MB refuses a legal video locally, showing the user a limit the server
/// does not have. Mirrors `_UPLOAD_CAP_MB` in `main.py`.
const int _capMbDefault = 100;
const Map<String, int> _capMb = {'video': 2048};

String _capLabel(int mb) => mb >= 1024 ? '${mb ~/ 1024} GB' : '$mb MB';

String _extOf(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

/// Mirror of the backend rule. Returns a rejection message, or `null` if the
/// file looks acceptable.
///
/// [mimeType] may be empty — a share sheet and a file picker both hand over
/// files with no type at all, and the extension decides then, exactly as on the
/// server.
String? uploadRejection({
  required String name,
  required int size,
  String mimeType = '',
}) {
  final mime = mimeType.split(';').first.trim().toLowerCase();
  final ext = _extOf(name);

  if (_codeExts.contains(ext)) {
    return 'Source code files aren’t supported (.$ext).';
  }
  // Legacy binary Office formats name their own remedy rather than falling to
  // the generic refusal — every route to reading one is a system binary the
  // backend runtime does not carry, so this is permanent, not a gap.
  if (ext == 'ppt' || mime == 'application/vnd.ms-powerpoint') {
    return 'Legacy .ppt files aren’t supported — re-save as .pptx and upload '
        'again.';
  }
  if (ext == 'doc' || mime == 'application/msword') {
    return 'Legacy .doc files aren’t supported — re-save as .docx and upload '
        'again.';
  }
  // A Google-native mime names a document with no bytes, whatever it
  // contains — `…google-apps.presentation` matched the pptx row's "contains
  // presentation" and took a Slides deck for a .pptx (uploads.md, 4.94.0).
  // Only the cloud picker meets one; the kinds Drive exports arrive under
  // their export type.
  if (mime.startsWith('application/vnd.google-apps.')) {
    return '“$name” isn’t a supported file type. $uploadAcceptHelp.';
  }

  String? tooBig(String docType) {
    final cap = _capMb[docType] ?? _capMbDefault;
    return size > cap * 1024 * 1024
        ? 'That file is over the ${_capLabel(cap)} limit.'
        : null;
  }

  // The class is resolved BEFORE the size check, because the cap is per-type
  // and the class selects it (4.13.0, ADR-049) — the same ordering as the
  // server, where `_classify_upload` runs ahead of the size check so a refused
  // upload leaves no state behind.
  final classes = <(bool, List<String>, String)>[
    (mime == 'application/pdf', ['pdf'], 'pdf'),
    (mime.contains('word'), ['docx'], 'docx'),
    (mime.contains('presentation'), ['pptx'], 'pptx'),
    (mime.startsWith('image/'), imageExts, 'image'),
    (
      mime.startsWith('audio/'),
      [...audioExts, 'mp4', 'webm', '3gp'],
      'audio'
    ),
    (mime.startsWith('video/'), videoExts, 'video'),
    (mime == 'text/plain', [...textExts, ''], 'plain'),
  ];

  for (final (matches, exts, docType) in classes) {
    if (matches) {
      if (ext.isNotEmpty && !exts.contains(ext)) {
        return '“$name” is declared as $mime but has a .$ext extension.';
      }
      return tooBig(docType);
    }
  }

  // MIME unhelpful (empty / octet-stream / vendor type) — the extension
  // decides, exactly as on the server. This branch is why a .pdf the picker
  // declined to type still uploads. Video is listed after audio for the same
  // reason `_EXT_FALLBACK` is: `.mp4`/`.webm`/`.3gp` are absent from
  // [audioExts], so an untyped one resolves to video.
  final byExt = <(List<String>, String)>[
    (['pdf'], 'pdf'),
    (['docx'], 'docx'),
    (['pptx'], 'pptx'),
    (imageExts, 'image'),
    (textExts, 'plain'),
    (audioExts, 'audio'),
    (videoExts, 'video'),
  ];
  for (final (exts, docType) in byExt) {
    if (exts.contains(ext)) return tooBig(docType);
  }

  return '“$name” isn’t a supported file type. $uploadAcceptHelp.';
}
