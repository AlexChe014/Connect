import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
    this.errorIcon = Icons.image_not_supported_outlined,
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final IconData errorIcon;

  @override
  Widget build(BuildContext context) {
    final trimmed = url?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: (trimmed == null || trimmed.isEmpty)
          ? _errorPlaceholder()
          : CachedNetworkImage(
              imageUrl: trimmed,
              width: width,
              height: height,
              fit: fit,
              placeholder: (context, url) => AppSkeletonBox(
                width: width,
                height: height ?? 16,
                borderRadius: 0,
              ),
              errorWidget: (context, url, error) => _errorPlaceholder(),
            ),
    );
  }

  Widget _errorPlaceholder() {
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: AppColors.surfaceElevated,
        child: Icon(
          errorIcon,
          color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
