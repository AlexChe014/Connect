import 'package:flutter/material.dart';

import '../models/documents/document_service.dart';
import '../repositories/documents_repository.dart';
import '../services/api_client.dart';
import '../utils/document_payload_utils.dart';
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
        _errorMessage =
            e is ApiException ? e.message : 'Не удалось загрузить документы';
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
      final message = e is ApiException ? e.message : 'Не удалось отправить код';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Неверный код подтверждения')),
        );
      }
      return ok;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _isVerifying = false);
      final message = e is ApiException ? e.message : 'Не удалось проверить код';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return false;
    }
  }

  Future<String?> _promptSigningCode() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final compactBtn = TextButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        );
        final compactFilled = FilledButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        );
        return AlertDialog(
          title: const Text(
            'Подтверждение доступа',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'На вашу почту отправлен 4‑значный код. Введите его, чтобы открыть документы.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Код из письма',
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                maxLength: 4,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: compactBtn,
                  onPressed: () async {
                    try {
                      await DocumentsRepository.instance.sendVerificationCode(
                        regenerate: true,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Код отправлен повторно')),
                        );
                      }
                    } catch (e) {
                      if (!context.mounted) return;
                      final message =
                          e is ApiException ? e.message : 'Не удалось отправить код';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(message)),
                      );
                    }
                  },
                  child: const Text('Отправить снова'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: compactBtn,
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              style: compactFilled,
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Продолжить'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('У документа отсутствует идентификатор')),
      );
      return;
    }

    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
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
      ScaffoldMessenger.of(context).showSnackBar(
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

  List<Map<String, dynamic>> get _selectedDocuments => _documents
      .where((document) {
        final guid = DocumentPayloadUtils.guid(document);
        return guid != null && _selectedGuids.contains(guid);
      })
      .toList();

  Future<void> _bulkAccept() async {
    if (_isSubmitting || !_selectionMode) return;

    final selected = _selectedDocuments;
    if (selected.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$_acceptActionLabel документы?'),
        content: Text(
          'Будет обработано документов: ${selected.length}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
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
      ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildSelectionBar() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting ? null : _clearSelection,
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _bulkAccept,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
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

  Widget _buildDocumentCheckbox({
    required bool selected,
    required ValueChanged<bool?> onChanged,
  }) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Checkbox(
        value: selected,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode
              ? 'Выбрано: ${_selectedGuids.length}'
              : widget.service.displayName,
        ),
        centerTitle: true,
        leading: _selectionMode
            ? IconButton(
                tooltip: 'Отменить выбор',
                onPressed: _isSubmitting ? null : _clearSelection,
                icon: const Icon(Icons.close),
              )
            : null,
      ),
      body: _buildBody(),
      bottomNavigationBar: _selectionMode ? _buildSelectionBar() : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _loadDocuments(
                  forceSigningCode: widget.service.isSigningService,
                ),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    if (_documents.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadDocuments(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              widget.service.isSigningService
                  ? 'Нет документов на подписание'
                  : 'Нет документов на согласование',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadDocuments(),
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(16, 8, 16, _selectionMode ? 8 : 16),
        itemCount: _documents.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 1,
          color: Theme.of(context).colorScheme.outline,
        ),
        itemBuilder: (context, index) {
          final document = _documents[index];
          final guid = DocumentPayloadUtils.guid(document);
          final title = DocumentPayloadUtils.datalist(document) ??
              DocumentPayloadUtils.title(document);
          final selected =
              guid != null && _selectedGuids.contains(guid);

          return InkWell(
            onTap: () {
              if (_selectionMode) {
                _toggleDocumentSelection(document);
              } else {
                _openDocument(document);
              }
            },
            onLongPress: () => _enterSelectionMode(document),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (_selectionMode) ...[
                    _buildDocumentCheckbox(
                      selected: selected,
                      onChanged: (_) => _toggleDocumentSelection(document),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  if (!_selectionMode)
                    Icon(
                      Icons.chevron_right,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
