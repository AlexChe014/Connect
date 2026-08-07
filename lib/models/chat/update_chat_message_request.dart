/// Тело запроса `PUT /api/chat/{chat}/messages/{message}`.
class UpdateChatMessageRequest {
  const UpdateChatMessageRequest({required this.text});

  final String text;

  Map<String, dynamic> toJson() => {'message': text.trim()};
}
