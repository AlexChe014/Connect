import 'dart:async';
import 'dart:convert';

import 'package:connect/config/api_config.dart';
import 'package:connect/utils/connector_url_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

/// Карточка ссылки по Open Graph: сайт, заголовок, описание, картинка.
@immutable
class LinkPreview {
  const LinkPreview({
    required this.url,
    required this.siteName,
    this.title,
    this.description,
    this.imageUrl,
  });

  final Uri url;
  final String siteName;
  final String? title;
  final String? description;
  final String? imageUrl;
}

/// Превью ссылок в чате. Сервер их не делает, поэтому страницу читает
/// сам телефон: только начало HTML, с таймаутом, результат — в памяти.
class LinkPreviewService {
  LinkPreviewService._();
  static final LinkPreviewService instance = LinkPreviewService._();

  static const int _maxBytes = 512 * 1024;
  static const Duration _timeout = Duration(seconds: 6);
  static const int _maxCached = 200;

  final Map<String, Future<LinkPreview?>> _cache = {};

  /// Уже загруженные превью — чтобы при пересборке пузыря карточка
  /// не мигала, пока FutureBuilder ждёт готовый Future.
  final Map<String, LinkPreview?> _resolved = {};
  final http.Client _client = http.Client();

  /// Ссылки, у которых превью не бывает: ВКС и наш портал (за входом —
  /// там была бы страница логина).
  static bool supports(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (uri.host.isEmpty) return false;
    if (connectorRoomFromUrl(uri.toString()) != null) return false;
    final ownHost = Uri.tryParse(ApiConfig.baseUrl)?.host;
    return ownHost == null || uri.host != ownHost;
  }

  bool isResolved(Uri uri) => _resolved.containsKey(uri.toString());
  LinkPreview? resolved(Uri uri) => _resolved[uri.toString()];

  Future<LinkPreview?> fetch(Uri uri) {
    final key = uri.toString();
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached; // В конец — недавно использованная.
      return cached;
    }
    if (_cache.length >= _maxCached) _cache.remove(_cache.keys.first);
    return _cache[key] = _load(uri);
  }

  Future<LinkPreview?> _load(Uri uri) async {
    LinkPreview? result;
    try {
      result = await _download(uri).timeout(_timeout);
    } catch (e) {
      debugPrint('LinkPreview $uri: $e');
    }
    if (_resolved.length >= _maxCached) _resolved.remove(_resolved.keys.first);
    _resolved[uri.toString()] = result;
    return result;
  }

  Future<LinkPreview?> _download(Uri uri) async {
    final request = http.Request('GET', uri)
      ..headers['User-Agent'] = 'Mozilla/5.0 (compatible; ConnectLinkPreview)'
      ..headers['Accept'] = 'text/html,application/xhtml+xml';
    final response = await _client.send(request);
    if (response.statusCode >= 400) return null;
    final type = response.headers['content-type'] ?? '';
    if (!type.contains('html')) return null;
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      if (bytes.length >= _maxBytes) break;
    }
    final finalUri = response.request?.url ?? uri;
    return _parse(finalUri, utf8.decode(bytes, allowMalformed: true));
  }

  static LinkPreview? _parse(Uri uri, String body) {
    final doc = html_parser.parse(body);
    String? meta(String key) {
      for (final el in doc.getElementsByTagName('meta')) {
        final name = el.attributes['property'] ?? el.attributes['name'];
        if (name?.toLowerCase() == key) {
          final content = el.attributes['content']?.trim();
          if (content != null && content.isNotEmpty) return content;
        }
      }
      return null;
    }

    final title =
        meta('og:title') ??
        meta('twitter:title') ??
        doc.getElementsByTagName('title').firstOrNull?.text.trim();
    final description =
        meta('og:description') ??
        meta('twitter:description') ??
        meta('description');
    final image = meta('og:image') ?? meta('twitter:image');
    final imageUri = image == null ? null : uri.resolve(image);
    if ((title == null || title.isEmpty) && description == null) return null;
    return LinkPreview(
      url: uri,
      siteName: meta('og:site_name') ?? uri.host.replaceFirst('www.', ''),
      title: title == null || title.isEmpty ? null : title,
      description: description,
      imageUrl:
          imageUri != null &&
              (imageUri.scheme == 'https' || imageUri.scheme == 'http')
          ? imageUri.toString()
          : null,
    );
  }
}
