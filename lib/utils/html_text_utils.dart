import 'package:html/parser.dart' as html_parser;

/// Утилиты для HTML-текста сообщений (чат, превью).
class HtmlTextUtils {
  HtmlTextUtils._();

  static bool looksLikeHtml(String value) {
    final trimmed = value.trimLeft();
    if (trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<!doctype')) {
      return true;
    }
    return RegExp(
      r'<\s*\/?[a-zA-Z][^>]*>',
      caseSensitive: false,
    ).hasMatch(value);
  }

  /// HTML → текст с сохранёнными переносами строк (абзацы, `<br>`, пункты
  /// списков) — для копирования и правки сообщения в поле ввода, где
  /// [toPlainText] склеил бы абзацы портала в одну строку.
  static String toMultilineText(String html) {
    final trimmed = html.trim();
    if (trimmed.isEmpty) return '';
    if (!looksLikeHtml(trimmed)) return decodeEntities(trimmed);

    // Переносы в исходнике HTML — просто пробелы; строки задают теги.
    final withBreaks = trimmed
        .replaceAll(RegExp(r'\s*\n\s*'), ' ')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(p|div|tr|li|h[1-6]|blockquote)>', caseSensitive: false),
          '\n',
        );
    String text;
    try {
      final document = html_parser.parse(withBreaks);
      text = document.body?.text ?? document.documentElement?.text ?? '';
    } catch (_) {
      text = decodeEntities(withBreaks.replaceAll(RegExp(r'<[^>]*>'), ''));
    }
    return _normalizeWhitespace(text.replaceAll(' ', ' '));
  }

  /// HTML → однострочный/многострочный plain text для превью и сниппетов.
  static String toPlainText(String html) {
    final trimmed = html.trim();
    if (trimmed.isEmpty) return '';
    if (!looksLikeHtml(trimmed)) return decodeEntities(trimmed);

    try {
      final document = html_parser.parse(trimmed);
      final extracted = document.body?.text ?? document.documentElement?.text;
      if (extracted != null) {
        final normalized = _normalizeWhitespace(extracted);
        if (normalized.isNotEmpty) return normalized;
      }
    } catch (_) {}

    var text = trimmed
        .replaceAll(RegExp(r'<(br|BR)\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(p|div|tr|li|h[1-6]|blockquote)>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]*>'), ' ');
    return _normalizeWhitespace(decodeEntities(text));
  }

  /// Пустой абзац, которым веб-редактор (Quill) отмечает пустую строку:
  /// `<p><br></p>`, `<p>&nbsp;</p>`.
  static final _emptyParagraph = RegExp(
    r'<p(?:\s[^>]*)?>(?:\s|&nbsp;|&#160;| |<br\s*/?>)*</p>',
    caseSensitive: false,
  );

  /// Хвост абзаца из `<br>` и неразрывных пробелов перед `</p>`.
  static final _paragraphTail = RegExp(
    r'(?:\s|&nbsp;|&#160;| |<br\s*/?>)+(?=</p>)',
    caseSensitive: false,
  );

  /// HTML поста для показа: без пустых абзацев. flutter_html рисует
  /// `<p><br></p>` в две строки и добавляет отступы абзаца — между
  /// абзацами выходило три пустые строки. Расстояние между абзацами
  /// задаёт стиль `p`.
  static String compactParagraphs(String html) {
    return html
        .replaceAll(_emptyParagraph, '')
        .replaceAll(_paragraphTail, '')
        .trim();
  }

  /// HTML → текст с переносом между абзацами — для превью поста.
  /// [toPlainText] склеивает `<p>А</p><p>Б</p>` в «АБ».
  static String toParagraphText(String html) {
    final trimmed = html.trim();
    if (!looksLikeHtml(trimmed)) return decodeEntities(trimmed);
    final withBreaks = compactParagraphs(trimmed)
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(p|div|li|h[1-6]|blockquote)>', caseSensitive: false),
          '\n',
        );
    String text;
    try {
      text = html_parser.parse(withBreaks).body?.text ?? '';
    } catch (_) {
      text = decodeEntities(withBreaks.replaceAll(RegExp(r'<[^>]*>'), ''));
    }
    return text
        .replaceAll(' ', ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
  }

  static String decodeEntities(String value) {
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }

  static String _normalizeWhitespace(String value) {
    return value
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
