import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Colors, RefreshIndicator, ScaffoldMessenger, SnackBar;

import '../config/app_theme.dart';
import '../models/documents/document_service.dart';
import '../repositories/documents_repository.dart';
import '../services/api_client.dart';
import '../services/document_pending_service.dart';
import '../utils/document_payload_utils.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_title_bar.dart';
import '../widgets/booking_glass_form.dart';
import '../widgets/cupertino_prompt_dialog.dart';
import 'document_detail_screen.dart';

class DocumentsListScreen extends StatefulWidget {
  const DocumentsListScreen({super.key, required this.service});

  final DocumentService service;

  @override
  State<DocumentsListScreen> createState() => _DocumentsListScreenState();
}

class _DocumentsListScreenState extends State<DocumentsListScreen> {
  List<Map<String, dynamic>> _documents = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isVerifying = false;
  bool _isSubmitting = false;
  final Set<String> _selectedGuids = <String>{};

  bool get _selectionMode => _selectedGuids.isNotEmpty;

  String get _acceptActionLabel =>
      widget.service.isSigningService ? 'Подписать' : 'Согласовать';

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  bool _isUnauthenticated(Object error) {
    if (error is! ApiException) return false;
    return error.message.toLowerCase().contains('unauthenticated');
  }

  Future<void> _loadDocuments({bool forceSigningCode = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (widget.service.isSigningService && forceSigningCode) {
        final ok = await _verifySigningCode();
        if (!ok) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          return;
        }
      }

      try {
        final items = await DocumentsRepository.instance.getAllDocuments(
          widget.service.id,
        );
        if (!mounted) return;
        setState(() {
          _documents = items;
          _isLoading = false;
          _selectedGuids.clear();
        });
        return;
      } catch (e) {
        if (widget.service.isSigningService && _isUnauthenticated(e)) {
          final ok = await _verifySigningCode();
          if (!ok) {
            if (!mounted) return;
            setState(() => _isLoading = false);
            return;
          }
          final items = await DocumentsRepository.instance.getAllDocuments(
            widget.service.id,
          );
          if (!mounted) return;
          setState(() {
            _documents = items;
            _isLoading = false;
            _selectedGuids.clear();
          });
          return;
        }
        rethrow;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is ApiException
            ? e.message
            : 'Не удалось загрузить документы';
      });
    }
  }

  Future<bool> _verifySigningCode() async {
    if (_isVerifying) return false;

    setState(() => _isVerifying = true);
    try {
      await DocumentsRepository.instance.sendVerificationCode();
    } catch (e) {
      if (!mounted) return false;
      setState(() => _isVerifying = false);
      final message = e is ApiException
          ? e.message
          : 'Не удалось отправить код';
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
      return false;
    }

    final code = await _promptSigningCode();
    if (code == null || code.isEmpty) {
      if (mounted) setState(() => _isVerifying = false);
      return false;
    }

    try {
      final ok = await DocumentsRepository.instance.verifyCode(code);
      if (!mounted) return false;
      setState(() => _isVerifying = false);
      if (ok) DocumentPendingService.instance.markSigningAccessGranted();
      if (!ok) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Неверный код подтверждения')),
        );
      }
      return ok;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _isVerifying = false);
      final message = e is ApiException
          ? e.message
          : 'Не удалось проверить код';
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
      return false;
    }
  }

  Future<String?> _promptSigningCode() async {
    final controller = TextEditingController();
    return showCupertinoDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return CupertinoPromptDialog(
          title: 'Подтверждение доступа',
          message:
              'На вашу почту отправлен 4‑значный код. Введите его, '
              'чтобы открыть документы.',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoTextField(
                controller: controller,
                placeholder: 'Код из письма',
                keyboardType: TextInputType.number,
                maxLength: 4,
                autofocus: true,
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.done,
                style: const TextStyle(fontSize: 20, letterSpacing: 8),
                placeholderStyle: TextStyle(
                  fontSize: 15,
                  letterSpacing: 0,
                  color: CupertinoColors.placeholderText.resolveFrom(context),
                ),
                onSubmitted: (_) =>
                    Navigator.pop(context, controller.text.trim()),
              ),
              const SizedBox(height: 10),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () async {
                  try {
                    await DocumentsRepository.instance.sendVerificationCode(
                      regenerate: true,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(content: Text('Код отправлен повторно')),
                      );
                    }
                  } catch (e) {
                    if (!context.mounted) return;
                    final message = e is ApiException
                        ? e.message
                        : 'Не удалось отправить код';
                    ScaffoldMessenger.maybeOf(
                      context,
                    )?.showSnackBar(SnackBar(content: Text(message)));
                  }
                },
                child: const Text('Отправить снова'),
              ),
            ],
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

  void _openDocument(Map<String, dynamic> document) {
    if (_selectionMode) {
      _toggleDocumentSelection(document);
      return;
    }

    final guid = DocumentPayloadUtils.guid(document);
    if (guid == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('У документа отсутствует идентификатор')),
      );
      return;
    }

    Navigator.of(context)
        .push<void>(
          CupertinoPageRoute<void>(
            builder: (context) => DocumentDetailScreen(
              service: widget.service,
              guid: guid,
              preview: document,
            ),
          ),
        )
        .then((_) => _loadDocuments());
  }

  void _enterSelectionMode(Map<String, dynamic> document) {
    final guid = DocumentPayloadUtils.guid(document);
    if (guid == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('У документа отсутствует идентификатор')),
      );
      return;
    }

    setState(() => _selectedGuids.add(guid));
  }

  void _toggleDocumentSelection(Map<String, dynamic> document) {
    final guid = DocumentPayloadUtils.guid(document);
    if (guid == null) return;

    setState(() {
      if (_selectedGuids.contains(guid)) {
        _selectedGuids.remove(guid);
      } else {
        _selectedGuids.add(guid);
      }
    });
  }

  void _clearSelection() {
    if (!_selectionMode) return;
    setState(_selectedGuids.clear);
  }

  List<Map<String, dynamic>> get _selectedDocuments =>
      _documents.where((document) {
        final guid = DocumentPayloadUtils.guid(document);
        return guid != null && _selectedGuids.contains(guid);
      }).toList();

  Future<void> _bulkAccept() async {
    if (_isSubmitting || !_selectionMode) return;

    final selected = _selectedDocuments;
    if (selected.isEmpty) return;

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('$_acceptActionLabel документы?'),
        content: Text('Будет обработано документов: ${selected.length}.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_acceptActionLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      final guids = selected
          .map(DocumentPayloadUtils.guid)
          .whereType<String>()
          .toList();
      final numbers = selected
          .map(DocumentPayloadUtils.number)
          .whereType<String>()
          .where((number) => number.trim().isNotEmpty)
          .toList();

      await DocumentsRepository.instance.acceptDocuments(
        serviceId: widget.service.id,
        guids: guids,
        numbers: numbers.isEmpty ? null : numbers,
      );

      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            widget.service.isSigningService
                ? 'Документы подписаны'
                : 'Документы согласованы',
          ),
        ),
      );
      await _loadDocuments();
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : 'Не удалось выполнить массовое действие';
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Плавающая стеклянная панель массового действия над списком.
  Widget _buildSelectionBar() {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AppGlass(
          borderRadius: BorderRadius.circular(26),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                Expanded(
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    borderRadius: BorderRadius.circular(20),
                    onPressed: _isSubmitting ? null : _clearSelection,
                    child: Text(
                      'Отмена',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                    onPressed: _isSubmitting ? null : _bulkAccept,
                    child: _isSubmitting
                        ? const CupertinoActivityIndicator(
                            color: CupertinoColors.white,
                          )
                        : Text(
                            '$_acceptActionLabel (${_selectedGuids.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: CupertinoColors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupedBg = AppColors.groupedBackground.resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);

    return AppGlassBarBlur(
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: groupedBg,
        navigationBar: AppTitleBar(
          title: Text(
            _selectionMode
                ? 'Выбрано: ${_selectedGuids.length}'
                : widget.service.displayName,
          ),
          blur: blur,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: _selectionMode
                ? (_isSubmitting ? null : _clearSelection)
                : () => Navigator.pop(context),
            child: Icon(
              _selectionMode ? CupertinoIcons.xmark : CupertinoIcons.back,
              size: AppTitleBar.iconSize,
              color: label,
            ),
          ),
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: '.SF Pro Text',
            decoration: TextDecoration.none,
            color: label,
            fontSize: 16,
          ),
          child: Stack(
            children: [
              const AppGlassGlow(height: 360),
              // Свой context — под скаффолдом, где в MediaQuery уже учтена
              // высота полупрозрачной шапки.
              Builder(builder: _buildBody),
              if (_selectionMode)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildSelectionBar(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);

    if (_isLoading) {
      return CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          AppGlassSliverList(
            itemCount: 6,
            padding: EdgeInsets.fromLTRB(16, padding.top + 12, 16, 24),
            itemBuilder: (context, index) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: AppSkeletonListTile(),
            ),
          ),
        ],
      );
    }

    if (_errorMessage != null) {
      return AppEmptyState(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: _errorMessage!,
        onRetry: () =>
            _loadDocuments(forceSigningCode: widget.service.isSigningService),
      );
    }

    if (_documents.isEmpty) {
      return RefreshIndicator.adaptive(
        edgeOffset: padding.top,
        onRefresh: () => _loadDocuments(),
        child: AppEmptyState(
          icon: CupertinoIcons.tray,
          message: widget.service.isSigningService
              ? 'Нет документов на подписание'
              : 'Нет документов на согласование',
        ),
      );
    }

    return RefreshIndicator.adaptive(
      edgeOffset: padding.top,
      onRefresh: () => _loadDocuments(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: padding.top)),
          SliverToBoxAdapter(
            child: AppGlassSectionLabel(
              _selectionMode
                  ? 'Отметьте документы'
                  : 'Документов: ${_documents.length}',
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            ),
          ),
          AppGlassSliverList(
            itemCount: _documents.length,
            // Поле 16 + значок 29 + зазор 12.
            separatorIndent: 57,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) {
              final document = _documents[index];
              final guid = DocumentPayloadUtils.guid(document);
              final title =
                  DocumentPayloadUtils.datalist(document) ??
                  DocumentPayloadUtils.title(document);
              final selected = guid != null && _selectedGuids.contains(guid);

              return _DocumentRow(
                title: title,
                isSigning: widget.service.isSigningService,
                selectionMode: _selectionMode,
                selected: selected,
                onTap: () => _openDocument(document),
                onLongPress: () => _enterSelectionMode(document),
              );
            },
          ),
          if (!_selectionMode)
            const SliverToBoxAdapter(
              child: BookingFootnote(
                'Удерживайте документ, чтобы выбрать несколько '
                'и обработать их разом.',
              ),
            ),
          // Под плавающей панелью выбора последняя строка не прячется.
          SliverToBoxAdapter(
            child: SizedBox(
              height: padding.bottom + (_selectionMode ? 96 : 32),
            ),
          ),
        ],
      ),
    );
  }
}

/// Строка документа на стеклянном списке. В режиме выбора вместо
/// значка — отметка, шеврон прячется.
class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.title,
    required this.isSigning,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final String title;
  final bool isSigning;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: ColoredBox(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
          child: Row(
            children: [
              SizedBox(
                width: 29,
                height: 29,
                child: selectionMode
                    ? Icon(
                        selected
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.circle,
                        size: 26,
                        color: selected
                            ? AppColors.primary
                            : CupertinoColors.systemGrey3.resolveFrom(context),
                      )
                    : AppIconBadge(
                        icon: CupertinoIcons.doc_text_fill,
                        color: isSigning
                            ? CupertinoColors.systemBlue.resolveFrom(context)
                            : CupertinoColors.systemGreen.resolveFrom(context),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.3,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
              ),
              if (!selectionMode) ...[
                const SizedBox(width: 8),
                Icon(
                  CupertinoIcons.chevron_forward,
                  size: 16,
                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
