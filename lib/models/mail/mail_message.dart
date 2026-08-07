import 'package:html/parser.dart' as html_parser;

class MailAttachment {
  final int id;
  final String filename;
  final String? mimeType;
  final int? size;

  const MailAttachment({
    required this.id,
    required this.filename,
    this.mimeType,
    this.size,
  });

  factory MailAttachment.fromJson(Map<String, dynamic> json) {
    return MailAttachment(
      id: _parseInt(json['id'] ?? json['attachment_id'] ?? json['uid']) ?? 0,
      filename: _optionalString(json, ['filename', 'name', 'file_name']) ?? 'file',
      mimeType: _optionalString(json, ['mime', 'mime_type', 'content_type']),
      size: _parseInt(json['size'] ?? json['file_size']),
    );
  }

  static String? _optionalString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final v = json[key];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static int? _parseInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }
}

class MailMessage {
  final int id;
  final String subject;
  final String from;
  final String? to;
  final String? body;
  final String? bodyHtml;
  final DateTime? date;
  final bool isRead;
  final bool hasAttachments;
  final List<MailAttachment> attachments;

  const MailMessage({
    required this.id,
    required this.subject,
    required this.from,
    this.to,
    this.body,
    this.bodyHtml,
    this.date,
    this.isRead = true,
    this.hasAttachments = false,
    this.attachments = const [],
  });

  String get previewBody {
    final plain = plainBody;
    if (plain.isNotEmpty) return plain;
    return '';
  }

  bool get hasBody => htmlContent != null || plainBody.isNotEmpty;

  /// HTML-версия письма для полноэкранного просмотра.
  String? get htmlContent {
    final html = bodyHtml?.trim();
    if (html != null && html.isNotEmpty) return html;

    final bodyText = body?.trim();
    if (bodyText != null && bodyText.isNotEmpty && _looksLikeHtml(bodyText)) {
      return bodyText;
    }
    return null;
  }

  /// Текстовая версия без разметки (для списка и ответа).
  String get plainBody {
    final text = body?.trim();
    if (text != null && text.isNotEmpty && !_looksLikeHtml(text)) {
      return _cleanPlainText(text);
    }

    final html = bodyHtml?.trim();
    if (html != null && html.isNotEmpty) {
      return _cleanPlainText(_htmlToPlainText(html));
    }

    if (text != null && text.isNotEmpty) {
      return _cleanPlainText(_htmlToPlainText(text));
    }
    return '';
  }

  static String _cleanPlainText(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  factory MailMessage.fromJson(Map<String, dynamic> json) {
    json = _flattenMessageJson(json);

    final attachments = <MailAttachment>[];
    final rawAttachments = json['attachments'];
    if (rawAttachments is List) {
      for (final item in rawAttachments) {
        if (item is Map<String, dynamic>) {
          attachments.add(MailAttachment.fromJson(item));
        }
      }
    }

    final hasAttachments = attachments.isNotEmpty ||
        json['has_attachments'] == true ||
        json['hasAttachments'] == true;

    var bodyHtml = _normalizeBodyString(_extractHtmlContent(json));
    var body = _normalizeBodyString(_extractPlainText(json));
    if (body == null && bodyHtml == null) {
      final fallback = _normalizeBodyString(_readScalarString(json['body']));
      if (fallback != null) {
        if (_looksLikeHtml(fallback)) {
          bodyHtml ??= fallback;
        } else {
          body = fallback;
        }
      }
    }
    bodyHtml ??= _normalizeBodyString(_extractBodyFromUnknownFields(json, preferHtml: true));
    body ??= _normalizeBodyString(_extractBodyFromUnknownFields(json, preferHtml: false));

    return MailMessage(
      id: _parseInt(
        json['id'] ??
            json['message_id'] ??
            json['uid'] ??
            json['msg_id'] ??
            json['msgno'],
      ) ??
          0,
      subject: _optionalString(json, ['subject', 'title', 'theme']) ?? '(без темы)',
      from: _parseAddress(json['from'] ?? json['sender']) ??
          _optionalString(json, ['from_email', 'from_name', 'from_address']) ??
          '',
      to: _parseAddress(json['to']) ??
          _optionalString(json, ['to_email', 'recipient', 'to_address']),
      body: body,
      bodyHtml: bodyHtml,
      date: _parseDate(
        json['date'] ??
            json['created_at'] ??
            json['sent_at'] ??
            json['datetime'] ??
            json['timestamp'] ??
            json['time'],
      ),
      isRead: _parseBool(
        json['seen'] ?? json['is_read'] ?? json['read'] ?? json['is_seen'],
        defaultValue: true,
      ),
      hasAttachments: hasAttachments,
      attachments: attachments,
    );
  }

  static Map<String, dynamic> _flattenMessageJson(Map<String, dynamic> json) {
    final flat = Map<String, dynamic>.from(json);
    for (final key in ['attributes', 'payload', 'data']) {
      final nested = json[key];
      if (nested is Map) {
        for (final entry in nested.entries) {
          flat.putIfAbsent(entry.key, () => entry.value);
        }
      }
    }
    return flat;
  }

  static String? _optionalString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = _readScalarString(json[key]);
      if (value != null) return value;
    }
    return null;
  }

  static String? _readScalarString(Object? value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    return null;
  }

  static String? _normalizeBodyString(String? value) {
    if (value == null) return null;
    var text = value.trim();
    if (text.isEmpty) return null;
    if (text.contains('&lt;') && text.contains('&gt;')) {
      text = _decodeHtmlEntities(text);
    }
    return text;
  }

  static String? _extractBodyFromUnknownFields(
    Map<String, dynamic> json, {
    required bool preferHtml,
  }) {
    for (final entry in json.entries) {
      final key = entry.key.toLowerCase();
      if (key == 'id' ||
          key == 'subject' ||
          key == 'from' ||
          key == 'to' ||
          key == 'date' ||
          key == 'attachments' ||
          key == 'service' ||
          key == 'email') {
        continue;
      }

      final value = _normalizeBodyString(_readScalarString(entry.value));
      if (value == null || value.length < 2) continue;

      final isHtml = _looksLikeHtml(value);
      if (preferHtml) {
        if (isHtml || key.contains('html') || key.contains('rich')) return value;
      } else if (!isHtml &&
          (key.contains('text') ||
              key.contains('plain') ||
              key.contains('body') ||
              key == 'content' ||
              key == 'message' ||
              key == 'snippet' ||
              key == 'preview')) {
        return value;
      }
    }

    final attributes = json['attributes'];
    if (attributes is Map) {
      return _extractBodyFromUnknownFields(
        attributes.cast<String, dynamic>(),
        preferHtml: preferHtml,
      );
    }

    return null;
  }

  static String? _extractPlainText(Map<String, dynamic> json) {
    for (final key in [
      'text',
      'text_body',
      'text_plain',
      'plain',
      'body_text',
      'snippet',
      'preview',
      'description',
    ]) {
      final value = _readScalarString(json[key]);
      if (value != null && !_looksLikeHtml(value)) return value;
    }

    for (final containerKey in ['body', 'content', 'message_body', 'bodies', 'payload']) {
      final extracted = _extractTextFromContainer(json[containerKey], preferHtml: false);
      if (extracted != null) return extracted;
    }

    return _extractFromParts(json['parts'], preferHtml: false);
  }

  static String? _extractHtmlContent(Map<String, dynamic> json) {
    for (final key in [
      'body_html',
      'html_body',
      'html',
      'content_html',
      'message_html',
      'text_html',
    ]) {
      final value = _readScalarString(json[key]);
      if (value != null) return value;
    }

    for (final containerKey in ['body', 'content', 'message_body', 'bodies', 'payload']) {
      final extracted = _extractTextFromContainer(json[containerKey], preferHtml: true);
      if (extracted != null) return extracted;
    }

    final body = _readScalarString(json['body']);
    if (body != null && _looksLikeHtml(body)) return body;

    final content = _readScalarString(json['content']);
    if (content != null && _looksLikeHtml(content)) return content;

    return _extractFromParts(json['parts'], preferHtml: true);
  }

  static String? _extractTextFromContainer(
    Object? container, {
    required bool preferHtml,
  }) {
    if (container == null) return null;

    if (container is String) {
      final value = container.trim();
      if (value.isEmpty) return null;
      if (preferHtml) {
        return _looksLikeHtml(value) ? value : null;
      }
      return _looksLikeHtml(value) ? null : value;
    }

    if (container is! Map) return null;
    final map = container.cast<String, dynamic>();

    if (preferHtml) {
      for (final key in ['html', 'html_body', 'body_html', 'content_html', 'rich']) {
        final value = _readScalarString(map[key]);
        if (value != null) return value;
      }
      final fallback = _readScalarString(map['body'] ?? map['content']);
      if (fallback != null && _looksLikeHtml(fallback)) return fallback;
      return null;
    }

    for (final key in ['text', 'plain', 'text_plain', 'text_body', 'body_text']) {
      final value = _readScalarString(map[key]);
      if (value != null && !_looksLikeHtml(value)) return value;
    }

    final fallback = _readScalarString(map['body'] ?? map['content']);
    if (fallback != null && !_looksLikeHtml(fallback)) return fallback;
    return null;
  }

  static String? _extractFromParts(Object? parts, {required bool preferHtml}) {
    if (parts is! List) return null;

    String? html;
    String? plain;

    for (final part in parts) {
      if (part is! Map) continue;
      final map = part.cast<String, dynamic>();
      final type = (map['type'] ?? map['content_type'] ?? map['mime'] ?? '')
          .toString()
          .toLowerCase();
      final content = _readScalarString(
        map['content'] ?? map['body'] ?? map['data'] ?? map['text'],
      );
      if (content == null) continue;

      if (type.contains('html')) {
        html ??= content;
      } else if (type.contains('plain') || type.contains('text')) {
        plain ??= content;
      } else if (_looksLikeHtml(content)) {
        html ??= content;
      } else {
        plain ??= content;
      }
    }

    return preferHtml ? (html ?? plain) : (plain ?? html);
  }

  static String? _parseAddress(Object? raw) {
    if (raw == null) return null;
    if (raw is String) {
      final s = raw.trim();
      return s.isEmpty ? null : s;
    }
    if (raw is Map) {
      final map = raw.cast<String, dynamic>();
      final email = _optionalString(map, ['email', 'address', 'mail']);
      final name = _optionalString(map, ['name', 'personal', 'display_name']);
      if (email != null && name != null) return '$name <$email>';
      return email ?? name;
    }
    if (raw is List && raw.isNotEmpty) {
      return _parseAddress(raw.first);
    }
    return null;
  }

  static int? _parseInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  static bool _parseBool(Object? v, {required bool defaultValue}) {
    if (v == null) return defaultValue;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return defaultValue;
  }

  static DateTime? _parseDate(Object? v) {
    if (v == null) return null;
    if (v is int) {
      final seconds = v > 9999999999 ? v ~/ 1000 : v;
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    }
    if (v is num) {
      final n = v.toInt();
      final seconds = n > 9999999999 ? n ~/ 1000 : n;
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    }
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    final parts = s.split('.');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    return null;
  }

  static bool _looksLikeHtml(String value) {
    final trimmed = value.trimLeft();
    if (trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<!doctype')) {
      return true;
    }
    return RegExp(r'<\s*\/?[a-zA-Z][^>]*>', caseSensitive: false).hasMatch(value);
  }

  static String _htmlToPlainText(String html) {
    try {
      final document = html_parser.parse(html);
      final extracted = document.body?.text ?? document.documentElement?.text;
      if (extracted != null) {
        final normalized = extracted
            .replaceAll(RegExp(r'[ \t]+'), ' ')
            .replaceAll(RegExp(r'\n[ \t]+'), '\n')
            .replaceAll(RegExp(r'\n{3,}'), '\n\n')
            .trim();
        if (normalized.isNotEmpty) return normalized;
      }
    } catch (_) {}

    var text = html
        .replaceAll(RegExp(r'<(br|BR)\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(p|div|tr|li|h[1-6]|blockquote)>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]*>'), ' ');
    text = _decodeHtmlEntities(text);
    return text
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static String _decodeHtmlEntities(String value) {
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }
}
