/// Тело запроса `PATCH /api/chat/{chat}/members/{user}`.
class UpdateChatMemberRequest {
  const UpdateChatMemberRequest({this.isAdmin});

  final bool? isAdmin;

  Map<String, dynamic> toJson() {
    final body = <String, dynamic>{};
    if (isAdmin != null) {
      body['is_admin'] = isAdmin;
    }
    return body;
  }
}
