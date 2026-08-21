/// Ответ `POST /videoconference/create` и `GET /videoconference/get`.
class Videoconference {
  const Videoconference({
    required this.id,
    required this.url,
    this.topic,
  });

  final int id;
  final String url;
  final String? topic;

  factory Videoconference.fromJson(Map<String, dynamic> json) {
    final idRaw = json['id'];
    final id = idRaw is int
        ? idRaw
        : idRaw is num
            ? idRaw.toInt()
            : int.tryParse('$idRaw') ?? 0;
    return Videoconference(
      id: id,
      url: (json['url'] as String?)?.trim() ?? '',
      topic: (json['topic'] as String?)?.trim(),
    );
  }
}
