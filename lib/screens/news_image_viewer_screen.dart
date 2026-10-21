import 'package:flutter/cupertino.dart';

import '../widgets/app_network_image.dart';

/// Фото поста на весь экран: листание, двойной тап и щипок — зум.
class NewsImageViewerScreen extends StatefulWidget {
  const NewsImageViewerScreen({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  final List<String> imageUrls;
  final int initialIndex;

  @override
  State<NewsImageViewerScreen> createState() => _NewsImageViewerScreenState();
}

class _NewsImageViewerScreenState extends State<NewsImageViewerScreen> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  late int _page = widget.initialIndex;

  /// Пока фото увеличено, свайп двигает его, а не листает страницы.
  bool _isZoomed = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.imageUrls.length;
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.black,
        brightness: Brightness.dark,
        border: null,
        automaticallyImplyLeading: false,
        middle: count > 1
            ? Text(
                '${_page + 1} из $count',
                style: const TextStyle(color: CupertinoColors.white),
              )
            : null,
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: Semantics(
            label: 'Закрыть изображение',
            child: const Icon(
              CupertinoIcons.xmark,
              color: CupertinoColors.white,
            ),
          ),
        ),
      ),
      child: SafeArea(
        child: PageView.builder(
          controller: _pageController,
          physics: _isZoomed
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(),
          itemCount: count,
          onPageChanged: (page) => setState(() {
            _page = page;
            _isZoomed = false;
          }),
          itemBuilder: (context, index) => _ZoomableImage(
            url: widget.imageUrls[index],
            onZoomChanged: (zoomed) {
              if (zoomed != _isZoomed) setState(() => _isZoomed = zoomed);
            },
          ),
        ),
      ),
    );
  }
}

class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({required this.url, required this.onZoomChanged});

  final String url;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final _transformationController = TransformationController();
  Offset _doubleTapPosition = Offset.zero;

  bool get _isZoomed => _transformationController.value.getMaxScaleOnAxis() > 1;

  void _toggleZoom() {
    if (_isZoomed) {
      _transformationController.value = Matrix4.identity();
    } else {
      const scale = 3.0;
      _transformationController.value = Matrix4.identity()
        ..setEntry(0, 0, scale)
        ..setEntry(1, 1, scale)
        ..setEntry(0, 3, -_doubleTapPosition.dx * (scale - 1))
        ..setEntry(1, 3, -_doubleTapPosition.dy * (scale - 1));
    }
    widget.onZoomChanged(_isZoomed);
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTapPosition = details.localPosition,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 1,
        maxScale: 5,
        onInteractionEnd: (_) => widget.onZoomChanged(_isZoomed),
        child: SizedBox.expand(
          child: AppNetworkImage(
            url: widget.url,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
