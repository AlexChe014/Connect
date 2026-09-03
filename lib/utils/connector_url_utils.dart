/// Парсинг ссылок Коннектора (`…/connector/{room}`).
String? connectorRoomFromUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final idx = segments.indexOf('connector');
  if (idx < 0 || idx + 1 >= segments.length) return null;
  final room = segments[idx + 1].trim();
  return room.isEmpty ? null : room;
}

final connectorUrlRegExp = RegExp(
  r'(https?:\/\/[^\s<>"\)]+)',
  caseSensitive: false,
);

/// Ищет room UUID в тексте сообщения (первое совпадение).
String? connectorRoomFromText(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  for (final match in connectorUrlRegExp.allMatches(text)) {
    final url = match.group(0)!.replaceAll(RegExp(r'[.,;:!?)]+$'), '');
    final room = connectorRoomFromUrl(url);
    if (room != null) return room;
  }
  return null;
}
