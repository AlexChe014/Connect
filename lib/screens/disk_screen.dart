import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Colors, RefreshIndicator, ScaffoldMessenger, SnackBar;
import '../services/haptics_service.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_theme.dart';
import '../models/disk/disk_entry.dart';
import '../repositories/disk_repository.dart';
import '../services/api_client.dart';
import '../utils/file_size_format.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_title_bar.dart';
import '../widgets/cupertino_prompt_dialog.dart';
import '../widgets/mail_glass.dart';
import '../widgets/swipe_actions_row.dart';

/// Раздел «Диск» — просмотр, загрузка и открытие файлов из Nextcloud
/// (`/api/nextcloud/*`). Онлайн-редактирование документов не поддерживается
/// бэкендом и в этой версии не реализовано.
///
/// Каждая папка — отдельный экран в `Navigator`, как в Files на iPhone:
/// работает системный свайп «назад» и анимация перехода.
class DiskScreen extends StatefulWidget {
  const DiskScreen({
    super.key,
    this.path = '',
    this.title,
    this.highlightName,
    this.inheritedLevels = 0,
  });

  /// Путь текущей папки. Пустая строка — корень.
  final String path;
  final String? title;

  /// Файл, который нужно показать и подсветить после загрузки (переход из
  /// глобального поиска).
  final String? highlightName;

  /// Сколько экранов «Диска» лежит в стеке под этим — по ним «хлебные
  /// крошки» возвращаются через `pop`, а не открывают папку заново.
  final int inheritedLevels;

  @override
  State<DiskScreen> createState() => _DiskScreenState();
}

/// Порядок строк; папки всегда идут перед файлами.
enum _DiskSort {
  name('По имени'),
  date('По дате изменения'),
  size('По размеру');

  const _DiskSort(this.label);

  final String label;
}

/// Одно звено пути в «хлебных крошках».
class _DiskCrumb {
  const _DiskCrumb({required this.path, required this.name});

  final String path;
  final String name;
}

/// Долгая операция с прогрессом (загрузка, открытие) — стеклянная капсула
/// над нижней панелью.
class _DiskTask {
  const _DiskTask(this.label, [this.progress]);

  final String label;

  /// 0…1; `null` — размер неизвестен, показывается только подпись.
  final double? progress;
}

class _DiskScreenState extends State<DiskScreen> {
  static const _sortPrefsKey = 'disk_sort';

  /// Порядок общий для всех экранов «Диска» и запоминается между запусками.
  static _DiskSort? _savedSort;

  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _swipeGroup = SwipeGroupController();
  final _highlightKey = GlobalKey();

  DiskListing? _listing;
  bool _isLoading = true;
  bool _isBusy = false;
  String? _errorMessage;
  int _loadToken = 0;
  String _query = '';
  _DiskSort _sort = _savedSort ?? _DiskSort.name;
  _DiskTask? _task;
  String? _highlighted;
  bool _highlightDone = false;
  Timer? _highlightTimer;

  String get _currentPath => widget.path;

  List<String> get _segments => DiskRepository.toApiPath(
    widget.path,
  ).split('/').where((s) => s.isNotEmpty).map(_decodeSegment).toList();

  String get _displayName {
    final title = widget.title;
    if (title != null && title.isNotEmpty) return title;
    final segments = _segments;
    return segments.isEmpty ? 'Диск' : segments.last;
  }

  /// Предки текущей папки — от корня до родителя.
  List<_DiskCrumb> get _crumbs {
    final segments = _segments;
    return [
      for (var i = 0; i < segments.length; i++)
        _DiskCrumb(
          path: segments.take(i).join('/'),
          name: i == 0 ? 'Диск' : segments[i - 1],
        ),
    ];
  }

  /// WebDAV отдаёт пути с процентным кодированием (`Мои%20файлы`).
  static String _decodeSegment(String segment) {
    try {
      return Uri.decodeComponent(segment);
    } catch (_) {
      return segment;
    }
  }

  @override
  void initState() {
    super.initState();
    final cached = DiskRepository.instance.cachedListing(_currentPath);
    if (cached != null) {
      _listing = cached;
      _isLoading = false;
      _load(silent: true);
    } else {
      _load();
    }
    if (_savedSort == null) _restoreSort();
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _restoreSort() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = _DiskSort.values.asNameMap()[prefs.getString(_sortPrefsKey)];
    _savedSort = saved ?? _DiskSort.name;
    if (mounted && saved != null && saved != _sort) {
      setState(() => _sort = saved);
    }
  }

  /// [silent] — обновление жестом или из кэша: список остаётся на месте,
  /// без скелетона.
  Future<void> _load({bool silent = false}) async {
    final token = ++_loadToken;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final listing = await DiskRepository.instance.listFolder(_currentPath);
      if (!mounted || token != _loadToken) return;
      setState(() {
        _listing = listing;
        _isLoading = false;
        _errorMessage = null;
      });
      _revealHighlightOnce();
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      // Обновление жестом при уже открытой папке не прячет её за ошибкой.
      if (silent && _listing != null && _errorMessage == null) {
        _showError('Не удалось обновить папку', e);
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = e is ApiException
            ? e.message
            : 'Не удалось загрузить содержимое папки';
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(String fallback, Object error) =>
      _showMessage(error is ApiException ? error.message : fallback);

  String _joinPath(String name) =>
      '${DiskRepository.toApiPath(_currentPath)}/$name'.replaceAll(
        RegExp(r'^/+'),
        '',
      );

  // ---------------------------------------------------------------------
  // Сортировка и поиск
  // ---------------------------------------------------------------------

  static int _byName(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  /// Сначала новые; без даты — в конце.
  static int _byDate(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  List<DiskFolder> _visibleFolders(DiskListing listing) {
    final q = _query.trim().toLowerCase();
    final folders = listing.folders
        .where((f) => q.isEmpty || f.name.toLowerCase().contains(q))
        .toList();
    folders.sort(
      (a, b) => _sort == _DiskSort.date
          ? _byDate(a.lastModified, b.lastModified)
          : _byName(a.name, b.name),
    );
    return folders;
  }

  List<DiskFile> _visibleFiles(DiskListing listing) {
    final q = _query.trim().toLowerCase();
    final files = listing.files
        .where((f) => q.isEmpty || f.name.toLowerCase().contains(q))
        .toList();
    files.sort(
      (a, b) => switch (_sort) {
        _DiskSort.name => _byName(a.name, b.name),
        _DiskSort.date => _byDate(a.lastModified, b.lastModified),
        _DiskSort.size => (b.size ?? -1).compareTo(a.size ?? -1),
      },
    );
    return files;
  }

  Future<void> _showSortMenu() async {
    final selected = await showCupertinoModalPopup<_DiskSort>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Сортировка'),
        actions: [
          for (final sort in _DiskSort.values)
            CupertinoActionSheetAction(
              isDefaultAction: sort == _sort,
              onPressed: () => Navigator.pop(context, sort),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(sort.label),
                  if (sort == _sort) ...[
                    const SizedBox(width: 8),
                    const Icon(CupertinoIcons.checkmark_alt, size: 20),
                  ],
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (selected == null || selected == _sort || !mounted) return;
    setState(() => _sort = selected);
    _savedSort = selected;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortPrefsKey, selected.name);
  }

  /// Переход из поиска: прокрутить к файлу и коротко подсветить строку.
  void _revealHighlightOnce() {
    final name = widget.highlightName;
    final listing = _listing;
    if (_highlightDone || name == null || listing == null) return;
    _highlightDone = true;

    final folders = _visibleFolders(listing);
    final fileIndex = _visibleFiles(listing).indexWhere((f) => f.name == name);
    if (fileIndex < 0) return;
    final index = folders.length + fileIndex;

    setState(() => _highlighted = name);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_scrollController.hasClients) return;
      // Строки строятся лениво: далёкой ещё нет в дереве — сначала
      // прокручиваем примерно к ней (строка ≈ 58pt), потом точно.
      if (_highlightKey.currentContext == null) {
        final position = _scrollController.position;
        _scrollController.jumpTo(
          (index * 58.0).clamp(0, position.maxScrollExtent),
        );
        await WidgetsBinding.instance.endOfFrame;
      }
      final rowContext = _highlightKey.currentContext;
      if (rowContext != null && rowContext.mounted) {
        await Scrollable.ensureVisible(
          rowContext,
          alignment: 0.4,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
    _highlightTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _highlighted = null);
    });
  }

  // ---------------------------------------------------------------------
  // Навигация
  // ---------------------------------------------------------------------

  Future<void> _openFolder(DiskFolder folder) async {
    _swipeGroup.closeAll();
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (context) => DiskScreen(
          path: folder.path,
          title: folder.name,
          inheritedLevels: widget.inheritedLevels + 1,
        ),
      ),
    );
    // Внутри могли загрузить или удалить файлы — обновляем без скелетона.
    if (mounted) _load(silent: true);
  }

  void _openCrumb(int index) {
    final navigator = Navigator.of(context);
    final steps = _crumbs.length - index;
    if (steps <= widget.inheritedLevels) {
      var left = steps;
      navigator.popUntil((_) => left-- <= 0);
      return;
    }
    // Нужной папки в стеке нет (экран открыт из поиска) — снимаем свои
    // экраны и заменяем нижний на неё.
    var left = widget.inheritedLevels;
    navigator.popUntil((_) => left-- <= 0);
    final crumb = _crumbs[index];
    navigator.pushReplacement(
      CupertinoPageRoute<void>(
        builder: (context) => DiskScreen(
          path: crumb.path,
          title: crumb.path.isEmpty ? null : crumb.name,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Создание и загрузка
  // ---------------------------------------------------------------------

  /// Причина, по которой имя папки нельзя использовать, или `null`.
  String? _folderNameError(String name) {
    if (name.isEmpty) return null;
    if (name.contains('/') || name.contains('\\')) {
      return 'Имя не может содержать «/» и «\\»';
    }
    if (name == '.' || name == '..') return 'Недопустимое имя';
    final lower = name.toLowerCase();
    final listing = _listing;
    final taken =
        listing != null &&
        (listing.folders.any((f) => f.name.toLowerCase() == lower) ||
            listing.files.any((f) => f.name.toLowerCase() == lower));
    return taken ? 'Папка или файл с таким именем уже есть' : null;
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final value = controller.text.trim();
          final error = _folderNameError(value);
          final canCreate = value.isNotEmpty && error == null;
          void submit() {
            if (canCreate) Navigator.pop(context, value);
          }

          return CupertinoPromptDialog(
            title: 'Новая папка',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CupertinoTextField(
                  controller: controller,
                  placeholder: 'Имя папки',
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (_) => submit(),
                ),
                if (error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    error,
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.systemRed.resolveFrom(context),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              CupertinoPromptDialogAction(
                label: 'Отмена',
                onPressed: () => Navigator.pop(context),
              ),
              CupertinoPromptDialogAction(
                label: 'Создать',
                isDefault: true,
                onPressed: canCreate ? submit : null,
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;

    setState(() => _isBusy = true);
    try {
      await DiskRepository.instance.createFolder(_joinPath(name));
      if (!mounted) return;
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось создать папку', e);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _showAddMenu() async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'media'),
            child: const Text('Фото и видео'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'files'),
            child: const Text('Файлы'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'folder'),
            child: const Text('Новая папка'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'media':
        await _pickAndUpload(media: true);
      case 'files':
        await _pickAndUpload(media: false);
      case 'folder':
        await _createFolder();
    }
  }

  void _setTask(_DiskTask? task) {
    if (mounted) setState(() => _task = task);
  }

  Future<void> _pickAndUpload({required bool media}) async {
    if (_task != null) return;
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: media ? FileType.media : FileType.any,
        allowMultiple: true,
        // Файлы не пережимаем: на «Диске» нужен оригинал. На iOS фото
        // из галереи при этом всё равно приходят в совместимом JPEG.
        compressionQuality: 0,
      );
    } catch (e) {
      _showError('Не удалось выбрать файлы', e);
      return;
    }
    var files = result?.files.where((f) => f.path != null).toList() ?? [];
    if (files.isEmpty || !mounted) return;

    // Сервер не принимает файлы больше лимита — не тратим трафик на заведомо
    // неудачную загрузку.
    final tooBig = files
        .where((f) => f.size > DiskRepository.maxUploadBytes)
        .map((f) => f.name)
        .toList();
    if (tooBig.isNotEmpty) {
      _showMessage(
        'Больше ${formatFileSize(DiskRepository.maxUploadBytes)} не '
        'загрузить: ${tooBig.join(', ')}',
      );
      files = files
          .where((f) => f.size <= DiskRepository.maxUploadBytes)
          .toList();
      if (files.isEmpty) return;
    }

    // Файл с тем же именем сервер молча перезаписывает — спрашиваем заранее.
    final existing = {
      for (final f in _listing?.files ?? const <DiskFile>[])
        f.name.toLowerCase(),
    };
    final clashes = files
        .where((f) => existing.contains(f.name.toLowerCase()))
        .map((f) => f.name)
        .toList();
    if (clashes.isNotEmpty) {
      final choice = await _confirmReplace(
        clashes,
        canSkip: clashes.length < files.length,
      );
      if (choice == null || !mounted) return;
      if (!choice) {
        files = files
            .where((f) => !existing.contains(f.name.toLowerCase()))
            .toList();
      }
    }

    final failed = <String>[];
    String? lastError;
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final label = files.length == 1
          ? 'Загрузка «${file.name}»'
          : 'Загрузка ${i + 1} из ${files.length}';
      _setTask(_DiskTask(label, 0));
      var shown = 0.0;
      try {
        await DiskRepository.instance.uploadFile(
          filePath: file.path!,
          filename: file.name,
          folder: _currentPath,
          onProgress: (progress) {
            // Перерисовка на каждый кусок тела не нужна — по процентам.
            if (progress - shown < 0.01 && progress < 1) return;
            shown = progress;
            _setTask(_DiskTask(label, progress));
          },
        );
      } catch (e) {
        failed.add(file.name);
        lastError = e is ApiException ? e.message : null;
      }
    }
    _setTask(null);
    if (!mounted) return;
    await _load(silent: true);
    if (!mounted || failed.isEmpty) return;
    _showMessage(
      files.length == 1
          ? (lastError ?? 'Не удалось загрузить файл')
          : 'Не загружено ${failed.length} из ${files.length}: '
                '${failed.join(', ')}',
    );
  }

  /// `true` — заменить, `false` — загрузить только новые, `null` — отмена.
  Future<bool?> _confirmReplace(List<String> names, {required bool canSkip}) {
    final single = names.length == 1;
    return showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(single ? 'Заменить файл?' : 'Заменить файлы?'),
        content: Text(
          single
              ? '«${names.first}» уже есть в этой папке и будет заменён.'
              : 'Эти файлы уже есть в папке и будут заменены: '
                    '${names.join(', ')}.',
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Заменить'),
          ),
          if (canSkip)
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Только новые'),
            ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Удаление
  // ---------------------------------------------------------------------

  Future<void> _deleteFolder(DiskFolder folder) async {
    final confirmed = await _confirmDelete(
      title: 'Удалить папку?',
      message:
          'Папка «${folder.name}» и всё её содержимое будут удалены без '
          'возможности восстановления.',
    );
    if (confirmed != true) return;
    await _runBusy(
      () => DiskRepository.instance.deleteFolder(folder.path),
      'Не удалось удалить папку',
    );
  }

  Future<void> _deleteFile(DiskFile file) async {
    final confirmed = await _confirmDelete(
      title: 'Удалить файл?',
      message: '«${file.name}» будет удалён без возможности восстановления.',
    );
    if (confirmed != true) return;
    await _runBusy(
      () => DiskRepository.instance.deleteFile(file.path),
      'Не удалось удалить файл',
    );
  }

  Future<void> _runBusy(Future<void> Function() action, String fallback) async {
    setState(() => _isBusy = true);
    try {
      await action();
      if (!mounted) return;
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      _showError(fallback, e);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<bool?> _confirmDelete({
    required String title,
    required String message,
  }) {
    return showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
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

  // ---------------------------------------------------------------------
  // Открытие, отправка, сохранение
  // ---------------------------------------------------------------------

  /// Локальная копия файла с прогрессом в капсуле; `null` — не удалось.
  Future<File?> _fetchWithProgress(DiskFile file, String verb) async {
    if (_task != null) return null;
    final label = '$verb «${file.name}»';
    _setTask(_DiskTask(label));
    var shown = 0.0;
    try {
      return await DiskRepository.instance.fetchFile(
        file,
        onProgress: (progress) {
          if (progress - shown < 0.01 && progress < 1) return;
          shown = progress;
          _setTask(_DiskTask(label, progress));
        },
      );
    } catch (e) {
      if (mounted) _showError('Не удалось скачать файл', e);
      return null;
    } finally {
      _setTask(null);
    }
  }

  Future<void> _openFile(DiskFile file) async {
    if (file.isImage) {
      await Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (context) => _DiskImagePreviewScreen(file: file),
        ),
      );
      return;
    }
    final local = await _fetchWithProgress(file, 'Открытие');
    if (local == null || !mounted) return;
    await _openLocalFile(local, onError: _showMessage);
  }

  Future<void> _shareFile(DiskFile file, Rect? origin) async {
    final local = await _fetchWithProgress(file, 'Подготовка');
    if (local == null || !mounted) return;
    await _shareDiskFile(local, file, origin);
  }

  Future<void> _saveToDevice(DiskFile file) async {
    final local = await _fetchWithProgress(file, 'Скачивание');
    if (local == null || !mounted) return;
    try {
      await FilePicker.platform.saveFile(
        fileName: file.name,
        bytes: await local.readAsBytes(),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Не удалось сохранить файл', e);
    }
  }

  Future<void> _showFolderActions(DiskFolder folder) async {
    AppHaptics.medium();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(folder.name),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _openFolder(folder);
            },
            child: const Text('Открыть'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              _deleteFolder(folder);
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

  Future<void> _showFileActions(DiskFile file, BuildContext rowContext) async {
    AppHaptics.medium();
    // Окно «Поделиться» на iPad привязывается к строке.
    final box = rowContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(file.name),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _openFile(file);
            },
            child: const Text('Открыть'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _shareFile(file, origin);
            },
            child: const Text('Отправить…'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _saveToDevice(file);
            },
            child: const Text('Сохранить на устройство'),
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

  // ---------------------------------------------------------------------
  // Вёрстка
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final task = _task;
    return AppGlassBarBlur(
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: AppColors.groupedBackground.resolveFrom(context),
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: '.SF Pro Text',
            decoration: TextDecoration.none,
            color: label,
            fontSize: 16,
          ),
          child: Stack(
            children: [
              const AppGlassGlow(),
              SafeArea(
                top: false,
                bottom: false,
                child: RefreshIndicator.adaptive(
                  onRefresh: AppHaptics.onRefresh(() => _load(silent: true)),
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      _buildNavBar(context, blur: blur),
                      if (_crumbs.isNotEmpty)
                        SliverToBoxAdapter(child: _buildBreadcrumb(context)),
                      _buildContentSliver(),
                      // Последняя строка не должна прятаться под панелью.
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height:
                              MailFloatingBar.reservedHeight(context) +
                              (task != null ? _DiskTaskCapsule.height + 8 : 0),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (task != null) _DiskTaskCapsule(task: task),
                    _DiskBottomBar(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      onAdd: _task == null && !_isBusy ? _showAddMenu : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavBar(BuildContext context, {required bool blur}) {
    final label = CupertinoColors.label.resolveFrom(context);
    return AppSliverTitleBar(
      title: Text(_displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
      blur: blur,
      leading: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: () => Navigator.maybePop(context),
        child: Icon(
          CupertinoIcons.back,
          size: AppSliverTitleBar.iconSize,
          color: label,
        ),
      ),
      trailing: _isBusy
          ? const CupertinoActivityIndicator()
          : CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: _showSortMenu,
              child: Icon(
                CupertinoIcons.arrow_up_arrow_down,
                size: AppSliverTitleBar.iconSize,
                color: label,
              ),
            ),
    );
  }

  /// Путь до текущей папки: предки — стеклянными капсулами, по нажатию
  /// возвращают на свой уровень; сама текущая папка уже в заголовке.
  Widget _buildBreadcrumb(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final crumbs = _crumbs;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
        itemCount: crumbs.length,
        separatorBuilder: (context, index) => Icon(
          CupertinoIcons.chevron_forward,
          size: 12,
          color: CupertinoColors.tertiaryLabel.resolveFrom(context),
        ),
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AppGlass(
              borderRadius: BorderRadius.circular(16),
              shadows: AppGlass.controlShadow,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: Size.zero,
                onPressed: () => _openCrumb(index),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (index == 0) ...[
                      Icon(CupertinoIcons.cloud, size: 15, color: label),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      crumbs[index].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: label,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContentSliver() {
    if (_isLoading) {
      return AppGlassSliverList(
        itemCount: 8,
        itemBuilder: (context, index) => const AppSkeletonListTile(),
      );
    }

    if (_errorMessage != null) {
      return SliverAppEmptyState(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: _errorMessage!,
        onRetry: _load,
      );
    }

    final listing = _listing;
    if (listing == null || listing.isEmpty) {
      return SliverAppEmptyState(
        icon: CupertinoIcons.folder,
        message: 'Здесь пока пусто',
        onRetry: _task == null && !_isBusy ? _showAddMenu : null,
        retryLabel: 'Добавить',
      );
    }

    final folders = _visibleFolders(listing);
    final files = _visibleFiles(listing);
    final rowCount = folders.length + files.length;
    if (rowCount == 0) {
      return SliverAppEmptyState(
        icon: CupertinoIcons.search,
        message: 'В этой папке ничего не нашлось по запросу «${_query.trim()}»',
      );
    }

    return AppGlassSliverList(
      separatorIndent: _DiskRow.separatorIndent,
      itemCount: rowCount,
      itemBuilder: (context, index) {
        // Свайп рисует красную полосу под строкой — у крайних строк она
        // должна повторять скругление карточки, а не торчать углом.
        const corner = Radius.circular(21);
        final radius = BorderRadius.vertical(
          top: index == 0 ? corner : Radius.zero,
          bottom: index == rowCount - 1 ? corner : Radius.zero,
        );

        if (index < folders.length) {
          final folder = folders[index];
          return SwipeActionsRow(
            id: 'folder:${folder.path}',
            groupController: _swipeGroup,
            borderRadius: radius,
            actions: [
              SwipeAction(
                icon: CupertinoIcons.delete,
                label: 'Удалить',
                color: CupertinoColors.destructiveRed.resolveFrom(context),
                onTap: () => _deleteFolder(folder),
              ),
            ],
            child: _DiskFolderTile(
              folder: folder,
              onTap: () => _openFolder(folder),
              onLongPress: () => _showFolderActions(folder),
            ),
          );
        }

        final file = files[index - folders.length];
        final highlighted = file.name == _highlighted;
        final row = SwipeActionsRow(
          id: 'file:${file.path}',
          groupController: _swipeGroup,
          borderRadius: radius,
          actions: [
            SwipeAction(
              icon: CupertinoIcons.delete,
              label: 'Удалить',
              color: CupertinoColors.destructiveRed.resolveFrom(context),
              onTap: () => _deleteFile(file),
            ),
          ],
          child: Builder(
            builder: (rowContext) => _DiskFileTile(
              file: file,
              highlighted: highlighted,
              onTap: () => _openFile(file),
              onLongPress: () => _showFileActions(file, rowContext),
            ),
          ),
        );
        return file.name == widget.highlightName
            ? KeyedSubtree(key: _highlightKey, child: row)
            : row;
      },
    );
  }
}

/// Открывает скачанный файл системным просмотром (QuickLook на iOS,
/// подходящее приложение на Android).
Future<void> _openLocalFile(
  File local, {
  required void Function(String message) onError,
}) async {
  final result = await OpenFilex.open(local.path);
  switch (result.type) {
    case ResultType.done:
      return;
    case ResultType.noAppToOpen:
      onError('Нет приложения, которое может открыть этот файл');
    default:
      onError('Не удалось открыть файл');
  }
}

/// Системное окно «Поделиться» для скачанного файла.
Future<void> _shareDiskFile(File local, DiskFile file, Rect? origin) {
  return SharePlus.instance.share(
    ShareParams(
      files: [XFile(local.path, mimeType: file.mime, name: file.name)],
      sharePositionOrigin: origin,
    ),
  );
}

/// Нижняя стеклянная панель: поиск по текущей папке и «добавить», как
/// поиск и «написать» в «Почте».
class _DiskBottomBar extends StatelessWidget {
  const _DiskBottomBar({
    required this.controller,
    required this.onChanged,
    required this.onAdd,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return MailFloatingBar(
      child: Row(
        children: [
          Expanded(
            child: AppGlass(
              borderRadius: BorderRadius.circular(MailFloatingBar.height / 2),
              shadows: AppGlass.controlShadow,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: CupertinoSearchTextField(
                    controller: controller,
                    placeholder: 'Поиск в папке',
                    backgroundColor: Colors.transparent,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          MailGlassIconButton(icon: CupertinoIcons.plus, onPressed: onAdd),
        ],
      ),
    );
  }
}

/// Капсула с подписью и полосой прогресса над нижней панелью.
class _DiskTaskCapsule extends StatelessWidget {
  const _DiskTaskCapsule({required this.task});

  static const double height = 44;

  final _DiskTask task;

  @override
  Widget build(BuildContext context) {
    final progress = task.progress;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: AppGlass(
        borderRadius: BorderRadius.circular(height / 2),
        shadows: AppGlass.controlShadow,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const CupertinoActivityIndicator(radius: 8),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: SizedBox(
                            height: 3,
                            child: Stack(
                              children: [
                                Container(
                                  color: secondary.withValues(alpha: 0.2),
                                ),
                                FractionallySizedBox(
                                  widthFactor: progress.clamp(0, 1),
                                  child: Container(color: AppColors.primary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (progress != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    '${(progress * 100).round()}%',
                    style: TextStyle(fontSize: 13, color: secondary),
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

class _DiskFolderTile extends StatelessWidget {
  const _DiskFolderTile({
    required this.folder,
    required this.onTap,
    required this.onLongPress,
  });

  final DiskFolder folder;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return _DiskRow(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: _DiskIconBadge(
        icon: CupertinoIcons.folder_fill,
        color: CupertinoColors.systemBlue.resolveFrom(context),
      ),
      title: folder.name,
      subtitle: folder.isShared ? 'Есть доступ у других' : null,
      trailing: Icon(
        CupertinoIcons.chevron_forward,
        size: 16,
        color: CupertinoColors.tertiaryLabel.resolveFrom(context),
      ),
    );
  }
}

class _DiskFileTile extends StatelessWidget {
  const _DiskFileTile({
    required this.file,
    required this.onTap,
    required this.onLongPress,
    this.highlighted = false,
  });

  final DiskFile file;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool highlighted;

  String? get _subtitle {
    final parts = <String>[
      if (file.size != null) formatFileSize(file.size!),
      if (file.lastModified != null)
        DateFormat(
          'd MMM, HH:mm',
          'ru_RU',
        ).format(file.lastModified!.toLocal()),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return _DiskRow(
      onTap: onTap,
      onLongPress: onLongPress,
      highlighted: highlighted,
      leading: file.isImage
          ? _DiskThumbnail(file: file)
          : _DiskFormatBadge(file: file),
      title: file.name,
      subtitle: _subtitle,
      trailing: file.isShared
          ? Icon(
              CupertinoIcons.person_2_fill,
              size: 16,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
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
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

/// Миниатюры качаются по две за раз: на длинном списке фотографий иначе
/// десятки скачиваний разом забили бы канал и задержали открытие файла.
abstract final class _ThumbnailLoader {
  static const _maxParallel = 2;

  /// Крупнее — не качаем ради миниатюры: это уже трафик, а не превью.
  static const maxSize = 10 * 1024 * 1024;

  static int _active = 0;
  static final _waiting = Queue<Completer<void>>();

  static Future<File?> load(DiskFile file, bool Function() isWanted) async {
    if (_active < _maxParallel) {
      _active++;
    } else {
      final slot = Completer<void>();
      _waiting.add(slot);
      await slot.future;
    }
    try {
      // Строку успели пролистать, пока ждали очереди.
      if (!isWanted()) return null;
      return await DiskRepository.instance.fetchFile(file);
    } catch (_) {
      return null;
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }
}

/// Миниатюра картинки вместо значка формата; пока не скачана или если
/// формат не читается — обычный [_DiskFormatBadge].
class _DiskThumbnail extends StatefulWidget {
  const _DiskThumbnail({required this.file});

  final DiskFile file;

  @override
  State<_DiskThumbnail> createState() => _DiskThumbnailState();
}

class _DiskThumbnailState extends State<_DiskThumbnail> {
  File? _local;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final file = widget.file;
    final cached = await DiskRepository.instance.cachedFile(file);
    if (!mounted) return;
    if (cached != null) {
      setState(() => _local = cached);
      return;
    }
    final size = file.size;
    if (size == null || size > _ThumbnailLoader.maxSize) return;
    final local = await _ThumbnailLoader.load(file, () => mounted);
    if (mounted && local != null) setState(() => _local = local);
  }

  @override
  Widget build(BuildContext context) {
    final local = _local;
    final badge = _DiskFormatBadge(file: widget.file);
    if (local == null) return badge;
    final pixels = (36 * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        local,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        cacheWidth: pixels,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => badge,
      ),
    );
  }
}

/// Иконка файла в стиле Files на iPhone: «страница» с цветным лейблом
/// формата снизу.
class _DiskFormatBadge extends StatelessWidget {
  const _DiskFormatBadge({required this.file});

  final DiskFile file;

  String get _extension {
    final dot = file.name.lastIndexOf('.');
    if (dot <= 0 || dot == file.name.length - 1) return '';
    final ext = file.name.substring(dot + 1).toUpperCase();
    return ext.length > 4 ? ext.substring(0, 4) : ext;
  }

  Color _colorOf(BuildContext context) {
    return CupertinoDynamicColor.resolve(_baseColor, context);
  }

  Color get _baseColor {
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
    if (const ['xls', 'xlsx', 'csv'].contains(ext)) {
      return CupertinoColors.systemGreen;
    }
    if (const ['doc', 'docx'].contains(ext)) return CupertinoColors.systemBlue;
    if (const ['ppt', 'pptx'].contains(ext)) {
      return CupertinoColors.systemOrange;
    }
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
          Icon(
            CupertinoIcons.doc_fill,
            size: 34,
            color: CupertinoColors.systemGrey4.resolveFrom(context),
          ),
          if (extension.isNotEmpty)
            Positioned(
              bottom: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: _colorOf(context),
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

/// Строка папки или файла на стеклянной карточке: прозрачная, фон даёт
/// [AppGlassSliverList], между строками — разделитель с отступом.
class _DiskRow extends StatelessWidget {
  const _DiskRow({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
    required this.onLongPress,
    this.highlighted = false,
  });

  /// Отступ разделителя: поле 16 + иконка 36 + зазор 12.
  static const double separatorIndent = 64;

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Короткая подсветка строки, к которой привёл поиск.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        color: highlighted
            ? AppColors.primary.withValues(alpha: 0.14)
            : AppColors.primary.withValues(alpha: 0),
        padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
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
  final _shareButtonKey = GlobalKey();
  File? _local;
  double? _progress;
  bool _isLoading = true;
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
      final local = await DiskRepository.instance.fetchFile(
        widget.file,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _local = local;
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

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _share() async {
    final local = _local;
    if (local == null) return;
    final box =
        _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    await _shareDiskFile(local, widget.file, origin);
  }

  /// Формат, который Flutter не декодирует (например, редкий RAW), —
  /// показываем системным просмотром.
  Widget _buildUnsupportedFormat() {
    return AppEmptyState(
      icon: CupertinoIcons.photo,
      message: 'Этот формат изображения нельзя посмотреть здесь',
      onRetry: _local == null
          ? null
          : () => _openLocalFile(_local!, onError: _showMessage),
      retryLabel: 'Открыть',
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = _local;
    final progress = _progress;
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          widget.file.name,
          style: const TextStyle(color: CupertinoColors.white),
        ),
        backgroundColor: CupertinoColors.black,
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: () => Navigator.maybePop(context),
          child: const Icon(
            CupertinoIcons.back,
            size: 26,
            color: CupertinoColors.white,
          ),
        ),
        trailing: CupertinoButton(
          key: _shareButtonKey,
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: local == null ? null : _share,
          child: const Icon(
            CupertinoIcons.square_arrow_up,
            color: CupertinoColors.white,
          ),
        ),
      ),
      child: SafeArea(
        child: Center(
          child: _isLoading
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CupertinoActivityIndicator(
                      color: CupertinoColors.white,
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${(progress * 100).round()}%',
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.systemGrey.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ],
                  ],
                )
              : _errorMessage != null
              ? AppEmptyState(
                  icon: CupertinoIcons.exclamationmark_triangle,
                  message: _errorMessage!,
                  onRetry: _load,
                )
              : InteractiveViewer(
                  maxScale: 5,
                  child: Image.file(
                    local!,
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
