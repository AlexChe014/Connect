import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show RefreshIndicator, ScaffoldMessenger, SnackBar;

import '../models/mail/mail_connection.dart';
import '../repositories/mail_repository.dart';
import '../repositories/profile_repository.dart';
import '../services/auth_service.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
import 'mail_connection_form_screen.dart';
import 'mail_inbox_screen.dart';

class MailScreen extends StatefulWidget {
  const MailScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

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

  Future<int?> _resolveUserId() async {
    try {
      final profile = await ProfileRepository.instance.getProfile();
      final profileId = _parseUserId(profile);
      if (profileId != null) return profileId;
    } catch (_) {}

    return _parseUserId(await AuthService.instance.getStoredUser());
  }

  Future<void> _loadConnections() async {
    setState(() => _isLoading = true);
    try {
      final userId = await _resolveUserId();
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
        builder: (context) => const MailConnectionFormScreen(),
      ),
    );
    if (created == true) await _loadConnections();
  }

  void _openInbox(MailConnection connection) {
    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (context) => MailInboxScreen(connection: connection),
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

  List<Widget> _buildContentSlivers() {
    if (_isLoading) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          sliver: SliverList.separated(
            itemCount: 4,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) => const AppSkeletonCardTile(),
          ),
        ),
      ];
    }

    if (_connections.isEmpty) {
      return [
        SliverFillRemaining(
          child: AppEmptyState(
            icon: CupertinoIcons.mail,
            message: _userId == null
                ? 'Не удалось определить пользователя'
                : 'Почтовые ящики не подключены\nПодключите Yandex, Gmail или свой IMAP-сервер',
            onRetry: _openCreateConnection,
            retryLabel: 'Подключить ящик',
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        sliver: SliverList.separated(
          itemCount: _connections.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final connection = _connections[index];
            return _ConnectionTile(
              connection: connection,
              onTap: () => _openInbox(connection),
              onEditPassword: () => _editPassword(connection),
            );
          },
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 16,
        ),
        child: SafeArea(
          top: false,
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _loadConnections,
            child: CustomScrollView(
              slivers: [
                CupertinoSliverNavigationBar(
                  largeTitle: const Text('Почта'),
                  backgroundColor: CupertinoColors.systemGroupedBackground
                      .withValues(alpha: 0.9),
                  border: null,
                  trailing: CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: _openCreateConnection,
                    child: const Icon(CupertinoIcons.add_circled, size: 28),
                  ),
                ),
                ..._buildContentSlivers(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({
    required this.connection,
    required this.onTap,
    required this.onEditPassword,
  });

  final MailConnection connection;
  final VoidCallback onTap;
  final VoidCallback onEditPassword;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CupertinoColors.activeBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  CupertinoIcons.mail_solid,
                  size: 17,
                  color: CupertinoColors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connection.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      connection.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      connection.serviceLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.activeBlue,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onEditPassword,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    CupertinoIcons.lock_rotation,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    size: 20,
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
