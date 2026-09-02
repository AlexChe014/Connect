import 'package:connect/config/api_config.dart';
import 'package:connect/utils/media_url_utils.dart';

class BookableObjectMedia {
  final int id;
  final String? originalUrl;
  final String? previewUrl;

  const BookableObjectMedia({
    required this.id,
    this.originalUrl,
    this.previewUrl,
  });

  factory BookableObjectMedia.fromJson(Map<String, dynamic> json) {
    final url = MediaUrlUtils.firstUrl(json);
    return BookableObjectMedia(
      id: (json['id'] as num?)?.toInt() ?? 0,
      originalUrl: ApiConfig.normalizeFileUrl(
        (json['original_url'] as String?) ?? url,
      ),
      previewUrl: ApiConfig.normalizeFileUrl(
        (json['preview_url'] as String?) ?? url,
      ),
    );
  }
}

class BookableObject {
  final int id;
  final bool isActive;
  final String name;
  final String? description;
  final int capacity;
  final int? order;
  final int? spaceId;
  final bool isFavorite;
  final List<BookableObjectMedia> media;

  /// `favoritable_type` для этого объекта в полиморфном избранном — разный
  /// для переговорок, рабочих мест и т.д. (см. `FavoritesRepository`).
  /// Приходит либо из записи `Favorite` (`GET /user/favorites/objects`),
  /// либо проставляется вызывающим кодом из `BookingObjectType.typeId`,
  /// которым был запрошен список объектов бронирования.
  final int? favoriteTypeId;

  const BookableObject({
    required this.id,
    required this.isActive,
    required this.name,
    this.description,
    required this.capacity,
    this.order,
    this.spaceId,
    required this.isFavorite,
    this.media = const [],
    this.favoriteTypeId,
  });

  BookableObject withFavoriteTypeId(int favoriteTypeId) => BookableObject(
    id: id,
    isActive: isActive,
    name: name,
    description: description,
    capacity: capacity,
    order: order,
    spaceId: spaceId,
    isFavorite: isFavorite,
    media: media,
    favoriteTypeId: favoriteTypeId,
  );

  String? get previewImageUrl => media.firstWhere(
        (m) => (m.previewUrl ?? '').isNotEmpty,
        orElse: () => const BookableObjectMedia(id: 0),
      ).previewUrl ??
      media.firstWhere(
        (m) => (m.originalUrl ?? '').isNotEmpty,
        orElse: () => const BookableObjectMedia(id: 0),
      ).originalUrl;

  factory BookableObject.fromJson(Map<String, dynamic> json) {
    final isActiveRaw = json['is_active'];
    final favoriteRaw = json['is_favorite'];
    final mediaRaw = json['media'];
    return BookableObject(
      id: (json['id'] as num?)?.toInt() ?? 0,
      isActive: isActiveRaw == true || isActiveRaw == 1 || isActiveRaw == '1',
      name: (json['name'] as String?)?.trim() ?? '',
      description: json['description'] as String?,
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      order: (json['order'] as num?)?.toInt(),
      spaceId: (json['space_id'] as num?)?.toInt(),
      isFavorite: favoriteRaw == true || favoriteRaw == 1 || favoriteRaw == '1',
      media: _parseMediaList(mediaRaw),
      favoriteTypeId: (json['favoritable_type'] as num?)?.toInt(),
    );
  }

  static List<BookableObjectMedia> _parseMediaList(Object? mediaRaw) {
    if (mediaRaw is List) {
      return mediaRaw
          .whereType<Map>()
          .map((e) => BookableObjectMedia.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    if (mediaRaw is Map) {
      return [BookableObjectMedia.fromJson(mediaRaw.cast<String, dynamic>())];
    }
    return const [];
  }
}

