import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:webview_flutter/webview_flutter.dart';

import '../config/app_theme.dart';
import '../models/mail/mail_message.dart';
import '../utils/open_link.dart';

class MailBodyContent extends StatefulWidget {
  const MailBodyContent({
    super.key,
    required this.message,
    this.loadAttachment,
    this.keepOriginalColors = false,
  });

  final MailMessage message;

  /// В тёмной теме не перекрашивать письмо, а показать его как есть — на
  /// белой подложке (если автоматическая инверсия испортила вёрстку).
  final bool keepOriginalColors;

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

  /// Тёмные цвета письма. Не инверсия целиком (белый текст на цветной
  /// плашке от неё становился тёмным), а перекраска каждого элемента по
  /// его итоговым цветам: светлые фоны темнеют до подложки с сохранением
  /// оттенка, насыщенные плашки лишь чуть темнеют, тёмный текст светлеет,
  /// а затем текст подтягивается до контраста 4.5 со своим новым фоном.
  /// Картинки и блоки с фоновой картинкой (баннеры) не трогаем. Исходные
  /// inline-стили запоминаются — `mailSetDark(false)` возвращает письмо
  /// как было, без перезагрузки.
  static const _darkColorsScript = r'''
<script>
(function () {
  var saved = null;

  function parse(c) {
    var m = /rgba?\(([^)]+)\)/.exec(c || '');
    if (!m) return null;
    var p = m[1].split(/[\s,\/]+/).filter(Boolean).map(parseFloat);
    return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
  }
  function css(c) {
    return 'rgb(' + Math.round(c.r) + ',' + Math.round(c.g) + ',' +
        Math.round(c.b) + ')';
  }
  function toHsl(c) {
    var r = c.r / 255, g = c.g / 255, b = c.b / 255;
    var max = Math.max(r, g, b), min = Math.min(r, g, b);
    var l = (max + min) / 2, h = 0, s = 0, d = max - min;
    if (d > 0) {
      s = d / (1 - Math.abs(2 * l - 1));
      if (max === r) h = ((g - b) / d) % 6;
      else if (max === g) h = (b - r) / d + 2;
      else h = (r - g) / d + 4;
      h *= 60;
      if (h < 0) h += 360;
    }
    return { h: h, s: s, l: l };
  }
  function fromHsl(h, s, l) {
    var c = (1 - Math.abs(2 * l - 1)) * s;
    var x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = l - c / 2;
    var r = 0, g = 0, b = 0;
    if (h < 60) { r = c; g = x; }
    else if (h < 120) { r = x; g = c; }
    else if (h < 180) { g = c; b = x; }
    else if (h < 240) { g = x; b = c; }
    else if (h < 300) { r = x; b = c; }
    else { r = c; b = x; }
    return { r: (r + m) * 255, g: (g + m) * 255, b: (b + m) * 255, a: 1 };
  }
  function lum(c) {
    function ch(v) {
      v /= 255;
      return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }
  function contrast(a, b) {
    var x = lum(a), y = lum(b);
    return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
  }

  // Фон и рамки: белый становится подложкой, светлые — чуть светлее неё
  // (сохраняется рисунок письма), насыщенные средние лишь темнеют.
  function darkBg(c) {
    var hsl = toHsl(c);
    if (hsl.l >= 0.75) {
      var l = 0.11 + (1 - hsl.l) * 0.6;
      if (hsl.s < 0.1) {
        var base = window.mailDarkBase, d = (l - 0.11) * 255;
        return { r: base[0] + d, g: base[1] + d, b: base[2] + d, a: 1 };
      }
      return fromHsl(hsl.h, Math.min(hsl.s, 0.5), l);
    }
    if (hsl.l > 0.3) return fromHsl(hsl.h, hsl.s, hsl.l * 0.65);
    return null;
  }
  function lightText(c, bg) {
    var hsl = toHsl(c);
    var l = hsl.l < 0.5 ? 0.9 - hsl.l * 0.6 : hsl.l;
    var out = fromHsl(hsl.h, hsl.s, l);
    // Светлый текст остаётся светлее фона: белый заголовок на цветной
    // плашке не должен превращаться в тёмный.
    var up = lum(out) >= lum(bg);
    for (var i = 0; i < 20 && contrast(out, bg) < 4.5; i++) {
      l = up ? Math.min(1, l + 0.05) : Math.max(0, l - 0.05);
      out = fromHsl(hsl.h, hsl.s, l);
    }
    return out;
  }

  var SKIP = { IMG: 1, VIDEO: 1, PICTURE: 1, CANVAS: 1, SCRIPT: 1,
      STYLE: 1, BR: 1, svg: 1 };
  var SIDES = ['top', 'right', 'bottom', 'left'];

  function set(el, prop, value) {
    saved.push([el, prop, el.style.getPropertyValue(prop),
        el.style.getPropertyPriority(prop)]);
    el.style.setProperty(prop, value, 'important');
  }

  function apply() {
    saved = [];
    var body = document.body;
    var els = [body].concat(Array.prototype.slice.call(
        body.querySelectorAll('*')));
    // Сначала читаем все исходные цвета, потом пишем: иначе дети
    // унаследовали бы уже перекрашенный цвет родителя.
    var items = [];
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      if (SKIP[el.tagName] || (el.closest && el.closest('svg'))) continue;
      var cs = getComputedStyle(el);
      var borders = [];
      for (var k = 0; k < 4; k++) {
        var side = SIDES[k];
        if (cs.getPropertyValue('border-' + side + '-style') !== 'none' &&
            parseFloat(cs.getPropertyValue('border-' + side + '-width')) > 0) {
          borders.push([side, parse(cs.getPropertyValue(
              'border-' + side + '-color'))]);
        }
      }
      items.push({ el: el, color: parse(cs.color),
          bg: parse(cs.backgroundColor),
          image: cs.backgroundImage && cs.backgroundImage !== 'none',
          borders: borders });
    }
    var base = window.mailDarkBase;
    var pageBg = { r: base[0], g: base[1], b: base[2], a: 1 };
    var effBg = new Map(), onImage = new Map();
    for (var j = 0; j < items.length; j++) {
      var it = items[j], parent = it.el.parentElement;
      var image = it.image || onImage.get(parent) === true;
      onImage.set(it.el, image);
      if (image) continue;
      var bg = effBg.get(parent) || pageBg;
      if (it.bg && it.bg.a > 0) {
        var nb = darkBg(it.bg);
        if (nb) set(it.el, 'background-color', css(nb));
        if (it.bg.a > 0.5) bg = nb || it.bg;
      }
      effBg.set(it.el, bg);
      if (it.color) set(it.el, 'color', css(lightText(it.color, bg)));
      for (var b = 0; b < it.borders.length; b++) {
        var bc = it.borders[b][1];
        var nbc = bc && bc.a > 0 && darkBg(bc);
        if (nbc) set(it.el, 'border-' + it.borders[b][0] + '-color', css(nbc));
      }
    }
  }

  function restore() {
    for (var i = saved.length - 1; i >= 0; i--) {
      var s = saved[i];
      if (s[2]) s[0].style.setProperty(s[1], s[2], s[3]);
      else s[0].style.removeProperty(s[1]);
    }
    saved = null;
  }

  window.mailSetDark = function (on) {
    if (!document.body) return;
    document.documentElement.classList.toggle('mail-dark', on);
    if (on && !saved) apply();
    else if (!on && saved) restore();
  };
})();
</script>
''';

  /// Письмо под ширину экрана. Рассылки свёрстаны фиксированными
  /// таблицами (обычно 600px) и вылезали за правый край. Сначала всё, что
  /// шире экрана, делаем резиновым: таблицы — 100%, ячейки и блоки — по
  /// содержимому. Если письмо всё равно не влезает (колонки фиксированной
  /// ширины, широкие картинки в ряд) — уменьшаем его целиком, как Apple
  /// Mail, а высоту для WebView пересчитываем с этим масштабом.
  static const _fitScript = r'''
<script>
(function () {
  function overflow() {
    return document.documentElement.scrollWidth -
        document.documentElement.clientWidth;
  }
  function fit() {
    var body = document.body;
    if (!body || window.mailFitScale) return;
    var vw = document.documentElement.clientWidth;
    if (overflow() <= 1) return;
    var wide = [];
    var els = body.querySelectorAll('*');
    for (var i = 0; i < els.length; i++) {
      var tag = els[i].tagName;
      if (tag === 'IMG' || tag === 'VIDEO' || tag === 'CANVAS') continue;
      if (els[i].offsetWidth > vw) wide.push(els[i]);
    }
    for (var j = 0; j < wide.length; j++) {
      var el = wide[j], st = el.style;
      st.setProperty('min-width', '0', 'important');
      if (el.tagName === 'TABLE') {
        st.setProperty('width', '100%', 'important');
      } else {
        st.setProperty('width', 'auto', 'important');
        st.setProperty('max-width', '100%', 'important');
      }
      if (el.hasAttribute('width')) el.removeAttribute('width');
    }
    var extra = overflow();
    if (extra > 1) {
      var width = vw + extra;
      var scale = vw / width;
      body.style.setProperty('overflow', 'visible', 'important');
      body.style.setProperty('width', width + 'px', 'important');
      body.style.transformOrigin = '0 0';
      body.style.transform = 'scale(' + scale + ')';
      document.documentElement.style.overflowX = 'hidden';
      window.mailFitScale = scale;
    }
    if (window.mailReportHeight) window.mailReportHeight();
  }
  fit();
  window.addEventListener('load', fit);
})();
</script>
''';

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

  /// Письмо показывается в тёмных цветах: тёмная тема и пользователь не
  /// попросил исходные цвета. Контроллер создаётся в
  /// didChangeDependencies — тему в initState ещё не прочитать.
  bool? _darkColors;

  Color get _background => _darkColors == true
      ? AppColors.mailBodyBackground.darkColor
      : AppColors.mailBodyBackground.color;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncDarkColors();
  }

  @override
  void didUpdateWidget(covariant MailBodyContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepOriginalColors != widget.keepOriginalColors) {
      _syncDarkColors();
    }
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

  /// Переключение цветов не перезагружает письмо: на открытой странице
  /// включается или выключается стиль инверсии.
  void _syncDarkColors() {
    final dark =
        CupertinoTheme.brightnessOf(context) == Brightness.dark &&
        !widget.keepOriginalColors;
    if (dark == _darkColors) return;
    final isFirst = _darkColors == null;
    _darkColors = dark;
    if (isFirst) {
      _initController();
      return;
    }
    final controller = _controller;
    if (controller == null) return;
    unawaited(controller.setBackgroundColor(_background));
    unawaited(_applyDarkColors(controller, _pageFinished));
  }

  Future<void> _applyDarkColors(
    WebViewController controller,
    Completer<void> pageFinished,
  ) async {
    await pageFinished.future;
    if (!mounted || controller != _controller) return;
    try {
      await controller.runJavaScript(
        'window.mailSetDark(${_darkColors == true});',
      );
    } catch (_) {}
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
      ..setBackgroundColor(_background)
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
  ///
  ///
  /// Тёмные цвета — см. [_darkColorsScript]. Свои dark-стили писем
  /// (`prefers-color-scheme: dark`) отключены: WebView включает их по
  /// системной теме, а не по теме приложения, и перекраска сделала бы
  /// уже тёмное письмо обратно светлым.
  String _prepareHtml(String html) {
    final base = AppColors.mailBodyBackground.darkColor.toARGB32();
    final baseRgb = [(base >> 16) & 0xFF, (base >> 8) & 0xFF, base & 0xFF];
    final head =
        '''
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="only light">
<style>
  :root { color-scheme: only light !important; }
  html { background: #ffffff; -webkit-text-size-adjust: 100%; }
  html.mail-dark { background: rgb(${baseRgb.join(',')}) !important; }
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
    const baseScript = '''
<script>
(function () {
  var last = 0;
  function report() {
    var b = document.body;
    if (!b) return;
    // mailFitScale — письмо уменьшено под ширину экрана (см. mailFit),
    // а scrollHeight/offsetHeight считаются без этого уменьшения.
    var z = window.mailFitScale || 1;
    var h = Math.ceil(Math.max(b.scrollHeight * z, b.offsetHeight * z,
        b.getBoundingClientRect().height));
    if (h > 0 && Math.abs(h - last) >= 1) {
      last = h;
      MailBodyHeight.postMessage(String(h));
    }
  }
  window.mailReportHeight = report;
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
    final script =
        '$baseScript$_fitScript<script>window.mailDarkBase = [${baseRgb.join(',')}];'
        '</script>$_darkColorsScript'
        '<script>window.mailSetDark(${_darkColors == true});</script>';

    var doc = html.trim().replaceAll(
      RegExp(r'prefers-color-scheme\s*:\s*dark', caseSensitive: false),
      'prefers-color-scheme: none',
    );
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
                Positioned.fill(
                  child: ColoredBox(
                    color: _background,
                    child: const Center(child: CupertinoActivityIndicator()),
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
