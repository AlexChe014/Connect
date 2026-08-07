import 'package:flutter/material.dart';

import '../config/app_icons.dart';
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

  Widget _buildResults() {
    return RefreshIndicator(
      onRefresh: _loadConnections,
      child: _buildResultsContent(),
    );
  }

  Widget _buildResultsContent() {
    if (_isLoading) {
      return const AppSkeletonList();
    }

    if (_connections.isEmpty) {
      return AppEmptyState(
        icon: AppIcons.mailAt,
        message: _userId == null
            ? 'Не удалось определить пользователя'
            : 'Почтовые ящики не подключены\nПодключите Yandex, Gmail или свой IMAP-сервер',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: _connections.length,
      itemBuilder: (context, index) {
        final connection = _connections[index];
        return _ConnectionTile(
          connection: connection,
          onTap: () => _openInbox(connection),
          onEditPassword: () async {
            final updated = await Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(
                builder: (context) =>
                    MailConnectionFormScreen(existing: connection),
              ),
            );
            if (updated == true) await _loadConnections();
          },
        );
      },
    );
  }

  Widget _buildHeader({required bool showInlineTitle}) {
    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme;

    return Container(
      color: appBarTheme.backgroundColor ?? theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (showInlineTitle)
              SizedBox(
                height: kToolbarHeight,
                child: Center(
                  child: Text(
                    'Почта',
                    style:
                        appBarTheme.titleTextStyle ??
                        theme.textTheme.titleLarge,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _buildAddButton(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody({required bool showInlineTitle}) {
    return Column(
      children: [
        _buildHeader(showInlineTitle: showInlineTitle),
        const Divider(height: 1),
        Expanded(child: _buildResults()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showAppBar) {
      return _buildBody(showInlineTitle: true);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Почта'),
        centerTitle: true,
        elevation: 0,
      ),
      body: _buildBody(showInlineTitle: false),
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
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
