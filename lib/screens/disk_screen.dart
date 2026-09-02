import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show RefreshIndicator, ScaffoldMessenger, SnackBar;
import 'package:intl/intl.dart';

import '../models/disk/disk_entry.dart';
import '../repositories/disk_repository.dart';
import '../services/api_client.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
import '../widgets/cupertino_prompt_dialog.dart';
import '../widgets/disk_share_sheet.dart';
import '../widgets/swipe_actions_row.dart';

/// Раздел «Диск» — просмотр, загрузка и шаринг файлов из Nextcloud
/// (`/api/nextcloud/*`). Онлайн-редактирование документов не поддерживается
/// бэкендом и в этой версии не реализовано.
class DiskScreen extends StatefulWidget {
  const DiskScreen({super.key, this.path = '', this.title});

  /// Путь текущей папки. Пустая строка — корень.
  final String path;
  final String? title;

  @override
  State<DiskScreen> createState() => _DiskScreenState();
}

/// Один уровень пути внутри «Диска» — хранится в [_DiskScreenState._pathStack]
/// вместо того, чтобы пушить новый [DiskScreen] на каждую вложенную папку
/// (раньше это раздувало стек `Navigator` на N уровней вложенности).
class _DiskPathEntry {
  const _DiskPathEntry({required this.path, this.title});

  final String path;
  final String? title;

  String get displayName {
    if (title != null && title!.isNotEmpty) return title!;
    if (path.isEmpty) return 'Диск';
    final segments = path.split('/').where((s) => s.isNotEmpty);
    return segments.isEmpty ? 'Диск' : segments.last;
  }
}

class _DiskScreenState extends State<DiskScreen> {
  late final List<_DiskPathEntry> _pathStack = [
    _DiskPathEntry(path: widget.path, title: widget.title),
  ];
  DiskListing? _listing;
  bool _isLoading = true;
  bool _isBusy = false;
  String? _errorMessage;
  int _loadToken = 0;
  final _swipeGroup = SwipeGroupController();

  _DiskPathEntry get _current => _pathStack.last;
  String get _currentPath => _current.path;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final listing = await DiskRepository.instance.listFolder(_currentPath);
      if (!mounted || token != _loadToken) return;
      setState(() {
        _listing = listing;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is ApiException
            ? e.message
            : 'Не удалось загрузить содержимое папки';
      });
    }
  }

  void _showError(String fallback, Object error) {
    final message = error is ApiException ? error.message : fallback;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  String _joinPath(String name) =>
      '$_currentPath/$name'.replaceAll(RegExp(r'/+'), '/');

  void _openFolder(DiskFolder folder) {
    setState(() {
      _pathStack.add(_DiskPathEntry(path: folder.path, title: folder.name));
    });
    _load();
  }

  void _popLevel() {
    if (_pathStack.length <= 1) return;
    setState(() => _pathStack.removeLast());
    _load();
  }

  void _popToLevel(int index) {
    if (index >= _pathStack.length - 1) return;
    setState(() => _pathStack.removeRange(index + 1, _pathStack.length));
    _load();
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoPromptDialog(
        title: 'Новая папка',
        content: CupertinoTextField(
          controller: controller,
          placeholder: 'Имя папки',
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
            label: 'Создать',
            isDefault: true,
            onPressed: () => Navigator.pop(context, controller.text.trim()),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    setState(() => _isBusy = true);
    try {
      await DiskRepository.instance.createFolder(_joinPath(name));
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось создать папку', e);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    setState(() => _isBusy = true);
    try {
      await DiskRepository.instance.uploadFile(
        bytes: bytes,
        filename: file.name,
        folder: _currentPath,
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось загрузить файл', e);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _deleteFolder(DiskFolder folder) async {
    final confirmed = await _confirmDelete(folder.name);
    if (confirmed != true) return;

    setState(() => _isBusy = true);
    try {
      await DiskRepository.instance.deleteFolder(folder.path);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось удалить папку', e);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _deleteFile(DiskFile file) async {
    final confirmed = await _confirmDelete(file.name);
    if (confirmed != true) return;

    setState(() => _isBusy = true);
    try {
      await DiskRepository.instance.deleteFile(file.path);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось удалить файл', e);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<bool?> _confirmDelete(String name) {
    return showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Удалить?'),
        content: Text('«$name» будет удалено без возможности восстановления.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  Future<Uint8List?> _downloadWithSpinner(DiskFile file) async {
    setState(() => _isBusy = true);
    try {
      final bytes = await DiskRepository.instance.downloadFile(file.path);
      return bytes;
    } catch (e) {
      if (mounted) _showError('Не удалось скачать файл', e);
      return null;
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _saveToDevice(DiskFile file) async {
    final bytes = await _downloadWithSpinner(file);
    if (bytes == null || !mounted) return;
    try {
      await FilePicker.platform.saveFile(fileName: file.name, bytes: bytes);
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось сохранить файл', e);
    }
  }

  void _shareFolder(DiskFolder folder) {
    DiskShareSheet.show(context, path: folder.path, name: folder.name);
  }

  void _shareFile(DiskFile file) {
    DiskShareSheet.show(context, path: file.path, name: file.name);
  }

  void _openFile(DiskFile file) {
    if (file.isImage) {
      Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (context) => _DiskImagePreviewScreen(file: file),
        ),
      );
      return;
    }

    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(file.name),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _saveToDevice(file);
            },
            child: const Text('Скачать'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _shareFile(file);
            },
            child: const Text('Поделиться'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              _deleteFile(file);
            },
            child: const Text('Удалить'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _pathStack.length <= 1,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _popLevel();
      },
      child: CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        navigationBar: CupertinoNavigationBar(
          leading: _pathStack.length > 1
              ? CupertinoNavigationBarBackButton(onPressed: _popLevel)
              : null,
          middle: Text(_current.displayName),
          backgroundColor: CupertinoColors.systemGroupedBackground,
          border: null,
          trailing: _isBusy
              ? const CupertinoActivityIndicator()
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      onPressed: _createFolder,
                      child: const Icon(
                        CupertinoIcons.folder_badge_plus,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      onPressed: _uploadFile,
                      child: const Icon(CupertinoIcons.cloud_upload, size: 24),
                    ),
                  ],
                ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              if (_pathStack.length > 1) _buildBreadcrumb(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreadcrumb() {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        itemCount: _pathStack.length,
        separatorBuilder: (context, index) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            CupertinoIcons.chevron_forward,
            size: 12,
            color: CupertinoColors.tertiaryLabel,
          ),
        ),
        itemBuilder: (context, index) {
          final entry = _pathStack[index];
          final isLast = index == _pathStack.length - 1;
          return Center(
            child: GestureDetector(
              onTap: isLast ? null : () => _popToLevel(index),
              child: Text(
                entry.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
                  color: isLast
                      ? CupertinoColors.label.resolveFrom(context)
                      : CupertinoColors.activeBlue,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const AppSkeletonList(count: 8);
    }

    if (_errorMessage != null) {
      return AppEmptyState(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: _errorMessage!,
        onRetry: _load,
      );
    }

    final listing = _listing;
    if (listing == null || listing.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: const AppEmptyState(
          icon: CupertinoIcons.folder,
          message: 'Здесь пока пусто',
        ),
      );
    }

    final rowCount = listing.folders.length + listing.files.length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: rowCount,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index < listing.folders.length) {
            final folder = listing.folders[index];
            return SwipeActionsRow(
              id: 'folder:${folder.path}',
              groupController: _swipeGroup,
              actions: [
                SwipeAction(
                  icon: CupertinoIcons.share,
                  label: 'Поделиться',
                  color: CupertinoColors.activeBlue,
                  onTap: () => _shareFolder(folder),
                ),
                SwipeAction(
                  icon: CupertinoIcons.delete,
                  label: 'Удалить',
                  color: CupertinoColors.destructiveRed,
                  onTap: () => _deleteFolder(folder),
                ),
              ],
              child: _DiskFolderTile(
                folder: folder,
                onTap: () => _openFolder(folder),
              ),
            );
          }

          final file = listing.files[index - listing.folders.length];
          return SwipeActionsRow(
            id: 'file:${file.path}',
            groupController: _swipeGroup,
            actions: [
              SwipeAction(
                icon: CupertinoIcons.share,
                label: 'Поделиться',
                color: CupertinoColors.activeBlue,
                onTap: () => _shareFile(file),
              ),
              SwipeAction(
                icon: CupertinoIcons.delete,
                label: 'Удалить',
                color: CupertinoColors.destructiveRed,
                onTap: () => _deleteFile(file),
              ),
            ],
            child: _DiskFileTile(file: file, onTap: () => _openFile(file)),
          );
        },
      ),
    );
  }
}

class _DiskFolderTile extends StatelessWidget {
  const _DiskFolderTile({required this.folder, required this.onTap});

  final DiskFolder folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _DiskTileContainer(
      onTap: onTap,
      leading: const _DiskIconBadge(
        icon: CupertinoIcons.folder_fill,
        color: CupertinoColors.systemYellow,
      ),
      title: folder.name,
      subtitle: folder.isShared ? 'Есть доступ у других' : null,
      trailing: const Icon(
        CupertinoIcons.chevron_forward,
        size: 18,
        color: CupertinoColors.tertiaryLabel,
      ),
    );
  }
}

class _DiskFileTile extends StatelessWidget {
  const _DiskFileTile({required this.file, required this.onTap});

  final DiskFile file;
  final VoidCallback onTap;

  String? get _subtitle {
    final parts = <String>[
      if (file.size != null) _formatSize(file.size!),
      if (file.lastModified != null)
        DateFormat(
          'd MMM, HH:mm',
          'ru_RU',
        ).format(file.lastModified!.toLocal()),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  @override
  Widget build(BuildContext context) {
    return _DiskTileContainer(
      onTap: onTap,
      leading: _DiskFormatBadge(file: file),
      title: file.name,
      subtitle: _subtitle,
      trailing: file.isShared
          ? const Icon(
              CupertinoIcons.person_2_fill,
              size: 16,
              color: CupertinoColors.systemBlue,
            )
          : null,
    );
  }
}

class _DiskIconBadge extends StatelessWidget {
  const _DiskIconBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 19, color: color),
    );
  }
}

/// Иконка файла в стиле Files на iPhone: белая «страница» с цветным
/// лейблом формата снизу вместо превью, которого у нас нет.
class _DiskFormatBadge extends StatelessWidget {
  const _DiskFormatBadge({required this.file});

  final DiskFile file;

  String get _extension {
    final dot = file.name.lastIndexOf('.');
    if (dot <= 0 || dot == file.name.length - 1) return '';
    final ext = file.name.substring(dot + 1).toUpperCase();
    return ext.length > 4 ? ext.substring(0, 4) : ext;
  }

  Color get _color {
    final mime = file.mime ?? '';
    final ext = _extension.toLowerCase();
    if (file.isImage) return CupertinoColors.systemOrange;
    if (mime.contains('pdf') || ext == 'pdf') return CupertinoColors.systemRed;
    if (mime.startsWith('video/')) return CupertinoColors.systemPurple;
    if (mime.startsWith('audio/')) return CupertinoColors.systemPink;
    if (mime.contains('zip') ||
        mime.contains('archive') ||
        const ['zip', 'rar', '7z'].contains(ext)) {
      return CupertinoColors.systemBrown;
    }
    if (const ['xls', 'xlsx', 'csv'].contains(ext))
      return CupertinoColors.systemGreen;
    if (const ['doc', 'docx'].contains(ext)) return CupertinoColors.systemBlue;
    if (const ['ppt', 'pptx'].contains(ext))
      return CupertinoColors.systemOrange;
    return CupertinoColors.systemGrey;
  }

  @override
  Widget build(BuildContext context) {
    final extension = _extension;
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            CupertinoIcons.doc_fill,
            size: 34,
            color: CupertinoColors.systemGrey4,
          ),
          if (extension.isNotEmpty)
            Positioned(
              bottom: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  extension,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: CupertinoColors.white,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DiskTileContainer extends StatelessWidget {
  const _DiskTileContainer({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

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
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.secondaryLabel,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class _DiskImagePreviewScreen extends StatefulWidget {
  const _DiskImagePreviewScreen({required this.file});

  final DiskFile file;

  @override
  State<_DiskImagePreviewScreen> createState() =>
      _DiskImagePreviewScreenState();
}

class _DiskImagePreviewScreenState extends State<_DiskImagePreviewScreen> {
  Uint8List? _bytes;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final bytes = await DiskRepository.instance.downloadFile(
        widget.file.path,
      );
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is ApiException
            ? e.message
            : 'Не удалось открыть файл';
      });
    }
  }

  Future<void> _download() async {
    setState(() => _isSaving = true);
    try {
      final bytes =
          _bytes ??
          await DiskRepository.instance.downloadFile(widget.file.path);
      if (!mounted) return;
      await FilePicker.platform.saveFile(
        fileName: widget.file.name,
        bytes: bytes,
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось сохранить файл', e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String fallback, Object error) {
    final message = error is ApiException ? error.message : fallback;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildUnsupportedFormat() {
    return AppEmptyState(
      icon: CupertinoIcons.photo,
      message: 'Этот формат изображения нельзя посмотреть здесь',
      onRetry: _isSaving ? null : _download,
      retryLabel: 'Скачать файл',
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          widget.file.name,
          style: const TextStyle(color: CupertinoColors.white),
        ),
        backgroundColor: CupertinoColors.black,
        border: null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: _isSaving ? null : _download,
              child: _isSaving
                  ? const CupertinoActivityIndicator(
                      color: CupertinoColors.white,
                    )
                  : const Icon(
                      CupertinoIcons.arrow_down_to_line,
                      color: CupertinoColors.white,
                    ),
            ),
            const SizedBox(width: 16),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: () => DiskShareSheet.show(
                context,
                path: widget.file.path,
                name: widget.file.name,
              ),
              child: const Icon(
                CupertinoIcons.share,
                color: CupertinoColors.white,
              ),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: _isLoading
              ? const AppPageLoader()
              : _errorMessage != null
              ? AppEmptyState(
                  icon: CupertinoIcons.exclamationmark_triangle,
                  message: _errorMessage!,
                  onRetry: _load,
                )
              : InteractiveViewer(
                  child: Image.memory(
                    _bytes!,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildUnsupportedFormat(),
                  ),
                ),
        ),
      ),
    );
  }
}
