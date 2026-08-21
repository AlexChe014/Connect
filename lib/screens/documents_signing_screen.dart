import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show RefreshIndicator, ScaffoldMessenger, SnackBar;

import '../models/documents/document_service.dart';
import '../repositories/documents_repository.dart';
import '../services/api_client.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
import '../widgets/cupertino_prompt_dialog.dart';
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
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
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
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Сервис «${service.displayTitle}» авторизован')),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось авторизоваться', e);
    }
  }

  Future<void> _logoutService(DocumentService service) async {
    try {
      final removed = await DocumentsRepository.instance.logoutService(
        service.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
    return showCupertinoDialog<String>(
      context: context,
      builder: (context) {
        return CupertinoPromptDialog(
          title: title,
          message: subtitle,
          content: CupertinoTextField(
            controller: controller,
            placeholder: hint,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
          ),
          actions: [
            CupertinoPromptDialogAction(
              label: 'Отмена',
              onPressed: () => Navigator.pop(context),
            ),
            CupertinoPromptDialogAction(
              label: 'Продолжить',
              isDefault: true,
              onPressed: () => Navigator.pop(context, controller.text.trim()),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showServiceActions(DocumentService service) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(service.displayName),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'auth'),
            child: const Text('Авторизоваться'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'logout'),
            child: const Text('Выйти'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'auth':
        await _authorizeService(service);
      case 'logout':
        await _logoutService(service);
    }
  }

  void _openDocuments(DocumentService service) {
    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (context) => DocumentsListScreen(service: service),
      ),
    );
  }

  Widget _iconBadge(IconData icon, Color color) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  List<Widget> _buildContentSlivers() {
    if (_isLoading || _isAuthenticating) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          sliver: SliverList.separated(
            itemCount: 6,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) => const AppSkeletonListTile(),
          ),
        ),
      ];
    }

    if (_services.isEmpty) {
      return [
        SliverFillRemaining(
          child: AppEmptyState(
            icon: CupertinoIcons.lock_shield,
            message:
                'Нет доступных сервисов\n'
                'Введите личный код доступа, чтобы получить список сервисов 1С',
            onRetry: _requestPersonalAccessCode,
            retryLabel: 'Ввести код доступа',
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        sliver: SliverList.separated(
          itemCount: _services.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final service = _services[index];
            return _ServiceTile(
              service: service,
              icon: _iconBadge(
                service.isSigningService
                    ? CupertinoIcons.pencil_outline
                    : CupertinoIcons.checkmark_seal,
                service.isSigningService
                    ? CupertinoColors.systemBlue
                    : CupertinoColors.systemGreen,
              ),
              onTap: () => _openDocuments(service),
              onMore: () => _showServiceActions(service),
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
            onRefresh: () => _loadServices(promptAccessCodeIfEmpty: false),
            child: CustomScrollView(
              slivers: [
                const CupertinoSliverNavigationBar(
                  largeTitle: Text('Согласование'),
                  backgroundColor: CupertinoColors.systemGroupedBackground,
                  border: null,
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

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.icon,
    required this.onTap,
    required this.onMore,
  });

  final DocumentService service;
  final Widget icon;
  final VoidCallback onTap;
  final VoidCallback onMore;

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
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  service.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.label,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onMore,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    CupertinoIcons.ellipsis,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
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
