import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart'
    show ScaffoldMessenger, SelectableText, SnackBar;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import '../models/mail/mail_connection.dart';
import '../models/mail/mail_folder.dart';
import '../models/mail/mail_message.dart';
import '../repositories/mail_repository.dart';
import '../services/crash_reporting_service.dart';
import '../services/mail_unread_service.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_title_bar.dart';
import '../widgets/home_shortcut_button.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/app_loading.dart';
import '../widgets/chat_avatar.dart';
import '../widgets/mail_body_content.dart';
import '../utils/file_size_format.dart';
import '../widgets/mail_glass.dart';
import 'compose_mail_screen.dart';

class MailMessageScreen extends StatefulWidget {
  const MailMessageScreen({
    super.key,
    required this.connection,
    required this.messageId,
    this.initialMessage,
    this.folders = const [],
    this.currentFolder,
    this.onMove,
  });

  final MailConnection connection;
  final int messageId;
  final MailMessage? initialMessage;
  final List<MailFolder> folders;

  /// Папка, из которой открыто письмо: её не предлагаем в «Переместить»,
  /// и по ней понятно, что письмо своё (Отправленные/Черновики).
  final MailFolder? currentFolder;

  /// Перемещение берёт на себя список: экран сразу закрывается, письмо
  /// пропадает из списка, а запрос идёт в фоне — сервер переносит письмо
  /// по IMAP несколько секунд, и раньше казалось, что ничего не происходит.
  final ValueChanged<MailFolder>? onMove;

  @override
  State<MailMessageScreen> createState() => _MailMessageScreenState();
}

class _MailMessageScreenState extends State<MailMessageScreen> {
  MailMessage? _message;
  bool _isLoading = true;
  bool _isDeleting = false;
  bool _showDetails = false;
  VoidCallback? _releaseHomeSuppress;

  @override
  void initState() {
    super.initState();
    // Плавающая кнопка «Домой» легла бы поверх «Удалить» в нижней панели.
    _releaseHomeSuppress = HomeShortcutButton.suppress();
    _loadMessage();
  }

  @override
  void dispose() {
    _releaseHomeSuppress?.call();
    super.dispose();
  }

  Future<void> _loadMessage() async {
    setState(() => _isLoading = true);
    try {
      final message = await MailRepository.instance.getMessage(
        connectionId: widget.connection.id,
        messageId: widget.messageId,
      );
      final initial = widget.initialMessage;
      var resolved = !message.hasBody && initial != null && initial.hasBody
          ? message.copyWith(
              subject: message.subject != '(без темы)'
                  ? message.subject
                  : initial.subject,
              from: message.from.isNotEmpty ? message.from : initial.from,
              to: message.to ?? initial.to,
              cc: message.cc ?? initial.cc,
              body: initial.body,
              bodyHtml: initial.bodyHtml,
              date: message.date ?? initial.date,
              hasAttachments: message.hasAttachments || initial.hasAttachments,
              attachments: message.attachments.isNotEmpty
                  ? message.attachments
                  : initial.attachments,
            )
          : message;

      if (!mounted) return;
      setState(() {
        _message = resolved;
        _isLoading = false;
      });

      // Открытие письма — это фактическое прочтение: getMessage() сам по себе
      // ничего не помечает на сервере, поэтому раньше письмо оставалось
      // непрочитанным (и точка-индикатор в списке не пропадала), пока
      // пользователь вручную не свайпал «прочитано». Помечаем в фоне, не
      // задерживая открытие письма вторым round-trip'ом.
      if (!resolved.isRead) {
        unawaited(_markReadInBackground(resolved));
      }
    } catch (_) {
      if (!mounted) return;
      final fallback = widget.initialMessage;
      setState(() {
        _message = fallback;
        _isLoading = false;
      });
      if (fallback == null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить письмо')),
        );
      } else if (fallback.htmlContent == null && fallback.plainBody.isEmpty) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Не удалось загрузить текст письма')),
        );
      }
    }
  }

  Future<void> _markReadInBackground(MailMessage current) async {
    try {
      await MailRepository.instance.markRead(
        connectionId: widget.connection.id,
        messageId: widget.messageId,
      );
      MailUnreadService.instance.invalidate();
      if (!mounted || _message == null || _message!.isRead) return;
      setState(() {
        _message = current.withRead(true);
      });
    } catch (_) {
      // Не удалось отметить прочитанным — письмо всё равно открыто,
      // просто точка-индикатор в списке останется до следующей попытки.
    }
  }

  Future<void> _deleteMessage() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Удалить письмо?'),
        content: const Text(
          'Письмо будет удалено без возможности восстановления.',
        ),
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
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await MailRepository.instance.deleteMessage(
        connectionId: widget.connection.id,
        messageId: widget.messageId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось удалить письмо')),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _moveToFolder() async {
    if (widget.folders.isEmpty) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Список папок пуст')));
      return;
    }

    // Раньше «текущей» в списке отмечалась просто первая папка, а папка,
    // где письмо уже лежит, предлагалась как цель перемещения.
    final current = widget.currentFolder;
    final options = widget.folders
        .where((f) => current == null || f.id != current.id)
        .toList();
    final folder = await showCupertinoModalPopup<MailFolder>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Переместить в папку'),
        message: current == null
            ? null
            : Text('Сейчас: ${current.displayName}'),
        actions: [
          for (final option in options)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, option),
              child: Text(option.displayName),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (folder == null || !mounted) return;

    final onMove = widget.onMove;
    if (onMove != null) {
      Navigator.of(context).pop();
      onMove(folder);
      return;
    }

    setState(() => _isDeleting = true);
    try {
      await MailRepository.instance.moveMessage(
        connectionId: widget.connection.id,
        messageId: widget.messageId,
        folderId: folder.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Письмо перемещено в «${folder.displayName}»')),
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось переместить письмо')),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _downloadAttachment(MailAttachment attachment) async {
    try {
      final bytes = await MailRepository.instance.downloadAttachment(
        connectionId: widget.connection.id,
        messageId: widget.messageId,
        filename: attachment.filename,
      );
      if (kIsWeb) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(bytes, name: attachment.filename)],
          ),
        );
        return;
      }
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/${attachment.filename}';
      await File(path).writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
    } catch (e, st) {
      CrashReportingService.recordNonFatal(
        e,
        st,
        reason: 'mail_attachment_download',
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Не удалось скачать вложение')),
      );
    }
  }

  Future<void> _reply({bool all = false}) async {
    final message = _message;
    if (message == null) return;
    final sent = await Navigator.of(context).push<bool>(
      CupertinoPageRoute<bool>(
        builder: (context) => ComposeMailScreen(
          connection: widget.connection,
          replyTo: message,
          replyAll: all,
        ),
      ),
    );
    if (sent == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _forward() async {
    final message = _message;
    if (message == null) return;
    final sent = await Navigator.of(context).push<bool>(
      CupertinoPageRoute<bool>(
        builder: (context) => ComposeMailScreen(
          connection: widget.connection,
          forwardOf: message,
        ),
      ),
    );
    if (sent == true && mounted) Navigator.of(context).pop(true);
  }

  bool _isOwn(String address) =>
      mailEmailOnly(address).toLowerCase() ==
      widget.connection.email.trim().toLowerCase();

  /// «Ерофеева Гулия, мне и ещё 2» — получатели одной строкой.
  String _recipientsSummary(MailMessage message) {
    final names = [
      ...MailMessage.splitAddresses(message.to),
      ...MailMessage.splitAddresses(message.cc),
    ].map((a) => _isOwn(a) ? 'мне' : mailDisplayName(a)).toList();
    if (names.isEmpty) return '';
    if (names.length <= 2) return names.join(', ');
    return '${names.take(2).join(', ')} и ещё ${names.length - 2}';
  }

  static String _shortDate(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return DateFormat('HH:mm', 'ru_RU').format(local);
    }
    final pattern = local.year == now.year ? 'd MMM, HH:mm' : 'd MMM yyyy';
    return DateFormat(pattern, 'ru_RU').format(local).replaceAll('.', '');
  }

  /// Шапка письма в две строки, как в «Почте» iOS: отправитель и дата,
  /// под ними получатели. Полные адреса — по нажатию.
  Widget _buildHeaderCard(BuildContext context, MailMessage message) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final senderName = mailDisplayName(message.from);
    final recipients = _recipientsSummary(message);
    final detailStyle = TextStyle(fontSize: 13, height: 1.35, color: label);

    Widget detail(String title, String value) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SelectableText.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$title: ',
              style: TextStyle(color: secondary),
            ),
            TextSpan(text: value),
          ],
        ),
        style: detailStyle,
      ),
    );

    return AppGlass(
      borderRadius: BorderRadius.circular(20),
      shadows: AppGlass.controlShadow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              message.subject,
              style: TextStyle(
                fontSize: 18,
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: label,
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showDetails = !_showDetails),
              child: Row(
                children: [
                  MemberAvatar(
                    displayName: senderName.isEmpty ? '?' : senderName,
                    radius: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                senderName.isEmpty
                                    ? 'Неизвестный отправитель'
                                    : senderName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: label,
                                ),
                              ),
                            ),
                            if (message.date != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                _shortDate(message.date!),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: secondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 1),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                recipients.isEmpty
                                    ? 'Подробнее'
                                    : 'Кому: $recipients',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: secondary,
                                ),
                              ),
                            ),
                            Icon(
                              _showDetails
                                  ? CupertinoIcons.chevron_up
                                  : CupertinoIcons.chevron_down,
                              size: 12,
                              color: secondary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_showDetails) ...[
              const SizedBox(height: 10),
              Container(
                height: 0.5,
                color: CupertinoColors.separator.resolveFrom(context),
              ),
              const SizedBox(height: 4),
              detail('От', message.from),
              if ((message.to ?? '').isNotEmpty) detail('Кому', message.to!),
              if ((message.cc ?? '').isNotEmpty) detail('Копия', message.cc!),
              if (message.date != null)
                detail(
                  'Дата',
                  DateFormat(
                    'd MMMM yyyy, HH:mm',
                    'ru_RU',
                  ).format(message.date!.toLocal()),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Вложения без картинок, уже показанных внутри текста письма.
  List<MailAttachment> _listedAttachments(MailMessage message) {
    final inline = MailBodyContent.inlineAttachments(message);
    return message.attachments.where((a) => !inline.contains(a)).toList();
  }

  Widget _buildAttachments(BuildContext context, MailMessage message) {
    final label = CupertinoColors.label.resolveFrom(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppGlassSectionLabel(
          'Вложения',
          padding: EdgeInsets.fromLTRB(4, 20, 4, 6),
        ),
        AppGlassSection(
          margin: EdgeInsets.zero,
          children: [
            for (final attachment in _listedAttachments(message))
              CupertinoListTile(
                leading: AppIconBadge(
                  icon: CupertinoIcons.doc_fill,
                  color: CupertinoColors.systemGrey.resolveFrom(context),
                ),
                title: Text(
                  attachment.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15),
                ),
                subtitle: attachment.size != null
                    ? Text(formatFileSize(attachment.size!))
                    : null,
                trailing: Icon(
                  CupertinoIcons.arrow_down_circle,
                  size: 22,
                  color: label,
                ),
                onTap: () => _downloadAttachment(attachment),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionBar() {
    return MailFloatingBar(
      child: AppGlass(
        borderRadius: BorderRadius.circular(MailFloatingBar.height / 2),
        shadows: AppGlass.controlShadow,
        // Под панелью обычно WebView письма, а платформенное представление
        // BackdropFilter не размывает — без плотной подложки текст письма
        // просвечивал сквозь подписи кнопок.
        child: ColoredBox(
          color: AppColors.screenBackground
              .resolveFrom(context)
              .withValues(alpha: 0.75),
          child: Row(
            children: [
              MailBarAction(
                icon: CupertinoIcons.trash,
                label: 'Удалить',
                isDestructive: true,
                onPressed: _isDeleting ? null : _deleteMessage,
              ),
              if (widget.folders.any((f) => f.id != widget.currentFolder?.id))
                MailBarAction(
                  icon: CupertinoIcons.folder,
                  label: 'Переместить',
                  onPressed: _isDeleting ? null : _moveToFolder,
                ),
              MailBarAction(
                icon: CupertinoIcons.reply,
                label: 'Ответить',
                onPressed: _isDeleting ? null : _reply,
              ),
              MailBarAction(
                icon: CupertinoIcons.reply_all,
                label: 'Ответить всем',
                onPressed: _isDeleting ? null : () => _reply(all: true),
              ),
              MailBarAction(
                icon: CupertinoIcons.arrowshape_turn_up_right,
                label: 'Переслать',
                onPressed: _isDeleting ? null : _forward,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    final groupedBg = AppColors.groupedBackground.resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);

    return AppGlassBarBlur(
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: groupedBg,
        navigationBar: AppTitleBar(
          blur: blur,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: () => Navigator.maybePop(context),
            child: Icon(
              CupertinoIcons.back,
              size: AppTitleBar.iconSize,
              color: label,
            ),
          ),
          trailing: _isDeleting ? const CupertinoActivityIndicator() : null,
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
              if (_isLoading)
                const SafeArea(child: AppPageLoader())
              else if (message == null)
                const SafeArea(
                  child: AppEmptyState(message: 'Письмо не найдено'),
                )
              else ...[
                Builder(
                  // Свой context — под скаффолдом, где в MediaQuery уже учтена
                  // высота полупрозрачной шапки.
                  builder: (context) => ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      MediaQuery.paddingOf(context).top + 8,
                      16,
                      MailFloatingBar.reservedHeight(context) + 8,
                    ),
                    children: [
                      _buildHeaderCard(context, message),
                      const SizedBox(height: 10),
                      AppFlatGlassCard(
                        // HTML-письмо сам WebView отбивает от краёв, лишний
                        // отступ карточки только отнимал у него ширину.
                        padding: MailBodyContent.rendersHtml(message)
                            ? EdgeInsets.zero
                            : const EdgeInsets.all(16),
                        child: MailBodyContent(
                          message: message,
                          loadAttachment: (attachment) =>
                              MailRepository.instance.downloadAttachment(
                                connectionId: widget.connection.id,
                                messageId: widget.messageId,
                                filename: attachment.filename,
                              ),
                        ),
                      ),
                      if (_listedAttachments(message).isNotEmpty)
                        _buildAttachments(context, message),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildActionBar(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
