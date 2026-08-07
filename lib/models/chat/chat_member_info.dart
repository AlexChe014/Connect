import 'package:connect/utils/media_url_utils.dart';
import 'package:connect/utils/user_display_name.dart';
import 'package:flutter/foundation.dart';

@immutable
class ChatMemberInfo {
  const ChatMemberInfo({
    required this.membershipId,
    required this.userId,
    required this.fullName,
    this.isAdmin = false,
    this.email,
    this.avatarUrl,
  });

  final int membershipId;
  final int userId;
  final String fullName;
  final bool isAdmin;
  final String? email;
  final String? avatarUrl;

  factory ChatMemberInfo.fromJson(Map<String, dynamic> json) {
    final user = _asJsonMap(json['user']) ?? json;
    final userId = _parseInt(json['user_id'] ?? user['id']) ?? 0;

    return ChatMemberInfo(
      membershipId: _parseInt(json['id']) ?? 0,
      userId: userId,
      isAdmin: json['is_admin'] == true,
      fullName: userDisplayNameFromJson(user),
      email: (user['email'] as String?)?.trim(),
      avatarUrl: MediaUrlUtils.normalizeFirstUrl(user['media']),
    );
  }

  static Map<String, dynamic>? _asJsonMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static int? _parseInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }
}
