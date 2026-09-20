class MailFolder {
  final int id;
  final String name;
  final String? originalName;
  final int? unreadCount;
  final int? totalCount;

  /// Уровень вложенности в дереве папок (0 — верхний уровень), проставляется
  /// при разборе ответа API из структуры `children`.
  final int depth;

  const MailFolder({
    required this.id,
    required this.name,
    this.originalName,
    this.unreadCount,
    this.totalCount,
    this.depth = 0,
  });

  MailFolder copyWithDepth(int depth) => MailFolder(
        id: id,
        name: name,
        originalName: originalName,
        unreadCount: unreadCount,
        totalCount: totalCount,
        depth: depth,
      );

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

  /// Служебные папки почтового сервера (контакты, календарь, задачи, RSS,
  /// журналы, «Ошибки синхронизации» и т.п.) — Exchange/групповые серверы
  /// отдают их как обычные IMAP-папки вперемешку с почтовыми, но пользователю
  /// в списке почты они не нужны. Совпадение ищется и по русским, и по
  /// английским названиям, т.к. локализация зависит от сервера.
  static const _hiddenSystemFolderKeywords = [
    'sync issues',
    'ошибки синхронизации',
    'conflicts',
    'конфликты',
    'local failures',
    'локальные ошибки',
    'server failures',
    'ошибки сервера',
    'contacts',
    'контакты',
    'deferred',
    'отложен',
    'rss feeds',
    'rss каналы',
    'rss subscriptions',
    'rss подписки',
    'journal',
    'журнал',
    'tasks',
    'задачи',
    'notes',
    'заметки',
    'scheduled',
    'запланировано',
    'archive',
    'архив',
    'calendar',
    'календарь',
  ];

  bool get isHiddenSystemFolder {
    if (isInbox || isSent || isDrafts || isTrash || isSpam) return false;
    final original = (originalName ?? '').trim().toLowerCase();
    final n = name.trim().toLowerCase();
    for (final keyword in _hiddenSystemFolderKeywords) {
      if (original.contains(keyword) || n.contains(keyword)) return true;
    }
    return false;
  }

  static final RegExp _inboxPrefix = RegExp(
    r'^inbox[\s./\\:>-]+',
    caseSensitive: false,
  );

  /// Имя папки для показа пользователю — без служебного префикса `INBOX`,
  /// которым некоторые IMAP-серверы (Exchange/Dovecot с точечной иерархией)
  /// предваряют имена всех вложенных папок (`INBOX.Отправленные`,
  /// `INBOX/Черновики`).
  String get displayName {
    if (isInbox) return name;
    final stripped = name.replaceFirst(_inboxPrefix, '');
    return stripped.trim().isEmpty ? name : stripped;
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
