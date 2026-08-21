import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show RefreshIndicator, ScaffoldMessenger, SnackBar;

import '../models/documents/document_service.dart';
import '../repositories/documents_repository.dart';
import '../services/api_client.dart';
import '../utils/document_payload_utils.dart';
import '../widgets/app_empty_state.dart';
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
                placeholderStyle: const TextStyle(
                  fontSize: 15,
                  letterSpacing: 0,
                  color: CupertinoColors.placeholderText,
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

  Widget _buildSelectionBar() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground.resolveFrom(context),
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  color: CupertinoColors.systemGrey5.resolveFrom(context),
                  onPressed: _isSubmitting ? null : _clearSelection,
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CupertinoButton.filled(
                  onPressed: _isSubmitting ? null : _bulkAccept,
                  child: _isSubmitting
                      ? const CupertinoActivityIndicator(
                          color: CupertinoColors.white,
                        )
                      : Text('$_acceptActionLabel (${_selectedGuids.length})'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          _selectionMode
              ? 'Выбрано: ${_selectedGuids.length}'
              : widget.service.displayName,
        ),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        leading: _selectionMode
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: _isSubmitting ? null : _clearSelection,
                child: const Icon(CupertinoIcons.clear, size: 24),
              )
            : null,
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 16,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(child: _buildBody()),
              if (_selectionMode) _buildSelectionBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
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
      return RefreshIndicator(
        onRefresh: () => _loadDocuments(),
        child: AppEmptyState(
          icon: CupertinoIcons.tray,
          message: widget.service.isSigningService
              ? 'Нет документов на подписание'
              : 'Нет документов на согласование',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadDocuments(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: _documents.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final document = _documents[index];
          final guid = DocumentPayloadUtils.guid(document);
          final title =
              DocumentPayloadUtils.datalist(document) ??
              DocumentPayloadUtils.title(document);
          final selected = guid != null && _selectedGuids.contains(guid);

          return _DocumentTile(
            title: title,
            selectionMode: _selectionMode,
            selected: selected,
            onTap: () => _openDocument(document),
            onLongPress: () => _enterSelectionMode(document),
          );
        },
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.title,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final String title;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: selected
            ? CupertinoColors.activeBlue.withValues(alpha: 0.1)
            : CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
                context,
              ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              if (selectionMode) ...[
                Icon(
                  selected
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.circle,
                  color: selected
                      ? CupertinoColors.activeBlue
                      : CupertinoColors.systemGrey3.resolveFrom(context),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    color: CupertinoColors.label,
                  ),
                ),
              ),
              if (!selectionMode)
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
