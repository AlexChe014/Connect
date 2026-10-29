import 'package:cached_network_image/cached_network_image.dart';
import 'package:connect/services/link_preview_service.dart';
import 'package:connect/utils/html_text_utils.dart';
import 'package:connect/utils/open_link.dart';
import 'package:flutter/cupertino.dart';

final _firstUrlRegExp = RegExp(r'https?:\/\/[^\s<>"\)]+', caseSensitive: false);

/// Карточка первой ссылки сообщения под текстом, как в Telegram.
/// Пока превью грузится или его нет — ничего не рисует.
class ChatLinkPreview extends StatelessWidget {
  const ChatLinkPreview({super.key, required this.uri, required this.onBubble});

  final Uri uri;

  /// Цвет текста на пузыре.
  final Color onBubble;

  static const double _width = 260;

  /// Первая ссылка в тексте, для которой бывает превью; `null` — нет такой.
  static Uri? firstUrlIn(String text) {
    final plain = HtmlTextUtils.looksLikeHtml(text)
        ? HtmlTextUtils.toPlainText(text)
        : text;
    final match = _firstUrlRegExp.firstMatch(plain);
    if (match == null) return null;
    final raw = match.group(0)!.replaceAll(RegExp(r'[.,;:!?)]+$'), '');
    final uri = Uri.tryParse(raw);
    return uri != null && LinkPreviewService.supports(uri) ? uri : null;
  }

  @override
  Widget build(BuildContext context) {
    final service = LinkPreviewService.instance;
    if (service.isResolved(uri)) {
      final preview = service.resolved(uri);
      return preview == null ? const SizedBox.shrink() : _card(preview);
    }
    return FutureBuilder<LinkPreview?>(
      future: service.fetch(uri),
      builder: (context, snap) {
        final preview = snap.data;
        return preview == null ? const SizedBox.shrink() : _card(preview);
      },
    );
  }

  Widget _card(LinkPreview p) {
    final accent = onBubble;
    return GestureDetector(
      onTap: () => openLink(uri),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _width),
        child: Container(
          margin: const EdgeInsets.only(top: 6, bottom: 2),
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(color: accent.withValues(alpha: 0.7), width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                p.siteName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
              if (p.title != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    p.title!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: onBubble,
                    ),
                  ),
                ),
              if (p.description != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    p.description!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      color: onBubble.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              if (p.imageUrl != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: AspectRatio(
                      aspectRatio: 1.91,
                      child: CachedNetworkImage(
                        imageUrl: p.imageUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 720,
                        fadeInDuration: const Duration(milliseconds: 150),
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
