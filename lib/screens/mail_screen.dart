import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show RefreshIndicator, ScaffoldMessenger, SnackBar;

import '../models/mail/mail_connection.dart';
import '../repositories/mail_repository.dart';
import '../repositories/profile_repository.dart';
import '../services/auth_service.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_loading.dart';
import '../widgets/employee_row.dart';
import 'mail_connection_form_screen.dart';
import 'mail_inbox_screen.dart';
import 'mail_provider_picker_screen.dart';

class MailScreen extends StatefulWidget {
  const MailScreen({
    super.key,
    this.showAppBar = true,
    this.autoOpenInbox = true,
  });

  final bool showAppBar;

  /// Если есть хотя бы один подключённый ящик, сразу открывает его письма
  /// вместо списка ящиков — список нужен только чтобы добавить/отредактировать
  /// подключение, поэтому его пропускают, когда выбирать не из чего.
  /// `false` используется, когда экран открыт явно для управления ящиками
  /// (например, из [MailInboxScreen]).
  final bool autoOpenInbox;

  static int? _parseUserId(Map<String, dynamic>? json) {
    if (json == null) return null;

    final raw = json['id'] ?? json['user_id'];
    if (raw != null) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw.trim());
    }

    final nested = json['user'];
    if (nested is Map) {
      return _parseUserId(Map<String, dynamic>.from(nested));
    }

    return null;
  }

  static Future<int?> resolveUserId() async {
    try {
      final profile = await ProfileRepository.instance.getProfile();
      final profileId = _parseUserId(profile);
      if (profileId != null) return profileId;
    } catch (_) {}

    return _parseUserId(await AuthService.instance.getStoredUser());
  }

  static Future<List<MailConnection>> loadConnectionsForCurrentUser() async {
    final userId = await resolveUserId();
    if (userId == null) return const [];
    return MailRepository.instance.getConnectionsByUser(userId);
  }

  @override
  State<MailScreen> createState() => _MailScreenState();
}

class _MailScreenState extends State<MailScreen> {
  List<MailConnection> _connections = [];
  bool _isLoading = true;
  int? _userId;

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    setState(() => _isLoading = true);
    try {
      final userId = await MailScreen.resolveUserId();
      _userId = userId;
      if (userId == null) {
        if (!mounted) return;
        setState(() {
          _connections = [];
          _isLoading = false;
        });
        return;
      }
      final items = await MailRepository.instance.getConnectionsByUser(userId);
      if (!mounted) return;
      if (widget.autoOpenInbox && items.isNotEmpty) {
        final selected = items.firstWhere(
          (c) => c.isDefault,
          orElse: () => items.first,
        );
        Navigator.of(context).pushReplacement<void, void>(
          CupertinoPageRoute<void>(
            builder: (context) =>
                MailInboxScreen(connection: selected, connections: items),
          ),
        );
        return;
      }
      setState(() {
        _connections = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить почтовые ящики')),
      );
    }
  }

  Future<void> _openCreateConnection() async {
    final created = await Navigator.of(context).push<bool>(
      CupertinoPageRoute<bool>(
        builder: (context) => const MailProviderPickerScreen(),
      ),
    );
    if (created == true) await _loadConnections();
  }

  void _openInbox(MailConnection connection) {
    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (context) =>
            MailInboxScreen(connection: connection, connections: _connections),
      ),
    );
  }

  Future<void> _editPassword(MailConnection connection) async {
    final updated = await Navigator.of(context).push<bool>(
      CupertinoPageRoute<bool>(
        builder: (context) => MailConnectionFormScreen(existing: connection),
      ),
    );
    if (updated == true) await _loadConnections();
  }

  Widget _buildContentSliver() {
    if (_isLoading) {
      return AppGlassSliverList(
        itemCount: 3,
        itemBuilder: (context, index) => const AppSkeletonListTile(),
      );
    }

    if (_connections.isEmpty) {
      return SliverAppEmptyState(
        icon: CupertinoIcons.mail,
        message: _userId == null
            ? 'Не удалось определить пользователя'
            : 'Почтовые ящики не подключены\nПодключите Яндекс, Mail или свой IMAP-сервер',
        onRetry: _openCreateConnection,
        retryLabel: 'Подключить ящик',
      );
    }

    return AppGlassSliverList(
      separatorIndent: 72,
      itemCount: _connections.length,
      itemBuilder: (context, index) {
        final connection = _connections[index];
        return _ConnectionTile(
          connection: connection,
          onTap: () => _openInbox(connection),
          onEditPassword: () => _editPassword(connection),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: label,
          fontSize: 16,
        ),
        child: Stack(
          children: [
            const AppGlassGlow(),
            SafeArea(
              top: false,
              bottom: false,
              child: RefreshIndicator.adaptive(
                onRefresh: _loadConnections,
                child: CustomScrollView(
                  slivers: [
                    CupertinoSliverNavigationBar(
                      largeTitle: const Text('Почта'),
                      // Прозрачная: под шапкой остаётся системное размытие, а
                      // заливка дала бы на цветном пятне видимую границу.
                      backgroundColor: CupertinoColors.systemGroupedBackground
                          .resolveFrom(context)
                          .withValues(alpha: 0),
                      automaticBackgroundVisibility: false,
                      border: null,
                      leading: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: () => Navigator.maybePop(context),
                        child: Icon(
                          CupertinoIcons.back,
                          size: 26,
                          color: label,
                        ),
                      ),
                      trailing: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        onPressed: _openCreateConnection,
                        child: Icon(
                          CupertinoIcons.add_circled,
                          size: 28,
                          color: label,
                        ),
                      ),
                    ),
                    if (!_isLoading && _connections.isNotEmpty)
                      const SliverToBoxAdapter(
                        child: AppGlassSectionLabel(
                          'Почтовые ящики',
                          padding: EdgeInsets.fromLTRB(20, 4, 20, 6),
                        ),
                      ),
                    _buildContentSliver(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Строка ящика — та же сетка, что у строки сотрудника: значок 44 слева,
/// название и адрес, справа кнопка смены пароля.
class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({
    required this.connection,
    required this.onTap,
    required this.onEditPassword,
  });

  final MailConnection connection;
  final VoidCallback onTap;
  final VoidCallback onEditPassword;

  /// Цвет провайдера — по нему ящики различают с первого взгляда.
  static Color _colorFor(MailConnection connection) {
    switch (mailProviderKindFromService(connection.service)) {
      case MailProviderKind.yandex:
        return CupertinoColors.systemRed;
      case MailProviderKind.mailru:
        return CupertinoColors.systemBlue;
      case MailProviderKind.corporate:
        return CupertinoColors.systemGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final caption = [
      connection.serviceLabel,
      if (connection.isDefault) 'основной',
    ].where((e) => e.trim().isNotEmpty).join(' · ');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _colorFor(connection),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                CupertinoIcons.mail_solid,
                size: 22,
                color: CupertinoColors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    connection.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    connection.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: secondary),
                  ),
                  if (caption.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: secondary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            EmployeeRowButton(
              icon: CupertinoIcons.lock_rotation,
              onPressed: onEditPassword,
            ),
            const SizedBox(width: 6),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 16,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
          ],
        ),
      ),
    );
  }
}
