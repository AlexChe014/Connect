import 'package:html/parser.dart' as html_parser;

/// Утилиты для HTML-текста сообщений (чат, превью).
class HtmlTextUtils {
  HtmlTextUtils._();

  static bool looksLikeHtml(String value) {
    final trimmed = value.trimLeft();
    if (trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<!doctype')) {
      return true;
    }
    return RegExp(r'<\s*\/?[a-zA-Z][^>]*>', caseSensitive: false).hasMatch(value);
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
