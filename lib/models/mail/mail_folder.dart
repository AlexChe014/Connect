class MailFolder {
  final int id;
  final String name;
  final String? originalName;
  final int? unreadCount;
  final int? totalCount;

  const MailFolder({
    required this.id,
    required this.name,
    this.originalName,
    this.unreadCount,
    this.totalCount,
  });

  bool get isInbox {
    final original = originalName?.trim().toLowerCase();
    if (original == 'inbox') return true;
    final n = name.trim().toLowerCase();
    return n == 'inbox' || n == 'входящие';
  }

  bool get isSent {
    return _matches(const [
      'sent',
      'sent items',
      'sent messages',
      'отправленные',
    ]);
  }

  bool get isDrafts {
    return _matches(const ['drafts', 'draft', 'черновики']);
  }

  bool get isTrash {
    return _matches(const [
      'trash',
      'deleted',
      'deleted items',
      'bin',
      'корзина',
      'удаленные',
      'удалённые',
    ]);
  }

  bool get isSpam {
    return _matches(const ['spam', 'junk', 'junk e-mail', 'спам']);
  }

  bool get isArchive {
    return _matches(const ['archive', 'all mail', 'архив']);
  }

  bool _matches(List<String> candidates) {
    final original = originalName?.trim().toLowerCase();
    final n = name.trim().toLowerCase();
    for (final candidate in candidates) {
      if (original == candidate || n == candidate) return true;
    }
    return false;
  }

  factory MailFolder.fromJson(Map<String, dynamic> json) {
    final originalName = _optionalString(json, [
      'original_name',
      'path',
      'full_name',
    ]);
    return MailFolder(
      id: _parseInt(
            json['id'] ?? json['folder_id'] ?? json['uid'] ?? json['mailbox_id'],
          ) ??
          0,
      name: _optionalString(json, [
            'custom_name',
            'name',
            'title',
            'folder',
            'label',
            'mailbox',
            'original_name',
          ]) ??
          originalName ??
          'Папка',
      originalName: originalName,
      unreadCount: _parseInt(
        json['unread'] ?? json['unread_count'] ?? json['unseen'],
      ),
      totalCount: _parseInt(
        json['emails_count'] ??
            json['total'] ??
            json['total_count'] ??
            json['count'],
      ),
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
