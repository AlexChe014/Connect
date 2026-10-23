import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import '../config/app_theme.dart';
import '../repositories/news_repository.dart';
import '../utils/file_size_format.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/booking_glass_form.dart';
import '../widgets/mail_glass.dart';

class _PendingFile {
  final String filename;
  final Uint8List bytes;
  final bool isPicture;

  const _PendingFile({
    required this.filename,
    required this.bytes,
    required this.isPicture,
  });
}

const _kEmojiList = <String>[
  '😀',
  '😁',
  '😂',
  '🤣',
  '😊',
  '😍',
  '😘',
  '😎',
  '🤔',
  '😅',
  '😉',
  '🙂',
  '😴',
  '🥳',
  '😢',
  '😭',
  '😡',
  '👍',
  '👎',
  '👏',
  '🙏',
  '💪',
  '🔥',
  '✨',
  '🎉',
  '❤️',
  '💙',
  '💚',
  '💛',
  '💜',
  '⭐',
  '✅',
  '❌',
  '📌',
  '📷',
  '📢',
  '🚀',
  '🏆',
  '☕',
  '🎂',
  '🎁',
  '⏰',
  '📅',
  '💡',
  '📎',
];

/// Создание новости (`POST /dashboard/news/create`).
class NewsCreateScreen extends StatefulWidget {
  const NewsCreateScreen({super.key});

  @override
  State<NewsCreateScreen> createState() => _NewsCreateScreenState();
}

class _NewsCreateScreenState extends State<NewsCreateScreen> {
  final _titleController = TextEditingController();
  final QuillController _quillController = QuillController.basic();
  final _titleFocusNode = FocusNode();
  final _editorFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  final List<_PendingFile> _files = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_onTitleChanged);
  }

  @override
  void dispose() {
    _titleController
      ..removeListener(_onTitleChanged)
      ..dispose();
    _quillController.dispose();
    _titleFocusNode.dispose();
    _editorFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTitleChanged() => setState(() {});

  bool get _canPublish => _titleController.text.trim().isNotEmpty;

  bool get _hasUnsavedChanges =>
      _files.isNotEmpty ||
      _titleController.text.trim().isNotEmpty ||
      _quillController.document.toPlainText().trim().isNotEmpty;

  List<_PendingFile> get _pictures => _files.where((f) => f.isPicture).toList();

  List<_PendingFile> get _documents =>
      _files.where((f) => !f.isPicture).toList();

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
    // Без withData на iOS и Android bytes == null — файл молча терялся.
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
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
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        message: Wrap(
          alignment: WrapAlignment.center,
          children: [
            for (final emoji in _kEmojiList)
              CupertinoButton(
                padding: const EdgeInsets.all(6),
                minimumSize: Size.zero,
                onPressed: () {
                  _insertEmoji(emoji);
                  Navigator.pop(sheetContext);
                },
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
          ],
        ),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Отмена'),
        ),
      ),
    );
  }

  /// Первое фото поста — обложка в ленте.
  void _makeCover(_PendingFile file) {
    setState(() {
      _files
        ..remove(file)
        ..insert(0, file);
    });
  }

  void _removePendingFile(_PendingFile file) {
    setState(() => _files.remove(file));
  }

  Future<void> _showPictureActions(_PendingFile file) async {
    final isCover = identical(_pictures.first, file);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          if (!isCover)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                _makeCover(file);
              },
              child: const Text('Сделать обложкой'),
            ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              _removePendingFile(file);
            },
            child: const Text('Удалить фото'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
    );
  }

  /// Выход без публикации: набранный пост пропадал молча.
  Future<void> _confirmDiscard() async {
    final discard = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Пост не опубликован'),
        message: const Text('Если выйти, набранный текст и вложения пропадут.'),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить черновик'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Продолжить редактирование'),
        ),
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    if (!_canPublish || _isSaving) return;
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _isSaving = true);
    try {
      final pictures = _pictures
          .map(
            (f) => http.MultipartFile.fromBytes(
              'pictures[]',
              f.bytes,
              filename: f.filename,
            ),
          )
          .toList();
      final documents = _documents
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
        const SnackBar(content: Text('Не удалось опубликовать пост')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Заголовок и текст — одной стеклянной карточкой, как заметка:
  /// заголовок крупно во всю ширину и переносится, а не обрезается.
  Widget _buildComposeCard(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final placeholder = CupertinoColors.placeholderText.resolveFrom(context);
    final bodyStyle = TextStyle(fontSize: 16, height: 1.35, color: label);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppGlass(
        borderRadius: BorderRadius.circular(22),
        shadows: AppGlass.controlShadow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CupertinoTextField(
              controller: _titleController,
              focusNode: _titleFocusNode,
              placeholder: 'Заголовок',
              autofocus: true,
              enabled: !_isSaving,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _editorFocusNode.requestFocus(),
              decoration: const BoxDecoration(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                height: 1.25,
                color: label,
              ),
              placeholderStyle: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                height: 1.25,
                color: placeholder,
              ),
            ),
            Container(
              height: 0.5,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: CupertinoColors.separator.resolveFrom(context),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 180),
              child: Material(
                type: MaterialType.transparency,
                child: QuillEditor(
                  controller: _quillController,
                  focusNode: _editorFocusNode,
                  // Редактор растёт вместе с текстом, а курсор держит
                  // в поле зрения общий список экрана.
                  scrollController: _scrollController,
                  config: QuillEditorConfig(
                    placeholder: 'Текст поста',
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    scrollable: false,
                    expands: false,
                    scrollBottomInset: MailFloatingBar.reservedHeight(context),
                    customStyles: DefaultStyles(
                      paragraph: DefaultTextBlockStyle(
                        bodyStyle,
                        HorizontalSpacing.zero,
                        VerticalSpacing.zero,
                        VerticalSpacing.zero,
                        null,
                      ),
                      placeHolder: DefaultTextBlockStyle(
                        bodyStyle.copyWith(color: placeholder),
                        HorizontalSpacing.zero,
                        VerticalSpacing.zero,
                        VerticalSpacing.zero,
                        null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Фото — миниатюрами в ряд; первое подписано как обложка.
  Widget _buildPictures(BuildContext context) {
    final pictures = _pictures;
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: pictures.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final file = pictures[index];
          return _PictureThumb(
            file: file,
            isCover: index == 0 && pictures.length > 1,
            onTap: _isSaving ? null : () => _showPictureActions(file),
            onRemove: _isSaving ? null : () => _removePendingFile(file),
          );
        },
      ),
    );
  }

  Widget _buildDocuments(BuildContext context) {
    return AppGlassSection(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      children: [
        for (final file in _documents)
          CupertinoListTile(
            leading: const AppIconBadge(
              icon: CupertinoIcons.doc_fill,
              color: CupertinoColors.systemGrey,
            ),
            title: Text(
              file.filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15),
            ),
            subtitle: Text(formatFileSize(file.bytes.length)),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: _isSaving ? null : () => _removePendingFile(file),
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 22,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pictures = _pictures;
    return PopScope(
      canPop: _isSaving || !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isSaving) _confirmDiscard();
      },
      child: BookingGlassScaffold(
        title: 'Новый пост',
        canPop: !_isSaving,
        controller: _scrollController,
        trailing: BookingNavAction(
          label: 'Опубликовать',
          isLoading: _isSaving,
          onPressed: _canPublish ? _submit : null,
        ),
        bottomBar: MailFloatingBar(
          child: _FormatBar(
            controller: _quillController,
            editorFocusNode: _editorFocusNode,
            enabled: !_isSaving,
            onEmoji: _showEmojiPicker,
            onPhoto: _pickPictures,
            onFile: _pickDocuments,
          ),
        ),
        bottomBarHeight: MailFloatingBar.reservedHeight(context),
        children: [
          _buildComposeCard(context),
          if (pictures.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildPictures(context),
            if (pictures.length > 1)
              const BookingFootnote(
                'Первое фото — обложка поста в ленте. Нажмите на фото, '
                'чтобы сделать обложкой другое.',
              ),
          ],
          if (_documents.isNotEmpty) _buildDocuments(context),
        ],
      ),
    );
  }
}

/// Миниатюра выбранного фото с кнопкой «убрать».
class _PictureThumb extends StatelessWidget {
  const _PictureThumb({
    required this.file,
    required this.isCover,
    required this.onTap,
    required this.onRemove,
  });

  final _PendingFile file;
  final bool isCover;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 96,
        height: 96,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                file.bytes,
                fit: BoxFit.cover,
                cacheWidth: 288,
                gaplessPlayback: true,
              ),
            ),
            if (isCover)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    color: AppColors.scrimStrong,
                    child: const Text(
                      'Обложка',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.white,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: AppColors.scrimButton,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    CupertinoIcons.xmark,
                    size: 12,
                    color: CupertinoColors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Нижняя стеклянная панель: форматирование текста и вложения.
/// Кнопки стиля подсвечены, когда стиль включён у текста под курсором.
class _FormatBar extends StatelessWidget {
  const _FormatBar({
    required this.controller,
    required this.editorFocusNode,
    required this.enabled,
    required this.onEmoji,
    required this.onPhoto,
    required this.onFile,
  });

  final QuillController controller;
  final FocusNode editorFocusNode;
  final bool enabled;
  final VoidCallback onEmoji;
  final VoidCallback onPhoto;
  final VoidCallback onFile;

  bool _isActive(Attribute attribute) {
    final current = controller.getSelectionStyle().attributes[attribute.key];
    return current != null && current.value == attribute.value;
  }

  void _toggle(Attribute attribute) {
    controller.formatSelection(
      _isActive(attribute) ? Attribute.clone(attribute, null) : attribute,
    );
    // Стиль ставится на выделение — курсор должен остаться в тексте.
    if (!editorFocusNode.hasFocus) editorFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    // Панель — часть поля ввода: касание её кнопок не считается
    // «касанием мимо» и не снимает фокус с редактора.
    return TextFieldTapRegion(
      child: AppGlass(
        borderRadius: BorderRadius.circular(MailFloatingBar.height / 2),
        shadows: AppGlass.controlShadow,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            Widget style(IconData icon, Attribute attribute, String label) =>
                _FormatButton(
                  icon: icon,
                  label: label,
                  isActive: _isActive(attribute),
                  onPressed: enabled ? () => _toggle(attribute) : null,
                );
            return Row(
              children: [
                const SizedBox(width: 6),
                style(CupertinoIcons.bold, Attribute.bold, 'Жирный'),
                style(CupertinoIcons.italic, Attribute.italic, 'Курсив'),
                style(
                  CupertinoIcons.underline,
                  Attribute.underline,
                  'Подчёркнутый',
                ),
                style(CupertinoIcons.list_bullet, Attribute.ul, 'Список'),
                style(
                  CupertinoIcons.list_number,
                  Attribute.ol,
                  'Нумерованный список',
                ),
                Container(
                  width: 0.5,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: CupertinoColors.separator.resolveFrom(context),
                ),
                _FormatButton(
                  icon: CupertinoIcons.smiley,
                  label: 'Эмодзи',
                  onPressed: enabled ? onEmoji : null,
                ),
                _FormatButton(
                  icon: CupertinoIcons.photo,
                  label: 'Фото',
                  onPressed: enabled ? onPhoto : null,
                ),
                _FormatButton(
                  icon: CupertinoIcons.paperclip,
                  label: 'Файл',
                  onPressed: enabled ? onFile : null,
                ),
                const SizedBox(width: 6),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = onPressed == null
        ? CupertinoColors.tertiaryLabel.resolveFrom(context)
        : CupertinoColors.label.resolveFrom(context);
    return Expanded(
      child: Semantics(
        button: true,
        selected: isActive,
        label: label,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(36, 36),
          onPressed: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? CupertinoColors.tertiarySystemFill.resolveFrom(context)
                  : Colors.transparent,
            ),
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}
