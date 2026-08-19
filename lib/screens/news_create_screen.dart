import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

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

const _kEmojiList = <String>[
  '😀', '😁', '😂', '🤣', '😊', '😍', '😘', '😎', '🤔', '😅',
  '😉', '🙂', '😴', '🥳', '😢', '😭', '😡', '👍', '👎', '👏',
  '🙏', '💪', '🔥', '✨', '🎉', '❤️', '💙', '💚', '💛', '💜',
  '⭐', '✅', '❌', '📌', '📷', '📢', '🚀', '🏆', '☕', '🎂',
  '🎁', '⏰', '📅', '💡', '📎',
];

/// Создание новости (`POST /dashboard/news/create`).
class NewsCreateScreen extends StatefulWidget {
  const NewsCreateScreen({super.key});

  @override
  State<NewsCreateScreen> createState() => _NewsCreateScreenState();
}

class _NewsCreateScreenState extends State<NewsCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final QuillController _quillController = QuillController.basic();
  final _editorFocusNode = FocusNode();
  final _editorScrollController = ScrollController();
  final _picker = ImagePicker();
  final List<_PendingFile> _files = [];
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _quillController.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  Future<void> _pickPictures() async {
    final images = await _picker.pickMultiImage();
    if (images.isEmpty || !mounted) return;

    final picked = <_PendingFile>[];
    for (final image in images) {
      final bytes = await image.readAsBytes();
      picked.add(
        _PendingFile(filename: image.name, bytes: bytes, isPicture: true),
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
        _PendingFile(filename: file.name, bytes: bytes, isPicture: false),
      );
    }
    if (picked.isEmpty || !mounted) return;
    setState(() => _files.addAll(picked));
  }

  void _removeFile(int index) {
    setState(() => _files.removeAt(index));
  }

  void _insertEmoji(String emoji) {
    final document = _quillController.document;
    var index = _quillController.selection.baseOffset;
    if (index < 0 || index > document.length - 1) {
      index = document.length - 1;
    }
    _quillController.replaceText(
      index,
      0,
      emoji,
      TextSelection.collapsed(offset: index + emoji.length),
    );
  }

  Future<void> _showEmojiPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          CupertinoColors.systemGroupedBackground.resolveFrom(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
            child: Wrap(
              alignment: WrapAlignment.start,
              children: _kEmojiList.map((emoji) {
                return CupertinoButton(
                  padding: const EdgeInsets.all(6),
                  minimumSize: Size.zero,
                  onPressed: () {
                    _insertEmoji(emoji);
                    Navigator.pop(sheetContext);
                  },
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
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

      final plainText = _quillController.document.toPlainText().trim();
      String? html;
      if (plainText.isNotEmpty) {
        final ops = _quillController.document.toDelta().toJson();
        html = QuillDeltaToHtmlConverter(
          ops,
          ConverterOptions.forEmail(),
        ).convert();
      }

      await NewsRepository.instance.create(
        title: _titleController.text.trim(),
        text: html,
        pictures: pictures,
        documents: documents,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось создать новость')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _iconBadge(IconData icon, Color color) {
    return Container(
      width: 29,
      height: 29,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(7)),
      child: Icon(icon, size: 17, color: CupertinoColors.white),
    );
  }

  Widget _buildEditorCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            QuillSimpleToolbar(
              controller: _quillController,
              config: QuillSimpleToolbarConfig(
                showFontFamily: false,
                showFontSize: false,
                showSmallButton: false,
                showStrikeThrough: false,
                showInlineCode: false,
                showAlignmentButtons: false,
                showHeaderStyle: false,
                showListCheck: false,
                showCodeBlock: false,
                showQuote: false,
                showIndent: false,
                showUndo: false,
                showRedo: false,
                showSearchButton: false,
                showSubscript: false,
                showSuperscript: false,
                showDividers: false,
                showLineHeightButton: false,
                multiRowsDisplay: false,
                toolbarIconAlignment: WrapAlignment.start,
                customButtons: [
                  QuillToolbarCustomButtonOptions(
                    icon: const Icon(CupertinoIcons.smiley, size: 18),
                    tooltip: 'Эмодзи',
                    onPressed: _showEmojiPicker,
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: CupertinoColors.separator.resolveFrom(context),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 160, maxHeight: 260),
              child: QuillEditor(
                controller: _quillController,
                focusNode: _editorFocusNode,
                scrollController: _editorScrollController,
                config: const QuillEditorConfig(
                  placeholder: 'Текст новости…',
                  padding: EdgeInsets.all(12),
                  expands: false,
                  scrollable: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Новая новость'),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Icon(CupertinoIcons.back, size: 26),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const CupertinoActivityIndicator()
              : const Text(
                  'Опубликовать',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
        ),
      ),
      // Без Material-предка любой Text, не переопределивший все поля стиля
      // явно, откатывается на debug-заглушку MaterialApp — этот
      // DefaultTextStyle подстраховывает весь экран разом (см. тот же
      // приём в create_booking_screen.dart).
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 16,
        ),
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 32),
              children: [
                CupertinoFormSection.insetGrouped(
                  children: [
                    CupertinoTextFormFieldRow(
                      controller: _titleController,
                      prefix: const Text('Заголовок'),
                      placeholder: 'Например, Новости компании',
                      textCapitalization: TextCapitalization.sentences,
                      textAlign: TextAlign.end,
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Введите заголовок'
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'ТЕКСТ',
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildEditorCard(context),
                ),
                const SizedBox(height: 20),
                CupertinoListSection.insetGrouped(
                  children: [
                    CupertinoListTile(
                      leading: _iconBadge(
                        CupertinoIcons.photo_on_rectangle,
                        CupertinoColors.systemBlue,
                      ),
                      title: const Text('Фото'),
                      trailing: const CupertinoListTileChevron(),
                      onTap: _isSaving ? null : _pickPictures,
                    ),
                    CupertinoListTile(
                      leading: _iconBadge(
                        CupertinoIcons.doc_text,
                        CupertinoColors.systemGrey,
                      ),
                      title: const Text('Документы'),
                      trailing: const CupertinoListTileChevron(),
                      onTap: _isSaving ? null : _pickDocuments,
                    ),
                  ],
                ),
                if (_files.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  CupertinoListSection.insetGrouped(
                    header: const Text('Вложения'),
                    children: List.generate(_files.length, (index) {
                      final file = _files[index];
                      return CupertinoListTile(
                        leading: _iconBadge(
                          file.isPicture
                              ? CupertinoIcons.photo
                              : CupertinoIcons.doc_text,
                          file.isPicture
                              ? CupertinoColors.systemBlue
                              : CupertinoColors.systemGrey,
                        ),
                        title: Text(
                          file.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(file.isPicture ? 'Изображение' : 'Документ'),
                        trailing: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          onPressed: _isSaving ? null : () => _removeFile(index),
                          child: const Icon(
                            CupertinoIcons.minus_circle_fill,
                            color: CupertinoColors.systemRed,
                            size: 22,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
