import 'package:flutter/material.dart';

import '../config/app_icons.dart';
import '../models/documents/document_service.dart';
import '../repositories/documents_repository.dart';
import '../services/api_client.dart';
import '../utils/document_payload_utils.dart';

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
        _errorMessage =
            e is ApiException ? e.message : 'Не удалось загрузить документ';
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
      ScaffoldMessenger.of(context).showSnackBar(
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отклонить документ?'),
        content: const Text(
          'Документ будет отклонён. Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Документ отклонён')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось отклонить документ', e);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String fallback, Object error) {
    final message = error is ApiException ? error.message : fallback;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  List<MapEntry<String, String>> _summaryEntries(Map<String, dynamic> document) {
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

  @override
  Widget build(BuildContext context) {
    final title = DocumentPayloadUtils.datalist(_displayDocument) ??
        DocumentPayloadUtils.title(_displayDocument);
    final actionLabel =
        widget.service.isSigningService ? 'Подписать' : 'Согласовать';

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        centerTitle: true,
      ),
      body: _buildBody(),
      bottomNavigationBar: _isLoading || _errorMessage != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _commentController,
                      decoration: const InputDecoration(
                        labelText: 'Комментарий',
                        hintText: 'Необязательно',
                      ),
                      minLines: 1,
                      maxLines: 3,
                      enabled: !_isSubmitting,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSubmitting ? null : _reject,
                            child: const Text('Отклонить'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _isSubmitting ? null : _accept,
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
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
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadDetails,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    final document = _displayDocument;
    final entries = _summaryEntries(document);
    final sides = _sides(document);
    final files = _files(document);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              DocumentPayloadUtils.datalist(document) ??
                  DocumentPayloadUtils.title(document),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Детали',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(entries[i].key),
                    subtitle: Text(entries[i].value),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (sides.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Стороны',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < sides.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(sides[i]['partner']?.toString() ?? 'Сторона'),
                    subtitle: Text(sides[i]['value']?.toString() ?? ''),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (files.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Файлы',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < files.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                            leading: const AppIcon(AppIcons.attachment),
                    title: Text(
                      files[i]['namefile']?.toString() ?? 'Файл',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (_acceptors.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Согласующие',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < _acceptors.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(
                      DocumentPayloadUtils.labelForAcceptor(_acceptors[i]),
                    ),
                    subtitle: () {
                      final status =
                          DocumentPayloadUtils.acceptorStatus(_acceptors[i]);
                      return status == null ? null : Text(status);
                    }(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
