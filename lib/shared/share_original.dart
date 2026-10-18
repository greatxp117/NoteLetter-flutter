import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Whether this build can share a file out (F-124): iOS and Android. The
/// toolbar draws Share only where this is true.
bool get canShareOriginal => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

/// The name the shared copy carries: the stored object's own file name when
/// its path has one, else the title with the type's extension. Never the
/// signed URL's query string, and never a name with a path separator in it.
String shareFileName({
  required String title,
  required String type,
  String? gcsPath,
}) {
  final fromPath = (gcsPath ?? '').split('/').last;
  // `raw/{uid}/{docId}/{uuid}_{name}` — the upload's own name follows the
  // first underscore when the object was stored that way.
  final i = fromPath.indexOf('_');
  final stored = i > 0 && fromPath.contains('.') ? fromPath.substring(i + 1) : '';
  if (stored.isNotEmpty) return _clean(stored);
  final base = _clean(title.trim().isEmpty ? 'Original file' : title.trim());
  final ext = switch (type) {
    'pdf' => 'pdf',
    'docx' => 'docx',
    'pptx' => 'pptx',
    'epub' => 'epub',
    'plain' => 'txt',
    _ => '',
  };
  if (ext.isEmpty || base.toLowerCase().endsWith('.$ext')) return base;
  return '$base.$ext';
}

String _clean(String s) => s.replaceAll(RegExp(r'[/\\:\x00-\x1f]'), ' ').trim();

/// Shares the original FILE — its bytes, under its own name — through the
/// system share sheet. Not the signed URL: that expires in minutes and opens
/// for nobody else (the retired Swift app shared the URL).
///
/// Returns null when the sheet was shown, or the reason it could not be.
Future<String?> shareOriginal(
  BuildContext anchor, {
  required String url,
  required String fileName,
  String? mimeType,
}) async {
  // Where the sheet comes from on an iPad: the control itself.
  final box = anchor.findRenderObject() as RenderBox?;
  final origin = box == null || !box.hasSize
      ? null
      : box.localToGlobal(Offset.zero) & box.size;
  try {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/share-${DateTime.now().millisecondsSinceEpoch}/$fileName';
    await Dio().download(url, path);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(path, mimeType: mimeType, name: fileName)],
      sharePositionOrigin: origin,
    ));
    return null;
  } on DioException catch (e) {
    return 'The original file could not be downloaded to share'
        '${e.response?.statusCode != null ? ' (HTTP ${e.response!.statusCode})' : ''}.';
  } catch (e) {
    return 'The original file could not be shared: $e';
  }
}
