import 'package:connect/utils/connector_link_join.dart';
import 'package:connect/utils/connector_url_utils.dart';
import 'package:connect/utils/html_text_utils.dart';
import 'package:connect/utils/open_link.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

final _urlRegExp = RegExp(r'(https?:\/\/[^\s<>"\)]+)', caseSensitive: false);

/// Текст сообщения чата: plain text / HTML; URL кликабельны.
class ChatMessageText extends StatefulWidget {
  const ChatMessageText({
    super.key,
    required this.text,
    this.color,
    this.fontSize = 15,
    this.maxLines,
    this.overflow,
    this.paragraphSpacing = 6,
    this.mentions = const {},
    this.onMentionTap,
  });

  final String text;
  final Color? color;
  final double fontSize;
  final int? maxLines;
  final TextOverflow? overflow;

  /// Отступ после абзаца `<p>` в HTML-тексте.
  final double paragraphSpacing;

  /// Имя участника → id: `@имя` в тексте выделяется, тап — [onMentionTap].
  final Map<String, int> mentions;
  final ValueChanged<int>? onMentionTap;

  @override
  State<ChatMessageText> createState() => _ChatMessageTextState();
}

class _ChatMessageTextState extends State<ChatMessageText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _openUrl(String raw) async {
    final url = raw.replaceAll(RegExp(r'[.,;:!?)]+$'), '');
    // Ссылка ВКС — как в календаре и брони: вход в приложении, при
    // ошибке — причина, а не молчаливый переход в браузер.
    if (connectorRoomFromUrl(url) != null) {
      await joinMeetingLink(context, url);
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await openLink(uri);
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final trimmed = widget.text.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    final effectiveColor =
        widget.color ??
        DefaultTextStyle.of(context).style.color ??
        Colors.black;

    if (!HtmlTextUtils.looksLikeHtml(trimmed)) {
      if (widget.maxLines != null) {
        return Text(
          trimmed,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
          style: TextStyle(
            color: effectiveColor,
            fontSize: widget.fontSize,
            height: 1.35,
          ),
        );
      }
      return Text.rich(
        TextSpan(
          style: TextStyle(
            color: effectiveColor,
            fontSize: widget.fontSize,
            height: 1.35,
          ),
          children: _linkSpans(trimmed, effectiveColor),
        ),
      );
    }

    if (widget.maxLines != null) {
      return Text(
        HtmlTextUtils.toPlainText(trimmed),
        maxLines: widget.maxLines,
        overflow: widget.overflow ?? TextOverflow.ellipsis,
        style: TextStyle(
          color: effectiveColor,
          fontSize: widget.fontSize,
          height: 1.35,
        ),
      );
    }

    return Html(
      data: trimmed,
      onLinkTap: (url, attributes, element) {
        if (url != null && url.isNotEmpty) _openUrl(url);
      },
      style: {
        'body': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          color: effectiveColor,
          fontSize: FontSize(widget.fontSize),
          lineHeight: LineHeight.number(1.35),
        ),
        'p': Style(
          margin: Margins.only(bottom: widget.paragraphSpacing),
          padding: HtmlPaddings.zero,
        ),
        'div': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
        'a': Style(
          color: effectiveColor,
          textDecoration: TextDecoration.underline,
          textDecorationColor: effectiveColor.withValues(alpha: 0.7),
        ),
        'strong': Style(fontWeight: FontWeight.w700),
        'b': Style(fontWeight: FontWeight.w700),
        'em': Style(fontStyle: FontStyle.italic),
        'i': Style(fontStyle: FontStyle.italic),
      },
    );
  }

  /// Ссылки и `@упоминания` одним проходом; длинные имена — первыми,
  /// чтобы «@Анна Петрова» не обрезалось до «@Анна».
  RegExp _tokenRegExp() {
    if (widget.mentions.isEmpty) return _urlRegExp;
    final names = widget.mentions.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return RegExp(
      '${_urlRegExp.pattern}|@(${names.map(RegExp.escape).join('|')})',
      caseSensitive: false,
    );
  }

  int? _mentionUserId(String name) {
    final lower = name.toLowerCase();
    for (final e in widget.mentions.entries) {
      if (e.key.toLowerCase() == lower) return e.value;
    }
    return null;
  }

  List<InlineSpan> _linkSpans(String text, Color color) {
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in _tokenRegExp().allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      final mentioned = match.groupCount >= 2 ? match.group(2) : null;
      if (mentioned != null) {
        final userId = _mentionUserId(mentioned);
        TapGestureRecognizer? recognizer;
        final onTap = widget.onMentionTap;
        if (userId != null && onTap != null) {
          recognizer = TapGestureRecognizer()..onTap = () => onTap(userId);
          _recognizers.add(recognizer);
        }
        spans.add(
          TextSpan(
            text: match.group(0),
            style: const TextStyle(fontWeight: FontWeight.w600),
            recognizer: recognizer,
          ),
        );
        start = match.end;
        continue;
      }
      final url = match.group(0)!;
      final recognizer = TapGestureRecognizer()..onTap = () => _openUrl(url);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: url,
          style: TextStyle(
            color: color,
            decoration: TextDecoration.underline,
            decorationColor: color.withValues(alpha: 0.7),
          ),
          recognizer: recognizer,
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return spans;
  }
}
