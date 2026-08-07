import 'package:flutter/material.dart';

import '../config/app_icons.dart';
import '../models/bookings/bookable_object.dart';

/// Фото и краткая информация об объекте бронирования.
class BookableObjectPreview extends StatelessWidget {
  const BookableObjectPreview({
    super.key,
    required this.object,
    this.compact = false,
  });

  final BookableObject object;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final imageUrl = object.previewImageUrl;
    final imageSize = compact ? 56.0 : 72.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: imageSize,
          height: imageSize,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: imageUrl == null
              ? AppIcon(
                  AppIcons.locationPin,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: compact ? 26 : 32,
                )
              : Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.broken_image_outlined,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!compact)
                Text(
                  object.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              if (object.capacity > 0) ...[
                SizedBox(height: compact ? 0 : 6),
                Text(
                  'Вместимость: до ${object.capacity} чел.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
              if ((object.description ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  object.description!.trim(),
                  maxLines: compact ? 2 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
