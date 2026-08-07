import 'dart:io';

import 'package:connect/models/chat.dart';
import 'package:connect/utils/user_display_name.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

String chatInitials(Chat c) {
  final t = c.title.trim();
  if (t.isEmpty) return '?';
  final parts = t
      .split(RegExp(r'\s+'))
      .where((p) => p.trim().isNotEmpty)
      .toList();
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

/// Заглушка из инициалов на цветном фоне (общий фоллбэк для аватаров).
class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({
    required this.initials,
    required this.backgroundColor,
    required this.radius,
  });

  final String initials;
  final Color backgroundColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
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

class ChatAvatar extends StatefulWidget {
  const ChatAvatar({super.key, required this.chat, this.radius = 22});

  final Chat chat;
  final double radius;

  @override
  State<ChatAvatar> createState() => _ChatAvatarState();
}

class _ChatAvatarState extends State<ChatAvatar> {
  bool _imageFailed = false;

  Widget _fallback() => _InitialsAvatar(
    initials: chatInitials(widget.chat),
    backgroundColor: chatAvatarColor(widget.chat.title),
    radius: widget.radius,
  );

  @override
  Widget build(BuildContext context) {
    if (!_imageFailed) {
      final url = chatAvatarBestUrl(widget.chat);
      if (url != null) {
        return CircleAvatar(
          radius: widget.radius,
          backgroundColor: Colors.transparent,
          backgroundImage: NetworkImage(url),
          onBackgroundImageError: (error, stackTrace) {
            if (mounted) setState(() => _imageFailed = true);
          },
        );
      }

      final path = chatAvatarBestPath(widget.chat);
      if (path != null && !kIsWeb) {
        return CircleAvatar(
          radius: widget.radius,
          backgroundImage: FileImage(File(path)),
          backgroundColor: Colors.transparent,
          onBackgroundImageError: (error, stackTrace) {
            if (mounted) setState(() => _imageFailed = true);
          },
        );
      }
    }

    return _fallback();
  }
}

/// Аватар участника по имени и URL.
class MemberAvatar extends StatefulWidget {
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
  State<MemberAvatar> createState() => _MemberAvatarState();
}

class _MemberAvatarState extends State<MemberAvatar> {
  bool _imageFailed = false;

  @override
  void didUpdateWidget(MemberAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl) _imageFailed = false;
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.avatarUrl?.trim();
    if (!_imageFailed && url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: Colors.transparent,
        backgroundImage: NetworkImage(url),
        onBackgroundImageError: (error, stackTrace) {
          if (mounted) setState(() => _imageFailed = true);
        },
      );
    }

    return _InitialsAvatar(
      initials: userInitials(widget.displayName),
      backgroundColor: chatAvatarColor(widget.displayName),
      radius: widget.radius,
    );
  }
}
