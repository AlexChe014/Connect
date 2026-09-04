import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;

import '../models/documents/document_service.dart';
import '../repositories/documents_repository.dart';
import '../services/api_client.dart';
import '../utils/document_file_share.dart';
import '../utils/document_payload_utils.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';

class DocumentDetailScreen extends StatefulWidget {
  const DocumentDetailScreen({
    super.key,
    required this.service,
    required this.guid,
    this.preview,
  });

  final DocumentService service;
  final String guid;
  final Map<String, dynamic>? preview;

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  Map<String, dynamic>? _document;
  List<Map<String, dynamic>> _acceptors = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  final _commentController = TextEditingController();
  int? _downloadingFileIndex;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final doc = await DocumentsRepository.instance.getDocument(
        serviceId: widget.service.id,
        guid: widget.guid,
      );

      List<Map<String, dynamic>> acceptors = const [];
      try {
        acceptors = await DocumentsRepository.instance.getAcceptors(
          serviceId: widget.service.id,
          guid: widget.guid,
        );
      } catch (_) {
        // Согласующие могут быть пустыми/ошибка 1С — не блокируем карточку документа.
      }

      if (!mounted) return;
      setState(() {
        _document = doc;
        _acceptors = acceptors;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is ApiException
            ? e.message
            : 'Не удалось загрузить документ';
      });
    }
  }

  Map<String, dynamic> get _displayDocument =>
      _document ?? widget.preview ?? const {};

  Future<void> _accept() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);
    try {
      await DocumentsRepository.instance.acceptDocument(
        serviceId: widget.service.id,
        guid: widget.guid,
        comment: _commentController.text.trim(),
        number: DocumentPayloadUtils.number(_displayDocument),
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            widget.service.isSigningService
                ? 'Документ подписан'
                : 'Документ согласован',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showError(
        widget.service.isSigningService
            ? 'Не удалось подписать документ'
            : 'Не удалось согласовать документ',
        e,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _reject() async {
    if (_isSubmitting) return;

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Отклонить документ?'),
        content: const Text(
          'Документ будет отклонён. Это действие нельзя отменить.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отклонить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    try {
      await DocumentsRepository.instance.rejectDocument(
        serviceId: widget.service.id,
        guid: widget.guid,
        comment: _commentController.text.trim(),
        number: DocumentPayloadUtils.number(_displayDocument),
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Документ отклонён')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось отклонить документ', e);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _openFile(int index, Map<String, dynamic> file) async {
    if (_downloadingFileIndex != null) return;

    setState(() => _downloadingFileIndex = index);
    try {
      final fileGuid =
          (file['guid'] ?? file['fileguid'] ?? file['file_guid'] ?? file['id'])
              ?.toString()
              .trim();
      final response = await DocumentsRepository.instance.getDocumentFile(
        serviceId: widget.service.id,
        guid: (fileGuid == null || fileGuid.isEmpty) ? widget.guid : fileGuid,
      );
      await DocumentFileShare.share(
        response,
        fallbackName: file['namefile']?.toString() ?? 'Файл',
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось скачать файл', e);
    } finally {
      if (mounted) setState(() => _downloadingFileIndex = null);
    }
  }

  // Экран целиком построен на Cupertino-виджетах без Material Scaffold —
  // ScaffoldMessenger.showSnackBar в этом случае привязывается к Scaffold
  // предыдущего экрана в стеке навигации и рисуется под текущей страницей,
  // поэтому остаётся невидимым. Показываем ошибку диалогом.
  void _showError(String fallback, Object error) {
    final message = error is ApiException ? error.message : fallback;
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }

  List<MapEntry<String, String>> _summaryEntries(
    Map<String, dynamic> document,
  ) {
    const order = [
      ('task', 'Задача'),
      ('title', 'Комментарий'),
      ('number', 'Номер'),
      ('author', 'Автор'),
      ('sum', 'Сумма'),
      ('time', 'Срок'),
      ('status', 'Статус'),
    ];

    final entries = <MapEntry<String, String>>[];
    for (final item in order) {
      final raw = document[item.$1];
      if (raw == null) continue;
      final value = raw.toString().trim();
      if (value.isEmpty) continue;
      entries.add(MapEntry(item.$2, value));
    }
    return entries;
  }

  List<Map<String, dynamic>> _sides(Map<String, dynamic> document) {
    final raw = document['sides'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<Map<String, dynamic>> _files(Map<String, dynamic> document) {
    final raw = document['files'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Widget _iconBadge(IconData icon, Color color) {
    return Container(
      width: 29,
      height: 29,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 17, color: CupertinoColors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title =
        DocumentPayloadUtils.datalist(_displayDocument) ??
        DocumentPayloadUtils.title(_displayDocument);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 15,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(child: _buildBody()),
              if (!_isLoading && _errorMessage == null) _buildActionBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    final actionLabel = widget.service.isSigningService
        ? 'Подписать'
        : 'Согласовать';
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoTextField(
                controller: _commentController,
                placeholder: 'Комментарий (необязательно)',
                minLines: 1,
                maxLines: 3,
                enabled: !_isSubmitting,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      color: CupertinoColors.systemGrey5.resolveFrom(context),
                      onPressed: _isSubmitting ? null : _reject,
                      child: const Text(
                        'Отклонить',
                        style: TextStyle(color: CupertinoColors.systemRed),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton.filled(
                      onPressed: _isSubmitting ? null : _accept,
                      child: _isSubmitting
                          ? const CupertinoActivityIndicator(
                              color: CupertinoColors.white,
                            )
                          : Text(actionLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const AppPageLoader();
    }

    if (_errorMessage != null) {
      return AppEmptyState(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: _errorMessage!,
        onRetry: _loadDetails,
      );
    }

    final document = _displayDocument;
    final entries = _summaryEntries(document);
    final sides = _sides(document);
    final files = _files(document);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        Container(
          decoration: BoxDecoration(
            color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
              context,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(16),
          child: Text(
            DocumentPayloadUtils.datalist(document) ??
                DocumentPayloadUtils.title(document),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'ДЕТАЛИ',
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          CupertinoListSection.insetGrouped(
            margin: EdgeInsets.zero,
            children: [
              for (final entry in entries)
                CupertinoListTile(
                  title: Text(
                    entry.key,
                    style: const TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entry.value,
                      // CupertinoListTile форсирует subtitle в 1 строку с
                      // "…", если не переопределить maxLines явно.
                      maxLines: 20,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: CupertinoColors.label),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (sides.isNotEmpty) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'СТОРОНЫ',
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          CupertinoListSection.insetGrouped(
            margin: EdgeInsets.zero,
            children: [
              for (final side in sides)
                CupertinoListTile(
                  leading: _iconBadge(
                    CupertinoIcons.person_2_fill,
                    CupertinoColors.systemIndigo,
                  ),
                  title: Text(side['partner']?.toString() ?? 'Сторона'),
                  subtitle: (side['value']?.toString() ?? '').isEmpty
                      ? null
                      : Text(side['value'].toString()),
                ),
            ],
          ),
        ],
        if (files.isNotEmpty) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'ФАЙЛЫ',
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          CupertinoListSection.insetGrouped(
            margin: EdgeInsets.zero,
            children: [
              for (final entry in files.asMap().entries)
                CupertinoListTile(
                  leading: _iconBadge(
                    CupertinoIcons.paperclip,
                    CupertinoColors.systemGrey,
                  ),
                  title: Text(entry.value['namefile']?.toString() ?? 'Файл'),
                  trailing: _downloadingFileIndex == entry.key
                      ? const CupertinoActivityIndicator()
                      : const CupertinoListTileChevron(),
                  onTap: _downloadingFileIndex == null
                      ? () => _openFile(entry.key, entry.value)
                      : null,
                ),
            ],
          ),
        ],
        if (_acceptors.isNotEmpty) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'СОГЛАСУЮЩИЕ',
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          CupertinoListSection.insetGrouped(
            margin: EdgeInsets.zero,
            children: [
              for (final acceptor in _acceptors)
                CupertinoListTile(
                  leading: _iconBadge(
                    CupertinoIcons.checkmark_seal_fill,
                    CupertinoColors.systemGreen,
                  ),
                  title: Text(DocumentPayloadUtils.labelForAcceptor(acceptor)),
                  subtitle: () {
                    final status = DocumentPayloadUtils.acceptorStatus(
                      acceptor,
                    );
                    return status == null ? null : Text(status);
                  }(),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
