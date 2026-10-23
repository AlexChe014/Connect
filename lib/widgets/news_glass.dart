import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_theme.dart';
import '../models/news_item.dart';
import '../utils/file_size_format.dart';
import 'app_icon_badge.dart';
import 'app_network_image.dart';
import 'chat_avatar.dart';

/// Общие детали раздела «Лента» в стиле Liquid Glass.

/// Дата поста: «Сегодня», «Вчера», «21 октября», в прошлые годы — с годом.
String formatNewsDate(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Сегодня';
  if (diff == 1) return 'Вчера';
  if (local.year == now.year) {
    return DateFormat('d MMMM', 'ru_RU').format(local);
  }
  return DateFormat("d MMMM y 'г.'", 'ru_RU').format(local);
}

/// Аватар и имя автора, под именем — дата; у закреплённого поста — булавка.
class NewsAuthorLine extends StatelessWidget {
  const NewsAuthorLine({super.key, required this.news, this.avatarRadius = 18});

  final NewsItem news;
  final double avatarRadius;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final author = news.author;
    return Row(
      children: [
        MemberAvatar(
          displayName: author?.fullName ?? 'Автор',
          avatarUrl: author?.avatarUrl,
          radius: avatarRadius,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                author?.fullName ?? 'Автор',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                formatNewsDate(news.date),
                style: TextStyle(fontSize: 13, color: secondary),
              ),
            ],
          ),
        ),
        if (news.isPinned)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(CupertinoIcons.pin_fill, size: 16, color: secondary),
          ),
      ],
    );
  }
}

/// Фото поста (по умолчанию 16:9): снимок целиком (contain) на размытой копии самого
/// себя — портретные фото не обрезаются, а карточка не прыгает по высоте.
class NewsCoverImage extends StatelessWidget {
  const NewsCoverImage({
    super.key,
    required this.url,
    this.moreCount = 0,
    this.borderRadius = 16,
    this.aspectRatio = 16 / 9,
  });

  final String url;
  final double aspectRatio;

  /// Сколько ещё фото в посте — плашка «+N» в углу.
  final int moreCount;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: AppNetworkImage(
                url: url,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const ColoredBox(color: AppColors.scrimFaint),
            AppNetworkImage(
              url: url,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.contain,
            ),
            if (moreCount > 0)
              Positioned(
                right: 10,
                bottom: 10,
                child: _PhotoCountBadge(text: '+$moreCount'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Тёмная капсула поверх фото: «+2», «1 / 3».
class _PhotoCountBadge extends StatelessWidget {
  const _PhotoCountBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          color: AppColors.scrim,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.photo_on_rectangle,
                size: 13,
                color: CupertinoColors.white,
              ),
              const SizedBox(width: 4),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Листаемые фото поста с точками-индикаторами; тап — [onOpen] с номером.
class NewsPhotoGallery extends StatefulWidget {
  const NewsPhotoGallery({super.key, required this.urls, required this.onOpen});

  final List<String> urls;
  final ValueChanged<int> onOpen;

  @override
  State<NewsPhotoGallery> createState() => _NewsPhotoGalleryState();
}

class _NewsPhotoGalleryState extends State<NewsPhotoGallery> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    if (urls.length == 1) {
      return GestureDetector(
        onTap: () => widget.onOpen(0),
        child: _NaturalCoverImage(url: urls.first),
      );
    }
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: PageView.builder(
              itemCount: urls.length,
              onPageChanged: (page) => setState(() => _page = page),
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => widget.onOpen(index),
                child: NewsCoverImage(url: urls[index], borderRadius: 0),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < urls.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == _page ? 16 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: i == _page
                      ? CupertinoColors.label.resolveFrom(context)
                      : CupertinoColors.systemFill.resolveFrom(context),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Одиночное фото в посте — в собственных пропорциях, без размытых полос.
/// Совсем узкие и совсем широкие снимки ограничены, для них полосы остаются.
class _NaturalCoverImage extends StatefulWidget {
  const _NaturalCoverImage({required this.url});

  final String url;

  @override
  State<_NaturalCoverImage> createState() => _NaturalCoverImageState();
}

class _NaturalCoverImageState extends State<_NaturalCoverImage> {
  static const _minRatio = 4 / 5;
  static const _maxRatio = 2.4;

  ImageStream? _stream;
  late final _listener = ImageStreamListener(_onImage, onError: (_, _) {});
  double? _ratio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_NaturalCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _ratio = null;
      _resolve();
    }
  }

  void _resolve() {
    final url = widget.url.trim();
    if (url.isEmpty) return;
    final stream = CachedNetworkImageProvider(
      url,
    ).resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool _) {
    final image = info.image;
    if (!mounted || image.height == 0) return;
    setState(() {
      _ratio = (image.width / image.height).clamp(_minRatio, _maxRatio);
    });
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NewsCoverImage(url: widget.url, aspectRatio: _ratio ?? 16 / 9);
  }
}

/// Строка файла поста: значок, имя, размер. Тап скачивает файл и
/// открывает системный просмотр (QuickLook на iOS).
class NewsDocumentRow extends StatefulWidget {
  const NewsDocumentRow({super.key, required this.document, this.onError});

  final NewsDocument document;
  final ValueChanged<String>? onError;

  @override
  State<NewsDocumentRow> createState() => _NewsDocumentRowState();
}

class _NewsDocumentRowState extends State<NewsDocumentRow> {
  bool _isOpening = false;

  Future<void> _open() async {
    if (_isOpening) return;
    setState(() => _isOpening = true);
    try {
      final file = await _download(widget.document);
      final result = await OpenFilex.open(file.path);
      if (result.type == ResultType.noAppToOpen) {
        widget.onError?.call('Нет приложения, которое может открыть этот файл');
      } else if (result.type != ResultType.done) {
        widget.onError?.call('Не удалось открыть файл');
      }
    } catch (_) {
      widget.onError?.call('Не удалось скачать файл');
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
  }

  /// Файл кладётся во временную папку под своим именем — повторное
  /// открытие не качает его заново.
  static Future<File> _download(NewsDocument document) async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory(
      '${tmp.path}/news_files/${document.url.hashCode.toUnsigned(32)}',
    );
    final file = File('${dir.path}/${document.name.replaceAll('/', '_')}');
    if (await file.exists() && await file.length() > 0) return file;
    final response = await http.get(Uri.parse(document.url));
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}');
    }
    await dir.create(recursive: true);
    return file.writeAsBytes(response.bodyBytes, flush: true);
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final isPdf =
        document.mimeType == 'application/pdf' ||
        document.name.toLowerCase().endsWith('.pdf');
    return CupertinoListTile(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 10),
      leading: AppIconBadge(
        icon: CupertinoIcons.doc_text_fill,
        color: isPdf
            ? CupertinoColors.systemRed.resolveFrom(context)
            : CupertinoColors.systemGrey.resolveFrom(context),
      ),
      title: Text(
        document.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15),
      ),
      subtitle: document.size > 0 ? Text(formatFileSize(document.size)) : null,
      trailing: _isOpening
          ? const CupertinoActivityIndicator()
          : Icon(
              CupertinoIcons.arrow_down_circle,
              size: 22,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
      onTap: _open,
    );
  }
}
