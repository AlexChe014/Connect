class MailFolder {
  final int id;
  final String name;
  final int? unreadCount;
  final int? totalCount;

  const MailFolder({
    required this.id,
    required this.name,
    this.unreadCount,
    this.totalCount,
  });

  factory MailFolder.fromJson(Map<String, dynamic> json) {
    return MailFolder(
      id: _parseInt(
        json['id'] ?? json['folder_id'] ?? json['uid'] ?? json['mailbox_id'],
      ) ??
          0,
      name: _optionalString(json, ['name', 'title', 'folder', 'label', 'mailbox']) ??
          'Папка',
      unreadCount: _parseInt(
        json['unread'] ?? json['unread_count'] ?? json['unseen'],
      ),
      totalCount: _parseInt(json['total'] ?? json['total_count'] ?? json['count']),
    );
  }

  static String? _optionalString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final v = json[key];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static int? _parseInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }
}
