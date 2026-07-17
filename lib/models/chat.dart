import 'package:flutter/foundation.dart';

/// Участник чата для отображения в UI.
@immutable
class ChatMemberSummary {
  const ChatMemberSummary({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.isAdmin = false,
  });

  final int userId;
  final String displayName;
  final String? avatarUrl;
  final bool isAdmin;
}

/// Диалог (личный или групповой).
@immutable
class Chat {
  const Chat({
    required this.id,
    required this.title,
    this.avatarPath,
    this.avatarUrl,
    this.peerAvatarPath,
    this.peerAvatarUrl,
    this.peerUserId,
    this.isGroup = false,
    this.description,
    this.creatorId,
    this.members = const [],
    this.lastMessagePreview,
    this.lastMessageAt,
  });

  final String id;
  final String title;
  /// Локальный путь к аватару чата (в т.ч. группы).
  final String? avatarPath;
  /// URL аватара чата с сервера.
  final String? avatarUrl;
  /// Для личных диалогов: локальный путь к аватару пользователя (собеседника).
  final String? peerAvatarPath;
  /// Для личных диалогов: URL аватара собеседника с сервера.
  final String? peerAvatarUrl;
  /// Id собеседника в личном чате.
  final int? peerUserId;
  final bool isGroup;
  final String? description;
  final int? creatorId;
  final List<ChatMemberSummary> members;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;

  bool canManage(int? userId) {
    if (userId == null) return false;
    if (creatorId == userId) return true;
    return members.any((m) => m.userId == userId && m.isAdmin);
  }

  List<String> get memberNames => members.map((m) => m.displayName).toList();

  String get subtitle {
    if (isGroup && members.isNotEmpty) {
      return memberNames.join(', ');
    }
    return lastMessagePreview ?? '';
  }

  Chat copyWithPreview({
    String? lastMessagePreview,
    DateTime? lastMessageAt,
  }) {
    return Chat(
      id: id,
      title: title,
      avatarPath: avatarPath,
      avatarUrl: avatarUrl,
      peerAvatarPath: peerAvatarPath,
      peerAvatarUrl: peerAvatarUrl,
      peerUserId: peerUserId,
      isGroup: isGroup,
      description: description,
      creatorId: creatorId,
      members: members,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    );
  }

  Chat copyWithMembers(List<ChatMemberSummary> members) {
    return Chat(
      id: id,
      title: title,
      avatarPath: avatarPath,
      avatarUrl: avatarUrl,
      peerAvatarPath: peerAvatarPath,
      peerAvatarUrl: peerAvatarUrl,
      peerUserId: peerUserId,
      isGroup: isGroup,
      description: description,
      creatorId: creatorId,
      members: members,
      lastMessagePreview: lastMessagePreview,
      lastMessageAt: lastMessageAt,
    );
  }

  Chat copyWithDetails({
    String? title,
    String? description,
    List<ChatMemberSummary>? members,
    int? creatorId,
    String? avatarPath,
    String? peerAvatarPath,
    String? peerAvatarUrl,
    String? lastMessagePreview,
    DateTime? lastMessageAt,
  }) {
    return Chat(
      id: id,
      title: title ?? this.title,
      avatarPath: avatarPath ?? this.avatarPath,
      avatarUrl: avatarUrl,
      peerAvatarPath: peerAvatarPath ?? this.peerAvatarPath,
      peerAvatarUrl: peerAvatarUrl ?? this.peerAvatarUrl,
      peerUserId: peerUserId,
      isGroup: isGroup,
      description: description ?? this.description,
      creatorId: creatorId ?? this.creatorId,
      members: members ?? this.members,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    );
  }
}
