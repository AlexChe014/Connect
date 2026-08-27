/// Тело `POST /connector/schedule`.
class ScheduleConnectorRequest {
  const ScheduleConnectorRequest({
    required this.theme,
    required this.datetimeStartSeconds,
    required this.datetimeEndSeconds,
    this.description,
    this.userIds = const [],
    this.isPrivate = false,
  });

  final String theme;
  final String? description;
  final int datetimeStartSeconds;
  final int datetimeEndSeconds;
  final List<int> userIds;
  final bool isPrivate;

  Map<String, dynamic> toJson() {
    final body = <String, dynamic>{
      'theme': theme.trim(),
      'datetime_start': datetimeStartSeconds,
      'datetime_end': datetimeEndSeconds,
    };
    final descriptionValue = description?.trim();
    if (descriptionValue != null && descriptionValue.isNotEmpty) {
      body['description'] = descriptionValue;
    }
    if (userIds.isNotEmpty) {
      body['users'] = userIds;
    }
    if (isPrivate) {
      body['is_private'] = true;
    }
    return body;
  }
}
