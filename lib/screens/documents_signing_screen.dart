import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show RefreshIndicator, ScaffoldMessenger, SnackBar;

import '../models/documents/document_service.dart';
import '../repositories/documents_repository.dart';
import '../services/api_client.dart';
import '../services/document_pending_service.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_title_bar.dart';
import '../widgets/booking_glass_form.dart';
import '../widgets/cupertino_prompt_dialog.dart';
import 'documents_list_screen.dart';

class DocumentsSigningScreen extends StatefulWidget {
  const DocumentsSigningScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<DocumentsSigningScreen> createState() => _DocumentsSigningScreenState();
}

class _DocumentsSigningScreenState extends State<DocumentsSigningScreen>
    with WidgetsBindingObserver {
  final _pending = DocumentPendingService.instance;
  Timer? _timer;
  List<DocumentService> _services = [];
  bool _isLoading = true;
  bool _isAuthenticating = false;
  bool _accessCodePromptShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pending.addListener(_onCountsChanged);
    _timer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshCounts(),
    );
    _loadServices();
  }

  void _onCountsChanged() {
    if (mounted) setState(() {});
  }

  void _refreshCounts() {
    if (!mounted ||
        _isLoading ||
        _pending.loading.isNotEmpty ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    unawaited(_pending.refresh(_services));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshCounts();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pending.removeListener(_onCountsChanged);
    super.dispose();
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
      unawaited(_pending.refresh(items));
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
      unawaited(_pending.refresh(services));
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

  Future<void> _logoutAll() async {
    try {
      final removed = await DocumentsRepository.instance.logout();
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            removed > 0
                ? 'Выполнен выход из всех сервисов 1С'
                : 'Активные сессии не найдены',
          ),
        ),
      );
      await _loadServices(promptAccessCodeIfEmpty: false);
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось выйти из сервисов 1С', e);
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
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, 'logout'),
            child: const Text('Выйти из всех сервисов 1С'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'logout') {
      await _logoutAll();
    }
  }

  Future<void> _openDocuments(DocumentService service) async {
    await Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (context) => DocumentsListScreen(service: service),
      ),
    );
    if (mounted) await _pending.refresh(_services);
  }

  List<Widget> _buildContentSlivers() {
    if (_isLoading || _isAuthenticating) {
      return [
        AppGlassSliverList(
          itemCount: 3,
          padding: const EdgeInsets.fromLTRB(16, 34, 16, 24),
          itemBuilder: (context, index) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: AppSkeletonListTile(),
          ),
        ),
      ];
    }

    if (_services.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: AppEmptyState(
            icon: CupertinoIcons.lock_shield,
            message:
                'Нет доступных сервисов\n'
                'Введите личный код доступа, чтобы получить список сервисов 1С',
            onRetry: _requestPersonalAccessCode,
            retryLabel: 'Ввести код доступа',
            scrollable: false,
          ),
        ),
      ];
    }

    return [
      const SliverToBoxAdapter(
        child: AppGlassSectionLabel(
          'Сервисы 1С',
          padding: EdgeInsets.fromLTRB(20, 8, 20, 6),
        ),
      ),
      AppGlassSliverList(
        itemCount: _services.length,
        // Поле 16 + значок 29 + зазор 12.
        separatorIndent: 57,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          final service = _services[index];
          return _ServiceRow(
            service: service,
            pendingCount: _pending.counts[service.id],
            countError: _pending.errors.contains(service.id),
            countLoading: _pending.loading.contains(service.id),
            onTap: () => _openDocuments(service),
            onMore: () => _showServiceActions(service),
          );
        },
      ),
      const SliverPadding(
        padding: EdgeInsets.only(bottom: 24),
        sliver: SliverToBoxAdapter(
          child: BookingFootnote(
            'Число справа — документы, которые ждут вашего решения. '
            'Через «…» можно выйти из сервисов 1С.',
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AppGlassBarBlur(
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
          context,
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
              const AppGlassGlow(),
              SafeArea(
                top: false,
                bottom: false,
                child: RefreshIndicator.adaptive(
                  onRefresh: () =>
                      _loadServices(promptAccessCodeIfEmpty: false),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      AppSliverTitleBar(
                        title: const Text('Согласование'),
                        leading: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          onPressed: () => Navigator.maybePop(context),
                          child: Icon(
                            CupertinoIcons.back,
                            size: AppSliverTitleBar.iconSize,
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                        ),
                        blur: blur,
                      ),
                      ..._buildContentSlivers(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка сервиса 1С на стеклянном списке: значок, название, число
/// документов на решении, «…» с действиями и шеврон.
class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.service,
    required this.onTap,
    required this.onMore,
    required this.pendingCount,
    required this.countError,
    required this.countLoading,
  });

  final DocumentService service;
  final int? pendingCount;
  final bool countError;
  final bool countLoading;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final count = pendingCount;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        child: Row(
          children: [
            AppIconBadge(
              icon: service.isSigningService
                  ? CupertinoIcons.pencil
                  : CupertinoIcons.checkmark_seal_fill,
              color: service.isSigningService
                  ? CupertinoColors.systemBlue.resolveFrom(context)
                  : CupertinoColors.systemGreen.resolveFrom(context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                service.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (countLoading)
              const CupertinoActivityIndicator(radius: 8)
            else if (countError)
              Semantics(
                label: 'Не удалось проверить документы',
                child: Icon(
                  CupertinoIcons.exclamationmark_circle,
                  color: CupertinoColors.systemOrange.resolveFrom(context),
                  size: 20,
                ),
              )
            else if (count != null)
              Semantics(
                label: 'Документов на согласование: $count',
                child: Container(
                  constraints: const BoxConstraints(minWidth: 24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: count > 0
                        ? CupertinoColors.systemRed.resolveFrom(context)
                        : CupertinoColors.tertiarySystemFill.resolveFrom(
                            context,
                          ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: count > 0
                          ? CupertinoColors.white
                          : CupertinoColors.secondaryLabel.resolveFrom(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: Size.zero,
              onPressed: onMore,
              child: Icon(
                CupertinoIcons.ellipsis_circle,
                size: 22,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
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
    );
  }
}
