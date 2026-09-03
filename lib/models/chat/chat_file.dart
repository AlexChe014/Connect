import 'package:flutter/foundation.dart';

/// Файл чата (`POST /api/chat/files`, поле `files` у сообщения).
@immutable
class ChatFile {
  const ChatFile({
    required this.id,
    required this.filename,
    required this.originalName,
    required this.mimeType,
    required this.size,
    this.isDuplicate = false,
    this.createdAt,
  });

  /// Лимит бэкенда: 10240 КБ.
  static const int maxSizeBytes = 10240 * 1024;

  final int id;
  final String filename;
  final String originalName;
  final String mimeType;
  final int size;
  final bool isDuplicate;
  final DateTime? createdAt;

  bool get isImage {
    if (mimeType.toLowerCase().startsWith('image/')) return true;
    return _extensionIs(originalName, const [
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'heic',
      'bmp',
    ]);
  }

  bool get isVideo {
    if (mimeType.toLowerCase().startsWith('video/')) return true;
    return _extensionIs(originalName, const [
      'mp4',
      'mov',
      'webm',
      'mkv',
      'avi',
    ]);
  }

  String get sizeLabel {
    if (size < 1024) return '$size Б';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(0)} КБ';
    }
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  factory ChatFile.fromJson(Map<String, dynamic> json) {
    return ChatFile(
      id: _parseInt(json['id']) ?? 0,
      filename: (json['filename'] as String?)?.trim() ?? '',
      originalName:
          (json['originalName'] as String?)?.trim() ??
          (json['original_name'] as String?)?.trim() ??
          (json['filename'] as String?)?.trim() ??
          'файл',
      mimeType:
          (json['mimeType'] as String?)?.trim() ??
          (json['mime_type'] as String?)?.trim() ??
          'application/octet-stream',
      size: _parseInt(json['size']) ?? 0,
      isDuplicate:
          json['is_duplicate'] == true || json['isDuplicate'] == true,
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
    );
  }

  static List<ChatFile> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    final out = <ChatFile>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        out.add(ChatFile.fromJson(item));
      } else if (item is Map) {
        out.add(ChatFile.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return out;
  }

  static bool _extensionIs(String name, List<String> extensions) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return false;
    final ext = name.substring(dot + 1).toLowerCase();
    return extensions.contains(ext);
  }

  static int? _parseInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString().trim());
  }
}
