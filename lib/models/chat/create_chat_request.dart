/// Тело запроса `POST /api/chat`.
class CreateChatRequest {
  const CreateChatRequest({
    this.title,
    this.description,
    this.isGroup = false,
    required this.userIds,
    this.type,
  });

  final String? title;
  final String? description;
  final bool isGroup;
  final List<int> userIds;
  final String? type;

  Map<String, dynamic> toJson() {
    final body = <String, dynamic>{
      'user_ids': userIds,
    };

    final titleValue = title?.trim();
    if (titleValue != null && titleValue.isNotEmpty) {
      body['title'] = titleValue;
    }

    return body;
  }
}
