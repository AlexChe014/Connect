import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/mail/mail_message.dart';

class MailBodyContent extends StatefulWidget {
  const MailBodyContent({super.key, required this.message});

  final MailMessage message;

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

  /// Высота до первого замера — небольшая, чтобы короткие письма не
  /// оставляли под собой пустое место, пока WebView грузится.
  static const _initialHeight = 120.0;

  WebViewController? _controller;
  double _contentHeight = _initialHeight;

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
      _initController();
    }
  }

  void _initController() {
    final html = widget.message.htmlContent;
    if (html == null || html.trim().isEmpty) {
      _controller = null;
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..addJavaScriptChannel(_heightChannel, onMessageReceived: _onHeight)
      ..setNavigationDelegate(
        NavigationDelegate(onNavigationRequest: _onNavigationRequest),
      )
      ..loadHtmlString(_prepareHtml(html));
  }

  void _onHeight(JavaScriptMessage message) {
    final height = double.tryParse(message.message);
    if (height == null || height <= 0 || !mounted) return;
    if ((height - _contentHeight).abs() < 1) return;
    setState(() => _contentHeight = height);
  }

  /// Ссылки из письма открываем во внешнем браузере / почтовом клиенте,
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
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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
         word-wrap: break-word; overflow-wrap: anywhere; overflow-x: auto; }
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
          child: WebViewWidget(
            controller: _controller!,
            gestureRecognizers: isCapped
                ? {
                    Factory<VerticalDragGestureRecognizer>(
                      VerticalDragGestureRecognizer.new,
                    ),
                  }
                : const <Factory<OneSequenceGestureRecognizer>>{},
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
