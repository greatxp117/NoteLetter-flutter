/// One item from `fn_list_cloud_files` — normalized across providers
/// (cloud-storage.md). `modifiedAt`/`path` are provider strings, never
/// Timestamps. `exportable` files (e.g. Google Docs) import as PDF.
class CloudFile {
  final String id;
  final String name;
  final String type; // 'file' | 'folder'
  final String? mimeType;
  final int size;
  final String modifiedAt;
  final bool exportable;
  final String path;

  const CloudFile({
    required this.id,
    required this.name,
    required this.type,
    this.mimeType,
    this.size = 0,
    this.modifiedAt = '',
    this.exportable = false,
    this.path = '',
  });

  bool get isFolder => type == 'folder';

  factory CloudFile.fromJson(Map<String, dynamic> json) {
    return CloudFile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'file',
      mimeType: json['mime_type'] as String?,
      size: (json['size'] as num?)?.toInt() ?? 0,
      modifiedAt: json['modified_at'] as String? ?? '',
      exportable: json['exportable'] as bool? ?? false,
      path: json['path'] as String? ?? '',
    );
  }
}

/// A single page of `fn_list_cloud_files`. `nextPageToken` is opaque — for
/// OneDrive it is a full `@odata.nextLink` URL; never parse it.
class CloudFileListing {
  final List<CloudFile> items;
  final String? nextPageToken;
  final String folderId;
  final String provider;

  const CloudFileListing({
    required this.items,
    this.nextPageToken,
    required this.folderId,
    required this.provider,
  });

  factory CloudFileListing.fromJson(Map<String, dynamic> json) {
    final raw = (json['items'] as List?) ?? const [];
    return CloudFileListing(
      items: raw
          .map((e) => CloudFile.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextPageToken: json['nextPageToken'] as String?,
      folderId: json['folderId'] as String? ?? 'root',
      provider: json['provider'] as String? ?? '',
    );
  }
}
