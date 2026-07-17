import 'package:connect/config/api_config.dart';

/// Извлечение URL из полей `media` бэкенда (строка, объект или массив).
class MediaUrlUtils {
  MediaUrlUtils._();

  static const _urlKeys = [
    'preview_url',
    'original_url',
    'url',
    'link',
    'path',
    'src',
  ];

  static String? firstUrl(Object? media) {
    if (media == null) return null;
    if (media is String) {
      final t = media.trim();
      return t.isEmpty ? null : t;
    }
    if (media is Map) {
      return _urlFromMap(media.cast<String, dynamic>());
    }
    if (media is List) {
      for (final item in media) {
        final url = firstUrl(item);
        if (url != null && url.isNotEmpty) return url;
      }
    }
    return null;
  }

  static String? normalizeFirstUrl(Object? media) {
    return ApiConfig.normalizeFileUrl(firstUrl(media));
  }

  static String? _urlFromMap(Map<String, dynamic> map) {
    for (final key in _urlKeys) {
      final raw = map[key];
      if (raw == null) continue;
      final s = raw.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }
}
