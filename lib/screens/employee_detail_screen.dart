import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../models/staff_user.dart';
import '../repositories/favorites_repository.dart';
import '../screens/chat_conversation_screen.dart';
import '../services/chat_service.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/status_bubble.dart';

class EmployeeDetailScreen extends StatefulWidget {
  const EmployeeDetailScreen({super.key, required this.user});

  final StaffUser user;

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  StaffUser get user => widget.user;

  bool _isFavorite = false;
  bool _isTogglingFavorite = false;

  @override
  void initState() {
    super.initState();
    _loadFavoriteState();
  }

  Future<void> _loadFavoriteState() async {
    try {
      final ids = await FavoritesRepository.instance.getFavoriteUserIds();
      if (!mounted) return;
      setState(() => _isFavorite = ids.contains(user.id));
    } catch (_) {
      // Молча остаёмся с состоянием "не в избранном" — не критично для экрана.
    }
  }

  Future<void> _toggleFavorite() async {
    final id = user.idAsInt;
    if (id == null || _isTogglingFavorite) return;
    setState(() {
      _isTogglingFavorite = true;
      _isFavorite = !_isFavorite;
    });
    try {
      await FavoritesRepository.instance.toggleUser(id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isFavorite = !_isFavorite);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось изменить избранное')),
      );
    } finally {
      if (mounted) setState(() => _isTogglingFavorite = false);
    }
  }

  Future<void> _openChat(BuildContext context) async {
    final peerId = user.idAsInt;
    if (peerId == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось определить пользователя')),
      );
      return;
    }

    final chat = await ChatService.instance.createDirect(
      fullName: user.fullName,
      peerUserId: peerId,
      peerAvatarUrl: user.avatarUrl,
    );
    if (!context.mounted) return;
    if (chat == null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Не удалось открыть чат')));
      return;
    }
    await Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (context) => ChatConversationScreen(chat: chat),
      ),
    );
  }

  Future<void> _call(BuildContext context) async {
    final phone = user.phone?.trim();
    if (phone == null || phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    await launchUrl(uri);
  }

  Future<void> _email(BuildContext context) async {
    final email = user.email?.trim();
    if (email == null || email.isEmpty) return;
    final uri = Uri(scheme: 'mailto', path: email);
    await launchUrl(uri);
  }

  Widget _iconBadge(IconData icon, Color color) {
    return Container(
      width: 29,
      height: 29,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 17, color: CupertinoColors.white),
    );
  }

  /// Строка "подпись сверху / значение снизу на всю ширину" — в отличие от
  /// leading+title+additionalInfo, длинные значения (email, телефон) не
  /// обрезаются и не выталкивают подпись.
  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    bool isPlaceholder = false,
  }) {
    return CupertinoListTile(
      leading: _iconBadge(icon, color),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          value,
          // CupertinoListTile форсирует subtitle в 1 строку с "…", если не
          // переопределить maxLines явно — вопреки комментарию выше это
          // резало длинные значения (например, должность) на самом деле.
          maxLines: 20,
          overflow: TextOverflow.ellipsis,
          style: isPlaceholder
              ? TextStyle(
                  fontStyle: FontStyle.italic,
                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                )
              : const TextStyle(color: CupertinoColors.label),
        ),
      ),
    );
  }

  bool get _isAdmin => user.roles.any((r) {
    final t = r.toLowerCase();
    return t.contains('админ') || t.contains('admin');
  });

  @override
  Widget build(BuildContext context) {
    final birthdayLabel = user.birthday != null
        ? DateFormat('d MMMM', 'ru_RU').format(user.birthday!)
        : 'Не указан';
    final positionLabel = (user.position ?? '').trim().isNotEmpty
        ? user.position!.trim()
        : 'Не указана';
    final rolesText = user.roles.isEmpty ? null : user.roles.join(', ');
    final workStatus = (user.workStatus ?? '').trim();
    final hasPhone = (user.phone ?? '').trim().isNotEmpty;
    final hasEmail = (user.email ?? '').trim().isNotEmpty;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: () => Navigator.pop(context),
          child: const Icon(CupertinoIcons.back, size: 26),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: _toggleFavorite,
          child: Icon(
            _isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
            size: 24,
            color: _isFavorite
                ? CupertinoColors.systemYellow
                : CupertinoColors.label.resolveFrom(context),
          ),
        ),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 16,
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    MemberAvatar(
                      displayName: user.fullName,
                      avatarUrl: user.avatarUrl,
                      radius: 52,
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: user.isOnline
                              ? const Color(0xFF34C759)
                              : AppColors.outlineStrong,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: CupertinoColors.systemGroupedBackground
                                .resolveFrom(context),
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                    if (user.isBirthdayToday)
                      Positioned(
                        left: -4,
                        bottom: -2,
                        child: Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemGroupedBackground
                                .resolveFrom(context),
                            shape: BoxShape.circle,
                          ),
                          child: const Text(
                            '🎂',
                            style: TextStyle(fontSize: 20),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                user.fullName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if ((user.department ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  user.department!.trim(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ],
              if (workStatus.isNotEmpty) ...[
                const SizedBox(height: 10),
                Center(child: StatusBubble(text: workStatus)),
              ],
              const SizedBox(height: 6),
              Text(
                user.isOnline ? 'В сети' : 'Не в сети',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (user.isBirthdayToday) ...[
                    _ContactActionButton(
                      emoji: '🎂',
                      color: CupertinoColors.systemPink,
                      label: 'Поздравить',
                      onTap: () => _openChat(context),
                    ),
                    const SizedBox(width: 28),
                  ],
                  _ContactActionButton(
                    icon: CupertinoIcons.bubble_left_fill,
                    color: CupertinoColors.systemBlue,
                    label: 'Написать',
                    onTap: () => _openChat(context),
                  ),
                  if (hasPhone) ...[
                    const SizedBox(width: 28),
                    _ContactActionButton(
                      icon: CupertinoIcons.phone_fill,
                      color: CupertinoColors.systemGreen,
                      label: 'Позвонить',
                      onTap: () => _call(context),
                    ),
                  ],
                  if (hasEmail) ...[
                    const SizedBox(width: 28),
                    _ContactActionButton(
                      icon: CupertinoIcons.mail_solid,
                      color: CupertinoColors.systemIndigo,
                      label: 'Почта',
                      onTap: () => _email(context),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 28),
              CupertinoListSection.insetGrouped(
                header: const Text('Информация'),
                children: [
                  if (hasEmail)
                    _infoRow(
                      context,
                      icon: CupertinoIcons.mail_solid,
                      color: CupertinoColors.systemBlue,
                      label: 'Email',
                      value: user.email!.trim(),
                    ),
                  if (hasPhone)
                    _infoRow(
                      context,
                      icon: CupertinoIcons.phone_fill,
                      color: CupertinoColors.systemGreen,
                      label: 'Телефон',
                      value: user.phone!.trim(),
                    ),
                  _infoRow(
                    context,
                    icon: CupertinoIcons.gift_fill,
                    color: CupertinoColors.systemPink,
                    label: 'День рождения',
                    value: birthdayLabel,
                    isPlaceholder: user.birthday == null,
                  ),
                  _infoRow(
                    context,
                    icon: CupertinoIcons.briefcase_fill,
                    color: CupertinoColors.systemTeal,
                    label: 'Должность',
                    value: positionLabel,
                    isPlaceholder: (user.position ?? '').trim().isEmpty,
                  ),
                  if ((user.department ?? '').trim().isNotEmpty)
                    _infoRow(
                      context,
                      icon: CupertinoIcons.building_2_fill,
                      color: CupertinoColors.systemIndigo,
                      label: 'Отдел',
                      value: user.department!.trim(),
                    ),
                  // Роли — служебная информация, полезна только для
                  // администраторов; обычным пользователям всегда покажет
                  // одно и то же ("Пользователь") и просто шумит на экране.
                  if (_isAdmin && rolesText != null)
                    _infoRow(
                      context,
                      icon: CupertinoIcons.star_fill,
                      color: CupertinoColors.systemOrange,
                      label: 'Роли',
                      value: rolesText,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactActionButton extends StatelessWidget {
  const _ContactActionButton({
    this.icon,
    this.emoji,
    required this.color,
    required this.label,
    required this.onTap,
  }) : assert(icon != null || emoji != null);

  final IconData? icon;
  final String? emoji;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: emoji != null
                ? Text(emoji!, style: const TextStyle(fontSize: 24))
                : Icon(icon, size: 24, color: CupertinoColors.white),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }
}
