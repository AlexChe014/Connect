/// Тело запроса `PATCH /api/chat/{chat}`.
class UpdateChatRequest {
  const UpdateChatRequest({
    this.title,
    this.description,
  });

  final String? title;
  final String? description;

  Map<String, dynamic> toJson() {
    final body = <String, dynamic>{};

    final titleValue = title?.trim();
    if (titleValue != null) {
      body['title'] = titleValue;
    }

    if (description != null) {
      body['description'] = description!.trim();
    }

    return body;
  }
}
