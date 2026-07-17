import 'package:flutter/material.dart';

import '../models/documents/document_service.dart';
import '../repositories/documents_repository.dart';
import '../services/api_client.dart';
import 'documents_list_screen.dart';

class DocumentsSigningScreen extends StatefulWidget {
  const DocumentsSigningScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<DocumentsSigningScreen> createState() => _DocumentsSigningScreenState();
}

class _DocumentsSigningScreenState extends State<DocumentsSigningScreen> {
  List<DocumentService> _services = [];
  bool _isLoading = true;
  bool _isAuthenticating = false;
  bool _accessCodePromptShown = false;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices({bool promptAccessCodeIfEmpty = true}) async {
    setState(() => _isLoading = true);
    try {
      final items = await DocumentsRepository.instance.getActiveServices();
      if (!mounted) return;
      setState(() {
        _services = items;
        _isLoading = false;
      });
      if (items.isEmpty && promptAccessCodeIfEmpty && !_accessCodePromptShown) {
        _accessCodePromptShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _requestPersonalAccessCode();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Не удалось загрузить сервисы 1С', e);
    }
  }

  void _showError(String fallback, Object error) {
    final message = error is ApiException ? error.message : fallback;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _requestPersonalAccessCode() async {
    if (_isAuthenticating) return;

    final code = await _promptCode(
      title: 'Личный код доступа',
      subtitle: 'Введите личный код для получения доступных сервисов 1С',
      label: 'Личный код',
      hint: 'Введите ваш код доступа',
    );
    if (code == null || code.isEmpty || !mounted) return;

    setState(() => _isAuthenticating = true);
    try {
      final services = await DocumentsRepository.instance.authenticate(code);
      if (!mounted) return;
      setState(() {
        _services = services;
        _isAuthenticating = false;
      });
      if (services.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('По этому коду нет доступных сервисов')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAuthenticating = false);
      _showError('Не удалось получить сервисы по коду', e);
    }
  }

  Future<void> _authorizeService(DocumentService service) async {
    final code = await _promptCode(
      title: 'Авторизация в 1С',
      subtitle: service.displayTitle,
    );
    if (code == null || !mounted) return;

    try {
      await DocumentsRepository.instance.authenticateService(
        serviceId: service.id,
        code: code,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Сервис «${service.displayTitle}» авторизован')),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось авторизоваться', e);
    }
  }

  Future<void> _logoutService(DocumentService service) async {
    try {
      final removed = await DocumentsRepository.instance.logoutService(service.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            removed > 0
                ? 'Сессия «${service.displayTitle}» завершена'
                : 'Активная сессия не найдена',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось выйти из сервиса', e);
    }
  }

  Future<String?> _promptCode({
    required String title,
    String? subtitle,
    String label = 'Код авторизации',
    String hint = 'Введите код из 1С',
  }) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (subtitle != null) ...[
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  isDense: true,
                ),
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Продолжить'),
            ),
          ],
        );
      },
    );
  }

  void _openDocuments(DocumentService service) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => DocumentsListScreen(service: service),
      ),
    );
  }

  Widget _buildListContent({required bool showInlineTitle}) {
    if (_isLoading || _isAuthenticating) {
      return const Center(child: CircularProgressIndicator());
    }

    final headerCount = showInlineTitle ? 1 : 0;
    final itemCount = headerCount + (_services.isEmpty ? 1 : _services.length);

    return RefreshIndicator(
      onRefresh: () => _loadServices(promptAccessCodeIfEmpty: false),
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
                      'Подписание',
                      style: appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge,
                    ),
                  ),
                ),
              ),
            );
          }

          final base = showInlineTitle ? 1 : 0;
          final afterHeader = index - base;

          if (_services.isEmpty) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      Icons.vpn_key_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Нет доступных сервисов',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Введите личный код доступа, чтобы получить список сервисов 1С',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _requestPersonalAccessCode,
                      icon: const Icon(Icons.vpn_key_outlined),
                      label: const Text('Ввести код доступа'),
                    ),
                  ],
                ),
              ),
            );
          }

          final service = _services[afterHeader];
          return _ServiceTile(
            service: service,
            onTap: () => _openDocuments(service),
            onAuthorize: () => _authorizeService(service),
            onLogout: () => _logoutService(service),
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
        title: const Text('Подписание'),
        centerTitle: true,
        elevation: 0,
      ),
      body: _buildListContent(showInlineTitle: false),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.onTap,
    required this.onAuthorize,
    required this.onLogout,
  });

  final DocumentService service;
  final VoidCallback onTap;
  final VoidCallback onAuthorize;
  final VoidCallback onLogout;

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
              Expanded(
                child: Text(
                  service.displayName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'auth':
                      onAuthorize();
                    case 'logout':
                      onLogout();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'auth',
                    child: Text('Авторизоваться'),
                  ),
                  PopupMenuItem(
                    value: 'logout',
                    child: Text('Выйти'),
                  ),
                ],
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
