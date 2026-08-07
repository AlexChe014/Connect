import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config/app_icons.dart';
import '../repositories/news_repository.dart';

class _PendingFile {
  final String filename;
  final List<int> bytes;
  final bool isPicture;

  const _PendingFile({
    required this.filename,
    required this.bytes,
    required this.isPicture,
  });
}

/// Создание новости (`POST /dashboard/news/create`).
class NewsCreateScreen extends StatefulWidget {
  const NewsCreateScreen({super.key});

  @override
  State<NewsCreateScreen> createState() => _NewsCreateScreenState();
}

class _NewsCreateScreenState extends State<NewsCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _textController = TextEditingController();
  final _picker = ImagePicker();
  final List<_PendingFile> _files = [];
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickPictures() async {
    final images = await _picker.pickMultiImage();
    if (images.isEmpty || !mounted) return;

    final picked = <_PendingFile>[];
    for (final image in images) {
      final bytes = await image.readAsBytes();
      picked.add(
        _PendingFile(
          filename: image.name,
          bytes: bytes,
          isPicture: true,
        ),
      );
    }
    if (!mounted || picked.isEmpty) return;
    setState(() => _files.addAll(picked));
  }

  Future<void> _pickDocuments() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || !mounted) return;

    final picked = <_PendingFile>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      picked.add(
        _PendingFile(
          filename: file.name,
          bytes: bytes,
          isPicture: false,
        ),
      );
    }
    if (picked.isEmpty || !mounted) return;
    setState(() => _files.addAll(picked));
  }

  void _removeFile(int index) {
    setState(() => _files.removeAt(index));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final pictures = _files
          .where((f) => f.isPicture)
          .map(
            (f) => http.MultipartFile.fromBytes(
              'pictures[]',
              f.bytes,
              filename: f.filename,
            ),
          )
          .toList();
      final documents = _files
          .where((f) => !f.isPicture)
          .map(
            (f) => http.MultipartFile.fromBytes(
              'documents[]',
              f.bytes,
              filename: f.filename,
            ),
          )
          .toList();

      await NewsRepository.instance.create(
        title: _titleController.text.trim(),
        text: _textController.text.trim(),
        pictures: pictures,
        documents: documents,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось создать новость')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новая новость'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _submit,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Опубликовать'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Заголовок',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Введите заголовок';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _textController,
              minLines: 6,
              maxLines: 16,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Текст',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _pickPictures,
                  icon: const AppIcon(AppIcons.attachment, size: 18),
                  label: const Text('Фото'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _pickDocuments,
                  icon: const AppIcon(AppIcons.documents, size: 18),
                  label: const Text('Документы'),
                ),
              ],
            ),
            if (_files.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...List.generate(_files.length, (index) {
                final file = _files[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: AppIcon(
                    file.isPicture ? AppIcons.news : AppIcons.documents,
                    size: 20,
                  ),
                  title: Text(file.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(file.isPicture ? 'Изображение' : 'Документ'),
                  trailing: IconButton(
                    onPressed: _isSaving ? null : () => _removeFile(index),
                    icon: const AppIcon(AppIcons.close, size: 18),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
