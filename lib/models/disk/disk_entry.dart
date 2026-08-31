/// Папка из ответа `files/list` (`data.folders[]`).
class DiskFolder {
  final String path;
  final String name;
  final bool isShared;
  final String? owner;
  final DateTime? lastModified;

  const DiskFolder({
    required this.path,
    required this.name,
    this.isShared = false,
    this.owner,
    this.lastModified,
  });

  factory DiskFolder.fromJson(Map<String, dynamic> json) {
    return DiskFolder(
      path: (json['path'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      isShared: _hasShare(json['share']),
      owner: json['owner']?.toString(),
      lastModified: _parseDate(json['last_modified']),
    );
  }
}

/// Файл из ответа `files/list` (`data.files[]`).
class DiskFile {
  final String path;
  final String name;
  final int? size;
  final String? mime;
  final bool isShared;
  final String? owner;
  final DateTime? lastModified;

  const DiskFile({
    required this.path,
    required this.name,
    this.size,
    this.mime,
    this.isShared = false,
    this.owner,
    this.lastModified,
  });

  bool get isImage => mime?.startsWith('image/') ?? false;

  factory DiskFile.fromJson(Map<String, dynamic> json) {
    return DiskFile(
      path: (json['path'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      size: _parseInt(json['size']),
      mime: json['mime']?.toString(),
      isShared: _hasShare(json['share']),
      owner: json['owner']?.toString(),
      lastModified: _parseDate(json['last_modified']),
    );
  }
}

/// Содержимое папки: `{folders: [...], files: [...]}` из `files/list`.
class DiskListing {
  final List<DiskFolder> folders;
  final List<DiskFile> files;

  const DiskListing({required this.folders, required this.files});

  bool get isEmpty => folders.isEmpty && files.isEmpty;

  factory DiskListing.fromJson(Map<String, dynamic> json) {
    final rawFolders = json['folders'];
    final rawFiles = json['files'];

    // Первая папка в ответе — это сама запрошенная (текущая) папка,
    // а не её ребёнок, поэтому пропускаем самый первый элемент списка.
    final folders = rawFolders is List
        ? rawFolders
              .whereType<Map>()
              .map((e) => DiskFolder.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : <DiskFolder>[];
    final trimmedFolders = folders.isEmpty
        ? folders
        : folders.sublist(1);

    final files = rawFiles is List
        ? rawFiles
              .whereType<Map>()
              .map((e) => DiskFile.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : <DiskFile>[];

    return DiskListing(folders: trimmedFolders, files: files);
  }
}

int? _parseInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

bool _hasShare(Object? value) {
  if (value is List) return value.isNotEmpty;
  return false;
}
