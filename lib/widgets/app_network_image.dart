import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';

import '../config/app_theme.dart';
import 'app_loading.dart';

/// Единая обёртка над сетевой картинкой: диск-кэш, плавное появление и
/// общий стиль плейсхолдера/ошибки — вместо `Image.network(errorBuilder: ...)`,
/// повторяющегося в каждом экране на свой лад.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 0,
    this.errorIcon = CupertinoIcons.photo,
    this.httpHeaders,
    this.memCacheWidth,
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final IconData errorIcon;
  final Map<String, String>? httpHeaders;

  /// Ширина раскодирования в пикселях. Без неё снимок с камеры лежит в
  /// памяти целиком (десятки МБ) и быстро вытесняет остальные из кэша.
  final int? memCacheWidth;

  @override
  Widget build(BuildContext context) {
    final trimmed = url?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: (trimmed == null || trimmed.isEmpty)
          ? _errorPlaceholder(context)
          : CachedNetworkImage(
              imageUrl: trimmed,
              httpHeaders: httpHeaders,
              memCacheWidth: memCacheWidth,
              width: width,
              height: height,
              fit: fit,
              placeholder: (context, url) => AppSkeletonBox(
                width: width,
                height: height ?? 16,
                borderRadius: 0,
              ),
              errorWidget: (context, url, error) => _errorPlaceholder(context),
            ),
    );
  }

  Widget _errorPlaceholder(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: AppColors.placeholderFill.resolveFrom(context),
        child: Icon(
          errorIcon,
          color: AppColors.placeholderIcon.resolveFrom(context),
        ),
      ),
    );
  }
}
