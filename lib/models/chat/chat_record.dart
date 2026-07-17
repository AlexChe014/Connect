import 'package:connect/models/chat/chat_member_info.dart';
import 'package:flutter/foundation.dart';

/// Полная модель чата из API (`store`, `show`, `update`, `members`).
@immutable
class ChatRecord {
  const ChatRecord({
    required this.id,
    required this.title,
    this.description,
    this.isGroup = false,
    this.isCommon = false,
    this.creatorId,
    this.createdAt,
    this.updatedAt,
    this.members = const [],
  });

  final int id;
  final String title;
  final String? description;
  final bool isGroup;
  final bool isCommon;
  final int? creatorId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<ChatMemberInfo> members;

  factory ChatRecord.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'];
    final members = rawMembers is List
        ? rawMembers
            .whereType<Map>()
            .map((e) => ChatMemberInfo.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false)
        : const <ChatMemberInfo>[];

    return ChatRecord(
      id: _parseInt(json['id']) ?? 0,
      title: (json['title'] as String?)?.trim() ?? '',
      description: (json['description'] as String?)?.trim(),
      isGroup: json['is_group'] == true,
      isCommon: json['is_common'] == true,
      creatorId: _parseInt(json['creator_id']),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      members: members,
    );
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
