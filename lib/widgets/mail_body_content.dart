import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:webview_flutter/webview_flutter.dart';

import '../models/mail/mail_message.dart';
import '../utils/open_link.dart';

class MailBodyContent extends StatefulWidget {
  const MailBodyContent({
    super.key,
    required this.message,
    this.loadAttachment,
  });

  final MailMessage message;

  /// Скачивает вложение — для встроенных картинок (`<img src="cid:...">`:
  /// логотипы, подписи Outlook). Без него такие картинки остаются битыми.
  final Future<Uint8List> Function(MailAttachment attachment)? loadAttachment;

  static final _cidPattern = RegExp(
    r'''cid:([^"'\s)>]+)''',
    caseSensitive: false,
  );

  /// Вложение, на которое ссылается `cid:` из HTML: по Content-ID, а если
  /// сервер его не отдаёт — по имени файла (Outlook пишет
  /// `cid:image001.png@01DC...`, а вложение называется `image001.png`).
  static MailAttachment? _attachmentForCid(
    String cid,
    List<MailAttachment> attachments,
  ) {
    final id = Uri.decodeComponent(cid).toLowerCase();
    final name = id.split('@').first;
    for (final a in attachments) {
      if (a.contentId?.toLowerCase() == id) return a;
    }
    for (final a in attachments) {
      final file = a.filename.toLowerCase();
      if (file == id || file == name) return a;
    }
    return null;
  }

  /// Вложения, которые показываются внутри текста письма, — экрану их не
  /// нужно дублировать в списке «Вложения». Сравнивать по `id` нельзя:
  /// сервер его не отдаёт, у всех вложений он 0.
  static Set<MailAttachment> inlineAttachments(MailMessage message) {
    final html = message.htmlContent;
    if (html == null) return const {};
    return Set.identity()..addAll([
      for (final match in _cidPattern.allMatches(html))
        ?_attachmentForCid(match.group(1)!, message.attachments),
    ]);
  }

  /// Письмо будет показано в WebView (а не обычным текстом) — экрану это
  /// нужно знать, чтобы не добавлять вокруг HTML ещё один внутренний отступ.
  static bool rendersHtml(MailMessage message) {
    final html = message.htmlContent;
    return html != null && html.trim().isNotEmpty;
  }

  @override
  State<MailBodyContent> createState() => _MailBodyContentState();
}

class _MailBodyContentState extends State<MailBodyContent> {
  static const _heightChannel = 'MailBodyHeight';
  static const _selectionChannel = 'MailBodySelection';

  /// Высота до первого замера — небольшая, чтобы короткие письма не
  /// оставляли под собой пустое место, пока WebView грузится.
  static const _initialHeight = 120.0;

  WebViewController? _controller;
  double _contentHeight = _initialHeight;

  /// В письме выделен текст: пока выделение есть, WebView забирает все
  /// жесты — иначе вертикальное перетаскивание ручек выделения перехватывал
  /// скролл страницы, и выделить больше пары слов не получалось.
  bool _hasSelection = false;

  /// WebView уже отрисовал письмо. До этого на месте тела крутится
  /// индикатор — иначе медленное письмо выглядело как пустое окно.
  bool _isRendered = false;

  /// Завершается, когда страница загружена и в неё можно подставлять
  /// встроенные картинки.
  Completer<void> _pageFinished = Completer<void>();

  /// Номер загрузки: ответ на устаревший запрос картинок не должен
  /// подменить письмо, если его успели заменить.
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void didUpdateWidget(covariant MailBodyContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Экран сначала может показать письмо из списка, а потом подменить его
    // полной версией с сервера — без перезагрузки WebView остался бы старый
    // (или пустой) HTML.
    if (oldWidget.message.htmlContent != widget.message.htmlContent) {
      _contentHeight = _initialHeight;
      _hasSelection = false;
      _isRendered = false;
      _initController();
    }
  }

  void _initController() {
    final html = widget.message.htmlContent;
    if (html == null || html.trim().isEmpty) {
      _controller = null;
      return;
    }
    _pageFinished = Completer<void>();
    final pageFinished = _pageFinished;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..addJavaScriptChannel(_heightChannel, onMessageReceived: _onHeight)
      ..addJavaScriptChannel(_selectionChannel, onMessageReceived: _onSelection)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onPageFinished: (_) {
            if (!pageFinished.isCompleted) pageFinished.complete();
            if (mounted && !_isRendered) setState(() => _isRendered = true);
          },
        ),
      );
    unawaited(_load(html));
  }

  /// Текст письма показываем сразу, а встроенные картинки (`cid:`)
  /// подставляем в уже открытую страницу по мере скачивания — раньше
  /// письмо целиком ждало их до 8 секунд, и окно оставалось пустым.
  Future<void> _load(String html) async {
    final token = ++_loadToken;
    final controller = _controller;
    final pageFinished = _pageFinished;
    if (controller == null) return;
    await controller.loadHtmlString(_prepareHtml(html));
    final images = await _resolveCidImages(html);
    if (images.isEmpty) return;
    await pageFinished.future;
    if (!mounted || token != _loadToken || controller != _controller) return;
    for (final entry in images.entries) {
      try {
        await controller.runJavaScript(
          'window.mailSetCid(${jsonEncode(entry.key)}, '
          '${jsonEncode(entry.value)});',
        );
      } catch (_) {}
    }
  }

  /// Скачивает встроенные картинки как data-URI. Не дольше нескольких
  /// секунд на картинку: медленное вложение остаётся битым.
  Future<Map<String, String>> _resolveCidImages(String html) async {
    final load = widget.loadAttachment;
    if (load == null || !html.toLowerCase().contains('cid:')) return const {};
    final cids = MailBodyContent._cidPattern
        .allMatches(html)
        .map((m) => m.group(1)!)
        .toSet();
    final replacements = <String, String>{};
    await Future.wait(
      cids.map((cid) async {
        final attachment = MailBodyContent._attachmentForCid(
          cid,
          widget.message.attachments,
        );
        if (attachment == null) return;
        try {
          final bytes = await load(
            attachment,
          ).timeout(const Duration(seconds: 8));
          final mime =
              attachment.mimeType ?? _mimeFromName(attachment.filename);
          replacements[cid] = 'data:$mime;base64,${base64Encode(bytes)}';
        } catch (_) {
          // Картинка останется битой — как и раньше, но текст не пострадает.
        }
      }),
    );
    return replacements;
  }

  static String _mimeFromName(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'svg' => 'image/svg+xml',
      'bmp' => 'image/bmp',
      _ => 'image/png',
    };
  }

  void _onHeight(JavaScriptMessage message) {
    final height = double.tryParse(message.message);
    if (height == null || height <= 0 || !mounted) return;
    if ((height - _contentHeight).abs() < 1 && _isRendered) return;
    // Высота приходит из уже отрисованной страницы — запасной сигнал на
    // случай, если onPageFinished не сработает.
    setState(() {
      _contentHeight = height;
      _isRendered = true;
    });
  }

  void _onSelection(JavaScriptMessage message) {
    final hasSelection = message.message == '1';
    if (hasSelection == _hasSelection || !mounted) return;
    setState(() => _hasSelection = hasSelection);
  }

  /// Ссылки из письма открываем во встроенном браузере / почтовом клиенте,
  /// а не внутри WebView: иначе сайт открылся бы в блоке тела письма.
  Future<NavigationDecision> _onNavigationRequest(
    NavigationRequest request,
  ) async {
    final uri = Uri.tryParse(request.url);
    if (uri == null || uri.scheme == 'about' || uri.scheme == 'data') {
      return NavigationDecision.navigate;
    }
    if (!request.isMainFrame) return NavigationDecision.navigate;
    try {
      await openLink(uri);
    } catch (_) {}
    return NavigationDecision.prevent;
  }

  /// Подгоняет письмо под ширину экрана: свой viewport (письма из Outlook,
  /// рассылки и т.п. приходят полным документом без него — тогда WebView
  /// рисует их как десктопную страницу шириной ~980px), ограничение ширины
  /// картинок/таблиц, перенос длинных ссылок, плюс скрипт, сообщающий
  /// высоту содержимого — WebView растягивается по ней и скроллится вместе
  /// со страницей, а не отдельным окном внутри.
  String _prepareHtml(String html) {
    const head = '''
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  html { background: #ffffff; -webkit-text-size-adjust: 100%; }
  body { margin: 0 !important; padding: 12px !important; color: #000000;
         font-family: -apple-system, Roboto, Arial, sans-serif;
         word-wrap: break-word; overflow-wrap: anywhere; overflow-x: auto;
         -webkit-user-select: text !important; user-select: text !important; }
  img { max-width: 100% !important; height: auto !important; }
  table { max-width: 100% !important; }
  td, th { word-break: break-word; }
  pre { white-space: pre-wrap; }
</style>
''';
    const script = '''
<script>
(function () {
  var last = 0;
  function report() {
    var b = document.body;
    if (!b) return;
    var h = Math.ceil(Math.max(b.scrollHeight, b.offsetHeight,
        b.getBoundingClientRect().height));
    if (h > 0 && Math.abs(h - last) >= 1) {
      last = h;
      MailBodyHeight.postMessage(String(h));
    }
  }
  window.addEventListener('load', report);
  document.addEventListener('DOMContentLoaded', report);
  var imgs = document.images;
  for (var i = 0; i < imgs.length; i++) {
    imgs[i].addEventListener('load', report);
    imgs[i].addEventListener('error', report);
  }
  if (window.ResizeObserver) {
    new ResizeObserver(report).observe(document.body);
  }
  setTimeout(report, 300);
  setTimeout(report, 1500);
  window.mailSetCid = function (cid, uri) {
    var want = ('cid:' + cid).toLowerCase();
    var imgs = document.images;
    for (var i = 0; i < imgs.length; i++) {
      var src = (imgs[i].getAttribute('src') || '').toLowerCase();
      if (src === want) imgs[i].src = uri;
    }
  };
  var selected = false;
  document.addEventListener('selectionchange', function () {
    var s = window.getSelection();
    var now = !!s && !s.isCollapsed && String(s).length > 0;
    if (now !== selected) {
      selected = now;
      MailBodySelection.postMessage(now ? '1' : '0');
    }
  });
})();
</script>
''';

    var doc = html.trim();
    // Свой viewport письма (часто width=600 или вовсе фиксированный)
    // заменяем нашим — иначе на телефоне оно не масштабируется.
    doc = doc.replaceAll(
      RegExp(
        r'''<meta[^>]+name\s*=\s*["']?viewport["']?[^>]*>''',
        caseSensitive: false,
      ),
      '',
    );

    final lower = doc.toLowerCase();
    if (!lower.contains('<html')) {
      return '<!DOCTYPE html><html><head>$head</head>'
          '<body>$doc$script</body></html>';
    }

    final headOpen = RegExp(r'<head(\s[^>]*)?>', caseSensitive: false);
    final htmlOpen = RegExp(r'<html(\s[^>]*)?>', caseSensitive: false);
    if (headOpen.hasMatch(doc)) {
      doc = doc.replaceFirstMapped(headOpen, (m) => '${m[0]}$head');
    } else {
      doc = doc.replaceFirstMapped(
        htmlOpen,
        (m) => '${m[0]}<head>$head</head>',
      );
    }

    final bodyClose = RegExp(r'</body\s*>', caseSensitive: false);
    final htmlClose = RegExp(r'</html\s*>', caseSensitive: false);
    if (bodyClose.hasMatch(doc)) {
      doc = doc.replaceFirstMapped(bodyClose, (m) => '$script${m[0]}');
    } else if (htmlClose.hasMatch(doc)) {
      doc = doc.replaceFirstMapped(htmlClose, (m) => '$script${m[0]}');
    } else {
      doc = '$doc$script';
    }
    return doc;
  }

  @override
  Widget build(BuildContext context) {
    final plain = widget.message.plainBody;
    final html = widget.message.htmlContent;

    if (_controller != null) {
      // Очень длинные письма не растягиваем бесконечно (огромный WebView
      // тяжело рендерится, особенно на Android) — выше лимита письмо
      // скроллится внутри блока, и для этого WebView забирает вертикальные
      // жесты себе.
      final maxHeight = MediaQuery.sizeOf(context).height * 6;
      final isCapped = _contentHeight > maxHeight;
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: isCapped ? maxHeight : _contentHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: WebViewWidget(
                  controller: _controller!,
                  // Долгое нажатие всегда отдаём WebView, чтобы выделение текста
                  // начиналось сразу, а не проигрывало скроллу страницы.
                  gestureRecognizers: _hasSelection
                      ? {
                          Factory<EagerGestureRecognizer>(
                            EagerGestureRecognizer.new,
                          ),
                        }
                      : {
                          Factory<LongPressGestureRecognizer>(
                            LongPressGestureRecognizer.new,
                          ),
                          if (isCapped)
                            Factory<VerticalDragGestureRecognizer>(
                              VerticalDragGestureRecognizer.new,
                            ),
                        },
                ),
              ),
              if (!_isRendered)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0xFFFFFFFF),
                    child: Center(child: CupertinoActivityIndicator()),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (plain.isNotEmpty) {
      return SelectableText(
        plain,
        style: TextStyle(
          fontSize: 16,
          color: CupertinoColors.label.resolveFrom(context),
        ),
      );
    }

    if (html != null && html.trim().isNotEmpty) {
      return SelectableText(
        html,
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.label.resolveFrom(context),
        ),
      );
    }

    return Text(
      'Текст письма отсутствует',
      style: TextStyle(
        fontSize: 16,
        color: CupertinoColors.secondaryLabel.resolveFrom(context),
      ),
    );
  }
}
