import 'dart:io';

import 'package:connect/models/chat.dart';
import 'package:connect/utils/user_display_name.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

String chatInitials(Chat c) {
  final t = c.title.trim();
  if (t.isEmpty) return '?';
  final parts = t.split(RegExp(r'\s+')).where((p) => p.trim().isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length >= 2) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  return parts[0].characters.take(2).toString().toUpperCase();
}

Color chatAvatarColor(String key) {
  var h = 0;
  for (final code in key.codeUnits) {
    h = (h * 31 + code) & 0x7fffffff;
  }
  const palette = <Color>[
    Color(0xFF5AC8FA),
    Color(0xFF34C759),
    Color(0xFFFF9500),
    Color(0xFFFF2D55),
    Color(0xFFAF52DE),
    Color(0xFF5856D6),
    Color(0xFF64D2FF),
    Color(0xFFFFCC00),
  ];
  return palette[h % palette.length];
}

String? chatAvatarBestPath(Chat c) {
  final peer = c.peerAvatarPath?.trim();
  if (peer != null && peer.isNotEmpty) return peer;
  final own = c.avatarPath?.trim();
  if (own != null && own.isNotEmpty) return own;
  return null;
}

String? chatAvatarBestUrl(Chat c) {
  final peer = c.peerAvatarUrl?.trim();
  if (peer != null && peer.isNotEmpty) return peer;
  final own = c.avatarUrl?.trim();
  if (own != null && own.isNotEmpty) return own;
  return null;
}

class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.chat,
    this.radius = 22,
  });

  final Chat chat;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = chatAvatarBestUrl(chat);
    if (url != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.transparent,
        backgroundImage: NetworkImage(url),
        onBackgroundImageError: (error, stackTrace) {},
      );
    }

    final path = chatAvatarBestPath(chat);
    if (path != null && !kIsWeb) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: FileImage(File(path)),
        backgroundColor: Colors.transparent,
        onBackgroundImageError: (error, stackTrace) {},
      );
    }

    final initials = chatInitials(chat);
    final bg = chatAvatarColor(chat.title);
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.75,
          height: 1,
        ),
      ),
    );
  }
}

/// Аватар участника по имени и URL.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.displayName,
    this.avatarUrl,
    this.radius = 18,
  });

  final String displayName;
  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.transparent,
        backgroundImage: NetworkImage(url),
        onBackgroundImageError: (error, stackTrace) {},
      );
    }

    final initials = userInitials(displayName);
    final bg = chatAvatarColor(displayName);
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.75,
          height: 1,
        ),
      ),
    );
  }
}
