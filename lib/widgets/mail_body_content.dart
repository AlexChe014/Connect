import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/mail/mail_message.dart';

class MailBodyContent extends StatefulWidget {
  const MailBodyContent({super.key, required this.message});

  final MailMessage message;

  @override
  State<MailBodyContent> createState() => _MailBodyContentState();
}

class _MailBodyContentState extends State<MailBodyContent> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    final html = widget.message.htmlContent;
    if (html != null && html.trim().isNotEmpty) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..loadHtmlString(_prepareHtml(html));
    }
  }

  String _prepareHtml(String html) {
    final trimmed = html.trim();
    if (trimmed.toLowerCase().contains('<html')) {
      return trimmed;
    }
    return '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
  </head>
  <body style="margin:0;padding:8px;font-family:Arial,sans-serif;">
    $trimmed
  </body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plain = widget.message.plainBody;
    final html = widget.message.htmlContent;

    if (_controller != null) {
      return SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: WebViewWidget(controller: _controller!),
        ),
      );
    }

    if (plain.isNotEmpty) {
      return SelectableText(
        plain,
        style: theme.textTheme.bodyLarge,
      );
    }

    if (html != null && html.trim().isNotEmpty) {
      return SelectableText(
        html,
        style: theme.textTheme.bodySmall,
      );
    }

    return Text(
      'Текст письма отсутствует',
      style: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
