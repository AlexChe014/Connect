/// Тело запроса `POST /api/chat/{chat}/members`.
class AddChatMembersRequest {
  const AddChatMembersRequest({required this.userIds});

  final List<int> userIds;

  Map<String, dynamic> toJson() => {'user_ids': userIds};
}
