import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;
import 'package:flutter/rendering.dart' show RenderProxyBox;

import '../config/app_theme.dart';
import '../models/documents/document_service.dart';
import '../repositories/documents_repository.dart';
import '../services/api_client.dart';
import '../services/crash_reporting_service.dart';
import '../utils/document_file_share.dart';
import '../utils/document_payload_utils.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/app_loading.dart';
import '../widgets/app_title_bar.dart';

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

  /// null — сервис не отдаёт согласующих (1С УХ отвечает ошибкой),
  /// пустой список — никто ещё не согласовал.
  List<Map<String, dynamic>>? _acceptors;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  final _commentController = TextEditingController();
  int? _downloadingFileIndex;
  double _actionBarHeight = 0;

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

      // Согласующих 1С отдаёт по guiddoc самого документа, а не по guid
      // задачи из списка (guidlist) — с ним приходит пустой список.
      final guidDoc = doc['guiddoc']?.toString().trim();
      List<Map<String, dynamic>>? acceptors;
      try {
        acceptors = await DocumentsRepository.instance.getAcceptors(
          serviceId: widget.service.id,
          guid: (guidDoc == null || guidDoc.isEmpty) ? widget.guid : guidDoc,
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
      // 1С отдаёт идентификатор файла в поле guidfile.
      final fileGuid =
          (file['guidfile'] ?? file['guid'] ?? file['fileguid'] ?? file['id'])
              ?.toString()
              .trim();
      if (fileGuid == null || fileGuid.isEmpty) {
        throw ApiException(200, 'У файла нет идентификатора');
      }
      final response = await DocumentsRepository.instance.getDocumentFile(
        serviceId: widget.service.id,
        guid: fileGuid,
      );
      await DocumentFileShare.share(
        response,
        fallbackName: file['namefile']?.toString() ?? 'Файл',
      );
    } catch (e, st) {
      CrashReportingService.recordNonFatal(
        e,
        st,
        reason: 'document_file_download',
      );
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
      ('comment', 'Комментарий'),
      ('title', 'Описание'),
      // Номер уже есть в шапке, срок и статус не нужны.
      ('author', 'Автор'),
      ('sum', 'Сумма'),
    ];

    final entries = <MapEntry<String, String>>[];
    for (final item in order) {
      final raw = document[item.$1];
      if (raw == null) continue;
      final value = raw.toString().trim();
      if (value.isEmpty) continue;
      // 1С иногда дублирует текст в title и comment — не показываем дважды.
      if (entries.any((e) => e.value == value)) continue;
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
    final groupedBg = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    final label = CupertinoColors.label.resolveFrom(context);
    final showActions = !_isLoading && _errorMessage == null;

    return AppGlassBarBlur(
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: groupedBg,
        navigationBar: AppTitleBar(
          blur: blur,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () => Navigator.pop(context),
            child: Icon(
              CupertinoIcons.back,
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
            fontSize: 15,
          ),
          child: Stack(
            children: [
              const AppGlassGlow(height: 360),
              // Свой context — под скаффолдом, где в MediaQuery уже учтена
              // высота полупрозрачной шапки.
              Builder(builder: _buildBody),
              if (showActions)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _MeasureSize(
                    onChange: (height) {
                      if (height != _actionBarHeight) {
                        setState(() => _actionBarHeight = height);
                      }
                    },
                    child: _buildActionBar(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Стеклянная панель снизу: комментарий и два решения.
  Widget _buildActionBar() {
    final actionLabel = widget.service.isSigningService
        ? 'Подписать'
        : 'Согласовать';
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: AppGlass(
          borderRadius: BorderRadius.circular(26),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoTextField(
                  controller: _commentController,
                  placeholder: 'Комментарий (необязательно)',
                  minLines: 1,
                  maxLines: 3,
                  enabled: !_isSubmitting,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0x1FFFFFFF)
                        : const Color(0x0F000000),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        borderRadius: BorderRadius.circular(20),
                        onPressed: _isSubmitting ? null : _reject,
                        child: Text(
                          'Отклонить',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: CupertinoColors.systemRed.resolveFrom(
                              context,
                            ),
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
                        onPressed: _isSubmitting ? null : _accept,
                        child: _isSubmitting
                            ? const CupertinoActivityIndicator(
                                color: CupertinoColors.white,
                              )
                            : Text(
                                actionLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: CupertinoColors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
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
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 8,
        // Высота панели действий меняется вместе с полем комментария,
        // поэтому список отступает от неё по замеру, а не на глаз.
        bottom: _actionBarHeight + 16,
      ),
      children: [
        _buildHeader(document),
        if (entries.isNotEmpty) ...[
          const AppGlassSectionLabel('Детали'),
          AppGlassSection(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final entry in entries)
                CupertinoListTile(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 14, 10),
                  title: Text(
                    entry.key,
                    style: TextStyle(fontSize: 13, color: secondary),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entry.value,
                      // CupertinoListTile форсирует subtitle в 1 строку с
                      // "…", если не переопределить maxLines явно.
                      maxLines: 20,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (sides.isNotEmpty) ...[
          const AppGlassSectionLabel('Стороны'),
          AppGlassSection(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final side in sides)
                CupertinoListTile(
                  leading: const AppIconBadge(
                    icon: CupertinoIcons.person_2_fill,
                    color: CupertinoColors.systemIndigo,
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
          const AppGlassSectionLabel('Файлы'),
          AppGlassSection(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final entry in files.asMap().entries)
                CupertinoListTile(
                  leading: const AppIconBadge(
                    icon: CupertinoIcons.paperclip,
                    color: CupertinoColors.systemGrey,
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
        if (_acceptors != null) ...[
          const AppGlassSectionLabel('Кем согласовано'),
          AppGlassSection(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              if (_acceptors!.isEmpty)
                CupertinoListTile(
                  title: Text(
                    'Пока никто не согласовал',
                    style: TextStyle(color: secondary),
                  ),
                ),
              for (final acceptor in _acceptors!)
                CupertinoListTile(
                  leading: const AppIconBadge(
                    icon: CupertinoIcons.checkmark_seal_fill,
                    color: CupertinoColors.systemGreen,
                  ),
                  title: Text(DocumentPayloadUtils.labelForAcceptor(acceptor)),
                  subtitle: () {
                    final details = [
                      DocumentPayloadUtils.acceptorStatus(acceptor),
                      DocumentPayloadUtils.acceptorDate(acceptor),
                      DocumentPayloadUtils.acceptorComment(acceptor),
                    ].whereType<String>().join(' · ');
                    return details.isEmpty
                        ? null
                        : Text(
                            details,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          );
                  }(),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// Шапка карточки: крупный значок и название документа на стекле.
  Widget _buildHeader(Map<String, dynamic> document) {
    final number = DocumentPayloadUtils.number(document)?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppGlass(
        borderRadius: BorderRadius.circular(22),
        shadows: AppGlass.controlShadow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIconBadge(
                    icon: widget.service.isSigningService
                        ? CupertinoIcons.pencil
                        : CupertinoIcons.checkmark_seal_fill,
                    color: widget.service.isSigningService
                        ? CupertinoColors.systemBlue
                        : CupertinoColors.systemGreen,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      [
                        widget.service.displayName,
                        if (number != null && number.isNotEmpty) '№ $number',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                DocumentPayloadUtils.datalist(document) ??
                    DocumentPayloadUtils.title(document),
                style: TextStyle(
                  fontSize: 17,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Сообщает высоту ребёнка после каждой раскладки — по ней список
/// отступает от плавающей панели действий.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<double> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasureSize render) {
    render.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<double> onChange;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _last) return;
    _last = height;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(height));
  }
}
