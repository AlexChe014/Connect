import 'package:flutter/material.dart';

import '../config/app_icons.dart';
import '../models/mail/mail_connection.dart';
import '../repositories/mail_repository.dart';
import '../repositories/profile_repository.dart';
import '../services/auth_service.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить почтовые ящики')),
      );
    }
  }

  Future<void> _openCreateConnection() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => const MailConnectionFormScreen(),
      ),
    );
    if (created == true) await _loadConnections();
  }

  void _openInbox(MailConnection connection) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => MailInboxScreen(connection: connection),
      ),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: _openCreateConnection,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              AppIcon(
                AppIcons.mailAdd,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'Добавить почтовый ящик',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListContent({required bool showInlineTitle}) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final headerCount = (showInlineTitle ? 1 : 0) + 1;
    final itemCount = headerCount + (_connections.isEmpty ? 1 : _connections.length);

    return RefreshIndicator(
      onRefresh: _loadConnections,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, showInlineTitle ? 0 : 8, 16, 16),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (showInlineTitle && index == 0) {
            final theme = Theme.of(context);
            final cs = theme.colorScheme;
            final appBarTheme = theme.appBarTheme;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              color: appBarTheme.backgroundColor ?? cs.surface,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: kToolbarHeight,
                  child: Center(
                    child: Text(
                      'Почта',
                      style: appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge,
                    ),
                  ),
                ),
              ),
            );
          }

          final base = showInlineTitle ? 1 : 0;
          final afterHeader = index - base;

          if (afterHeader == 0) {
            return Padding(
              padding: EdgeInsets.only(bottom: widget.showAppBar ? 0 : 12),
              child: _buildAddButton(context),
            );
          }

          if (_connections.isEmpty) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    AppIcon(
                      AppIcons.mailAt,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _userId == null
                          ? 'Не удалось определить пользователя'
                          : 'Почтовые ящики не подключены',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Подключите Yandex, Gmail или свой IMAP-сервер',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            );
          }

          final connection = _connections[afterHeader - 1];
          return _ConnectionTile(
            connection: connection,
            onTap: () => _openInbox(connection),
            onEditPassword: () async {
              final updated = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (context) => MailConnectionFormScreen(
                    existing: connection,
                  ),
                ),
              );
              if (updated == true) await _loadConnections();
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showAppBar) {
      return _buildListContent(showInlineTitle: true);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Почта'),
        centerTitle: true,
        elevation: 0,
      ),
      body: _buildListContent(showInlineTitle: false),
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
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: AppIcon(
                  AppIcons.mailAt,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connection.displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      connection.email,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      connection.serviceLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Обновить пароль',
                onPressed: onEditPassword,
                icon: const Icon(Icons.vpn_key_outlined),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
