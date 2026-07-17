import 'package:connect/utils/html_text_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

/// Текст сообщения чата: plain text или HTML-вёрстка с веб-сайта.
class ChatMessageText extends StatelessWidget {
  const ChatMessageText({
    super.key,
    required this.text,
    this.color,
    this.fontSize = 15,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final Color? color;
  final double fontSize;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    final effectiveColor =
        color ?? DefaultTextStyle.of(context).style.color ?? Colors.black;

    if (!HtmlTextUtils.looksLikeHtml(trimmed)) {
      return Text(
        trimmed,
        maxLines: maxLines,
        overflow: overflow,
        style: TextStyle(color: effectiveColor, fontSize: fontSize, height: 1.35),
      );
    }

    if (maxLines != null) {
      return Text(
        HtmlTextUtils.toPlainText(trimmed),
        maxLines: maxLines,
        overflow: overflow ?? TextOverflow.ellipsis,
        style: TextStyle(color: effectiveColor, fontSize: fontSize, height: 1.35),
      );
    }

    return Html(
      data: trimmed,
      style: {
        'body': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          color: effectiveColor,
          fontSize: FontSize(fontSize),
          lineHeight: LineHeight.number(1.35),
        ),
        'p': Style(
          margin: Margins.only(bottom: 6),
          padding: HtmlPaddings.zero,
        ),
        'div': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
        ),
        'h1': Style(
          fontSize: FontSize(fontSize + 4),
          fontWeight: FontWeight.w700,
          margin: Margins.only(bottom: 6),
          color: effectiveColor,
        ),
        'h2': Style(
          fontSize: FontSize(fontSize + 3),
          fontWeight: FontWeight.w700,
          margin: Margins.only(bottom: 6),
          color: effectiveColor,
        ),
        'h3': Style(
          fontSize: FontSize(fontSize + 2),
          fontWeight: FontWeight.w700,
          margin: Margins.only(bottom: 4),
          color: effectiveColor,
        ),
        'ul': Style(margin: Margins.only(left: 4, bottom: 4)),
        'ol': Style(margin: Margins.only(left: 4, bottom: 4)),
        'li': Style(margin: Margins.only(bottom: 2)),
        'blockquote': Style(
          margin: Margins.symmetric(vertical: 4),
          padding: HtmlPaddings.only(left: 8),
          border: Border(
            left: BorderSide(
              color: effectiveColor.withValues(alpha: 0.35),
              width: 3,
            ),
          ),
          fontStyle: FontStyle.italic,
        ),
        'a': Style(
          color: effectiveColor,
          textDecoration: TextDecoration.underline,
          textDecorationColor: effectiveColor.withValues(alpha: 0.7),
        ),
        'strong': Style(fontWeight: FontWeight.w700),
        'b': Style(fontWeight: FontWeight.w700),
        'em': Style(fontStyle: FontStyle.italic),
        'i': Style(fontStyle: FontStyle.italic),
        'u': Style(textDecoration: TextDecoration.underline),
        'code': Style(
          fontFamily: 'monospace',
          backgroundColor: effectiveColor.withValues(alpha: 0.12),
          padding: HtmlPaddings.symmetric(horizontal: 4, vertical: 1),
        ),
        'pre': Style(
          fontFamily: 'monospace',
          backgroundColor: effectiveColor.withValues(alpha: 0.10),
          padding: HtmlPaddings.all(8),
          margin: Margins.symmetric(vertical: 4),
          whiteSpace: WhiteSpace.pre,
        ),
        'img': Style(
          width: Width(220),
          margin: Margins.symmetric(vertical: 4),
        ),
        'table': Style(margin: Margins.symmetric(vertical: 4)),
        'td': Style(padding: HtmlPaddings.all(4)),
        'th': Style(
          padding: HtmlPaddings.all(4),
          fontWeight: FontWeight.w700,
        ),
      },
    );
  }
}
