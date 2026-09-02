import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connect/models/chat.dart';
import 'package:connect/services/birthday_directory.dart';
import 'package:connect/utils/user_display_name.dart';
import 'package:flutter/cupertino.dart';
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

  @override
  void initState() {
    super.initState();
    BirthdayDirectory.instance.addListener(_onBirthdaysLoaded);
    BirthdayDirectory.instance.ensureLoaded();
  }

  @override
  void dispose() {
    BirthdayDirectory.instance.removeListener(_onBirthdaysLoaded);
    super.dispose();
  }

  void _onBirthdaysLoaded() {
    if (mounted) setState(() {});
  }

  Widget _fallback() => _InitialsAvatar(
    initials: chatInitials(widget.chat),
    backgroundColor: chatAvatarColor(widget.chat.title),
    radius: widget.radius,
  );

  Widget _avatar() {
    if (!_imageFailed) {
      final url = chatAvatarBestUrl(widget.chat);
      if (url != null) {
        final size = widget.radius * 2;
        return ClipOval(
          child: CachedNetworkImage(
            imageUrl: url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (context, url) => _fallback(),
            errorWidget: (context, url, error) => _fallback(),
          ),
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

  @override
  Widget build(BuildContext context) {
    final avatar = _avatar();
    if (widget.chat.isGroup ||
        !BirthdayDirectory.instance.isBirthdayToday(widget.chat.peerUserId)) {
      return avatar;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [avatar, BirthdayBadge(radius: widget.radius)],
    );
  }
}

/// Значок-торт 🎂 в углу аватара именинника.
class BirthdayBadge extends StatelessWidget {
  const BirthdayBadge({super.key, required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) {
    final size = (radius * 0.62).clamp(16.0, 22.0);
    return Positioned(
      right: -2,
      bottom: -2,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          shape: BoxShape.circle,
        ),
        child: Text('🎂', style: TextStyle(fontSize: size * 0.62)),
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

  Widget _fallback() => _InitialsAvatar(
    initials: userInitials(displayName),
    backgroundColor: chatAvatarColor(displayName),
    radius: radius,
  );

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();
    if (url == null || url.isEmpty) return _fallback();

    // Плейсхолдер — сразу инициалы (не пустой круг), пока грузится/кэшируется
    // фото: без него аватар на миг мигает пустотой при первом появлении.
    final size = radius * 2;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, url) => _fallback(),
        errorWidget: (context, url, error) => _fallback(),
      ),
    );
  }
}
