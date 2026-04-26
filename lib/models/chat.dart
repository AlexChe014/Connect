import 'package:flutter/foundation.dart';

/// Диалог (личный или групповой).
@immutable
class Chat {
  const Chat({
    required this.id,
    required this.title,
    this.isGroup = false,
    this.memberNames = const [],
    this.lastMessagePreview,
    this.lastMessageAt,
  });

  final String id;
  final String title;
  final bool isGroup;
  final List<String> memberNames;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;

  String get subtitle {
    if (isGroup && memberNames.isNotEmpty) {
      return memberNames.join(', ');
    }
    return lastMessagePreview ?? '';
  }
}
