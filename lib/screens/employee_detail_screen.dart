import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/staff_user.dart';
import '../repositories/favorites_repository.dart';
import '../screens/chat_conversation_screen.dart';
import '../services/api_client.dart';
import '../services/chat_call_service.dart';
import '../services/chat_service.dart';
import '../widgets/app_glass.dart';
import '../widgets/employee_row.dart';

class EmployeeDetailScreen extends StatefulWidget {
  const EmployeeDetailScreen({super.key, required this.user});

  final StaffUser user;

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  StaffUser get user => widget.user;

  final _callService = ChatCallService.instance;

  bool _isFavorite = false;
  bool _isTogglingFavorite = false;

  @override
  void initState() {
    super.initState();
    _loadFavoriteState();
    _callService.addListener(_onCallState);
  }

  @override
  void dispose() {
    _callService.removeListener(_onCallState);
    super.dispose();
  }

  void _onCallState() {
    if (!mounted) return;
    setState(() {});
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
    final peerId = user.idAsInt;
    if (peerId == null || _callService.isStartingCall) return;

    try {
      final chat = await ChatService.instance.createDirect(
        fullName: user.fullName,
        peerUserId: peerId,
        peerAvatarUrl: user.avatarUrl,
      );
      if (!context.mounted) return;
      if (chat == null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Не удалось начать звонок')),
        );
        return;
      }
      await _callService.startCallFromChat(chat);
    } catch (e) {
      if (!context.mounted) return;
      final message = e is ApiException
          ? e.message
          : 'Не удалось начать звонок';
      showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Ошибка'),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _email() async {
    final email = user.email?.trim();
    if (email == null || email.isEmpty) return;
    await launchUrl(Uri(scheme: 'mailto', path: email));
  }

  Future<void> _dial() async {
    // В tel: только цифры и «+» — пробелы, скобки и дефисы из
    // справочника ломают ссылку на части устройств.
    final phone = (user.phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  void _copy(String value, String what) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text('$what скопирован')));
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

  /// Строка "подпись сверху / значение снизу на всю ширину" — длинные
  /// значения (email, роли) переносятся, а не обрезаются.
  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: CupertinoListTile(
        leading: _iconBadge(icon, color),
        onTap: onTap,
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
            // CupertinoListTile форсирует subtitle в 1 строку с "…", если
            // не переопределить maxLines явно.
            maxLines: 20,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
        ),
      ),
    );
  }

  bool get _isAdmin => user.roles.any((r) {
    final t = r.toLowerCase();
    return t.contains('админ') || t.contains('admin');
  });

  /// Шапка-карточка: аватар слева, текст справа. Раньше аватар стоял
  /// по центру во всю ширину и съедал треть экрана, а контакты
  /// оказывались за сгибом.
  Widget _buildHeader(BuildContext context) {
    final position = (user.position ?? '').trim();
    final department = (user.department ?? '').trim();
    final workStatus = (user.workStatus ?? '').trim();
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppGlass(
        borderRadius: BorderRadius.circular(24),
        shadows: AppGlass.controlShadow,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EmployeeAvatar(user: user, radius: 34),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                    if (position.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        position,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: secondary),
                      ),
                    ],
                    if (department.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        department,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.tertiaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _HeaderChip(
                          dotColor: user.isOnline
                              ? CupertinoColors.systemGreen.resolveFrom(context)
                              : CupertinoColors.systemGrey.resolveFrom(context),
                          text: user.isOnline ? 'В сети' : 'Не в сети',
                        ),
                        if (workStatus.isNotEmpty)
                          _HeaderChip(text: workStatus),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final hasEmail = (user.email ?? '').trim().isNotEmpty;
    final canCall = user.idAsInt != null;
    final actions = <Widget>[
      AppGlassActionButton(
        icon: CupertinoIcons.bubble_left_fill,
        label: 'Написать',
        onTap: () => _openChat(context),
      ),
      if (canCall)
        AppGlassActionButton(
          icon: CupertinoIcons.phone_fill,
          label: 'Звонок',
          onTap: _callService.isStartingCall ? null : () => _call(context),
        ),
      if (hasEmail)
        AppGlassActionButton(
          icon: CupertinoIcons.mail_solid,
          label: 'Почта',
          onTap: _email,
        ),
      AppGlassActionButton(
        icon: _isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
        label: 'Избранное',
        onTap: _toggleFavorite,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: actions[i]),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = (user.email ?? '').trim();
    final phone = (user.phone ?? '').trim();
    final rolesText = user.roles.isEmpty ? null : user.roles.join(', ');
    final showRoles = _isAdmin && rolesText != null;
    final groupedBg = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );

    return CupertinoPageScaffold(
      backgroundColor: groupedBg,
      navigationBar: CupertinoNavigationBar(
        // Прозрачная: под шапкой остаётся системное размытие, а заливка
        // дала бы на цветном пятне видимую границу.
        backgroundColor: groupedBg.withValues(alpha: 0),
        automaticBackgroundVisibility: false,
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: () => Navigator.pop(context),
          child: Icon(
            CupertinoIcons.back,
            size: 26,
            color: CupertinoColors.label.resolveFrom(context),
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
        child: Stack(
          children: [
            const AppGlassGlow(height: 360),
            Builder(
              // Свой context — под скаффолдом, где в MediaQuery уже учтена
              // высота полупрозрачной шапки.
              builder: (context) => ListView(
                padding: EdgeInsets.only(
                  top: MediaQuery.paddingOf(context).top + 8,
                  bottom: MediaQuery.paddingOf(context).bottom + 32,
                ),
                children: [
                  _buildHeader(context),
                  _buildActions(context),
                  if (email.isNotEmpty || phone.isNotEmpty) ...[
                    const AppGlassSectionLabel('Контакты'),
                    AppGlassSection(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        if (phone.isNotEmpty)
                          _infoRow(
                            context,
                            icon: CupertinoIcons.phone_fill,
                            color: CupertinoColors.systemGreen,
                            label: 'Телефон',
                            value: phone,
                            onTap: _dial,
                            onLongPress: () => _copy(phone, 'Телефон'),
                          ),
                        if (email.isNotEmpty)
                          _infoRow(
                            context,
                            icon: CupertinoIcons.mail_solid,
                            color: CupertinoColors.systemBlue,
                            label: 'Email',
                            value: email,
                            onTap: _email,
                            onLongPress: () => _copy(email, 'Email'),
                          ),
                      ],
                    ),
                  ],
                  if (user.birthday != null || showRoles) ...[
                    const AppGlassSectionLabel('О сотруднике'),
                    AppGlassSection(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        if (user.birthday != null)
                          _infoRow(
                            context,
                            icon: CupertinoIcons.gift_fill,
                            color: CupertinoColors.systemPink,
                            label: 'День рождения',
                            value: DateFormat(
                              'd MMMM',
                              'ru_RU',
                            ).format(user.birthday!),
                          ),
                        // Роли — служебная информация, полезна только
                        // администраторам; обычным пользователям всегда
                        // покажет одно и то же ("Пользователь") и шумит.
                        if (showRoles)
                          _infoRow(
                            context,
                            icon: CupertinoIcons
                                .person_crop_circle_badge_checkmark,
                            color: CupertinoColors.systemOrange,
                            label: 'Роли',
                            value: rolesText,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Капсула под ФИО: статус «в сети» с цветной точкой или рабочий статус.
class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.text, this.dotColor});

  final String text;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
