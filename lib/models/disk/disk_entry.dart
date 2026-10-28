/// Папка из ответа `files/list` (`data.folders[]`).
class DiskFolder {
  final String path;
  final String name;
  final bool isShared;
  final String? owner;

  /// Имя владельца (`owner_name`), если сервер его прислал.
  final String? ownerName;
  final DateTime? lastModified;

  const DiskFolder({
    required this.path,
    required this.name,
    this.isShared = false,
    this.owner,
    this.ownerName,
    this.lastModified,
  });

  factory DiskFolder.fromJson(Map<String, dynamic> json) {
    return DiskFolder(
      path: (json['path'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      isShared: _hasShare(json['share']),
      owner: json['owner']?.toString(),
      ownerName: _nonEmpty(json['owner_name']),
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

  /// Имя владельца (`owner_name`), если сервер его прислал.
  final String? ownerName;
  final DateTime? lastModified;

  const DiskFile({
    required this.path,
    required this.name,
    this.size,
    this.mime,
    this.isShared = false,
    this.owner,
    this.ownerName,
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
      ownerName: _nonEmpty(json['owner_name']),
      lastModified: _parseDate(json['last_modified']),
    );
  }
}

/// Содержимое папки: `{folders: [...], files: [...]}` из `files/list`.
class DiskListing {
  final List<DiskFolder> folders;
  final List<DiskFile> files;

  /// Владелец самой запрошенной папки; у корня — это сам пользователь.
  final String? folderOwner;

  const DiskListing({
    required this.folders,
    required this.files,
    this.folderOwner,
  });

  bool get isEmpty => folders.isEmpty && files.isEmpty;

  /// [folder] — запрошенная папка в виде `DiskRepository.toApiPath`.
  /// `files/list` кладёт её саму в `folders` рядом с детьми; её убираем по
  /// совпадению пути, а не «первую по счёту», чтобы смена порядка в ответе
  /// не спрятала настоящую папку. [normalize] приводит пути к одному виду.
  factory DiskListing.fromJson(
    Map<String, dynamic> json, {
    String folder = '',
    String Function(String path)? normalize,
  }) {
    final rawFolders = json['folders'];
    final rawFiles = json['files'];

    final folders = rawFolders is List
        ? rawFolders
              .whereType<Map>()
              .map((e) => DiskFolder.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : <DiskFolder>[];

    String key(String path) =>
        (normalize?.call(path) ?? path).replaceAll(RegExp(r'^/+|/+$'), '');
    final self = key(folder);
    final children = folders.where((f) => key(f.path) != self).toList();
    // Пути не совпали ни с одной папкой (сервер отдал их в другом виде) —
    // остаётся прежнее, проверенное на живых данных поведение: первая папка
    // в ответе — сама запрошенная.
    final fallback = children.length == folders.length && folders.isNotEmpty;
    final trimmedFolders = fallback ? folders.sublist(1) : children;
    final selfFolder = fallback
        ? folders.first
        : folders.where((f) => key(f.path) == self).firstOrNull;

    final files = rawFiles is List
        ? rawFiles
              .whereType<Map>()
              .map((e) => DiskFile.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : <DiskFile>[];

    return DiskListing(
      folders: trimmedFolders,
      files: files,
      folderOwner: selfFolder?.owner,
    );
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

String? _nonEmpty(Object? value) {
  final s = value?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

bool _hasShare(Object? value) {
  if (value is List) return value.isNotEmpty;
  return false;
}
