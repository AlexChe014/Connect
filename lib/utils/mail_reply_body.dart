import 'dart:convert' show htmlEscape;

import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';

import '../models/mail/mail_message.dart';

/// Тело ответа: новый текст, разделитель с данными исходного письма и
/// цитата. HTML-версия нужна, чтобы получатель видел границу между
/// сообщениями и исходное письмо с его оформлением; текстовая — для
/// почтовых программ без HTML.
class MailReplyBody {
  final String text;

  /// `null`, если цитировать нечего: письмо уходит обычным текстом.
  final String? html;

  const MailReplyBody({required this.text, this.html});

  static const _separator = 'Исходное сообщение';

  factory MailReplyBody.build({
    required String userText,
    required MailMessage original,
  }) {
    final reply = userText.trim();
    final plainQuote = original.previewBody;
    final htmlQuote = _quotedHtml(original);
    if (plainQuote.isEmpty && htmlQuote.isEmpty) {
      return MailReplyBody(text: reply);
    }

    final details = _details(original);
    final plainDetails = details.map((d) => '${d.$1}: ${d.$2}').join('\n');
    final htmlDetails = details
        .map((d) => '<b>${d.$1}:</b> ${_escape(d.$2)}')
        .join('<br>');

    return MailReplyBody(
      text: [
        if (reply.isNotEmpty) reply,
        '-----$_separator-----\n$plainDetails',
        plainQuote,
      ].join('\n\n'),
      html:
          '<div>${_escape(reply)}</div>'
          '<hr style="margin:20px 0;border:none;border-top:1px solid #cccccc;">'
          '<div style="font-size:13px;color:#555555;margin-bottom:12px;">'
          '<b>$_separator</b><br>$htmlDetails</div>'
          '<blockquote style="margin:0;padding:0 0 0 12px;'
          'border-left:2px solid #cccccc;">$htmlQuote</blockquote>',
    );
  }

  static List<(String, String)> _details(MailMessage original) {
    final date = original.date;
    return [
      if (original.from.isNotEmpty) ('От', original.from),
      if (date != null)
        (
          'Дата',
          DateFormat('d MMMM yyyy, HH:mm', 'ru_RU').format(date.toLocal()),
        ),
      if (original.to?.isNotEmpty ?? false) ('Кому', original.to!),
      if (original.cc?.isNotEmpty ?? false) ('Копия', original.cc!),
      if (original.subject.isNotEmpty) ('Тема', original.subject),
    ];
  }

  /// Содержимое `<body>` исходного письма. Скрипты и стили из него не
  /// берём (`<style>` действовал бы и на новый текст), а картинки `cid:` —
  /// это вложения исходного письма, в ответе они были бы битыми.
  static String _quotedHtml(MailMessage original) {
    final html = original.htmlContent;
    if (html == null) return _escape(original.previewBody);
    final document = html_parser.parse(html);
    document
        .querySelectorAll('script, style, link, meta, title')
        .forEach((element) => element.remove());
    for (final image in document.querySelectorAll('img')) {
      final src = image.attributes['src']?.trim().toLowerCase() ?? '';
      if (src.startsWith('cid:')) image.remove();
    }
    final content = document.body?.innerHtml.trim() ?? '';
    return content.isNotEmpty ? content : _escape(original.previewBody);
  }

  static String _escape(String value) =>
      htmlEscape.convert(value).replaceAll('\n', '<br>');
}
