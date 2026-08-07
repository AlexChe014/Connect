import 'booking_recurring.dart';

/// Тело запроса `POST /booking/create` (form-data).
class CreateBookingRequest {
  final String theme;
  final int modelType;
  final int modelId;
  final int datetimeStartSeconds;
  final int datetimeEndSeconds;
  final List<int> userIds;
  final BookingRecurring? recurring;
  final String? description;
  final String? link;
  final bool generateLink;
  final bool isPrivate;

  /// Доп. услуги: ключ — id услуги, значение — количество (`add[id]`).
  final Map<int, int> additions;

  const CreateBookingRequest({
    required this.theme,
    required this.modelType,
    required this.modelId,
    required this.datetimeStartSeconds,
    required this.datetimeEndSeconds,
    this.userIds = const [],
    this.recurring,
    this.description,
    this.link,
    this.generateLink = false,
    this.isPrivate = false,
    this.additions = const {},
  });

  bool get isRecurring => recurring != null;

  List<MapEntry<String, String>> toFormEntries() {
    final entries = <MapEntry<String, String>>[
      MapEntry('theme', theme.trim()),
      MapEntry('model_type', modelType.toString()),
      MapEntry('model_id', modelId.toString()),
      MapEntry('datetime_start', datetimeStartSeconds.toString()),
      MapEntry('datetime_end', datetimeEndSeconds.toString()),
    ];

    for (final userId in userIds) {
      entries.add(MapEntry('users[]', userId.toString()));
    }

    final descriptionValue = description?.trim();
    if (descriptionValue != null && descriptionValue.isNotEmpty) {
      entries.add(MapEntry('description', descriptionValue));
    }

    final linkValue = link?.trim();
    if (linkValue != null && linkValue.isNotEmpty) {
      entries.add(MapEntry('link', linkValue));
    }

    if (generateLink) {
      entries.add(const MapEntry('generateLink', '1'));
    }

    if (isPrivate) {
      entries.add(const MapEntry('is_private', '1'));
    }

    for (final entry in additions.entries) {
      if (entry.value > 0) {
        entries.add(MapEntry('add[${entry.key}]', entry.value.toString()));
      }
    }

    if (recurring != null) {
      entries.addAll(recurring!.toFormEntries());
    }

    return entries;
  }
}
