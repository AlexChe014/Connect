import 'package:flutter/cupertino.dart';

import '../widgets/app_network_image.dart';

class NewsImageViewerScreen extends StatefulWidget {
  const NewsImageViewerScreen({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  State<NewsImageViewerScreen> createState() => _NewsImageViewerScreenState();
}

class _NewsImageViewerScreenState extends State<NewsImageViewerScreen> {
  final _transformationController = TransformationController();
  Offset _doubleTapPosition = Offset.zero;

  void _toggleZoom() {
    if (_transformationController.value.getMaxScaleOnAxis() > 1) {
      _transformationController.value = Matrix4.identity();
      return;
    }

    const scale = 3.0;
    _transformationController.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, -_doubleTapPosition.dx * (scale - 1))
      ..setEntry(1, 3, -_doubleTapPosition.dy * (scale - 1));
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.black,
        brightness: Brightness.dark,
        border: null,
        automaticallyImplyLeading: false,
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: Semantics(
            label: 'Закрыть изображение',
            child: const Icon(CupertinoIcons.xmark, color: CupertinoColors.white),
          ),
        ),
      ),
      child: SafeArea(
        child: GestureDetector(
          onDoubleTapDown: (details) =>
              _doubleTapPosition = details.localPosition,
          onDoubleTap: _toggleZoom,
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 1,
            maxScale: 5,
            child: SizedBox.expand(
              child: AppNetworkImage(
                url: widget.imageUrl,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
