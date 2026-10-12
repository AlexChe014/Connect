import 'package:connect/utils/html_text_utils.dart';
import 'package:connect/utils/media_url_utils.dart';

class NewsItem {
  final String id;
  final String title;
  final String content;
  final String contentHtml;
  final DateTime date;
  final String? imageUrl;
  final List<String> imageUrls;
  final int likesCount;
  final int viewsCount;
  final bool isLiked;
  final String? myReaction;

  /// Реакции на пост, сгруппированные по эмодзи (поле `reactions`).
  final List<NewsReaction> reactions;
  final bool isViewed;
  final bool isPinned;
  final NewsAuthor? author;
  final List<NewsAuthor> likers;
  final List<NewsAuthor> viewers;

  const NewsItem({
    required this.id,
    required this.title,
    required this.content,
    this.contentHtml = '',
    required this.date,
    this.imageUrl,
    this.imageUrls = const [],
    this.likesCount = 0,
    this.viewsCount = 0,
    this.isLiked = false,
    this.myReaction,
    this.reactions = const [],
    this.isViewed = false,
    this.isPinned = false,
    this.author,
    this.likers = const [],
    this.viewers = const [],
  });

  NewsItem copyWith({
    String? id,
    String? title,
    String? content,
    String? contentHtml,
    DateTime? date,
    String? imageUrl,
    List<String>? imageUrls,
    int? likesCount,
    int? viewsCount,
    bool? isLiked,
    String? myReaction,
    bool clearReaction = false,
    List<NewsReaction>? reactions,
    bool? isViewed,
    bool? isPinned,
    NewsAuthor? author,
    List<NewsAuthor>? likers,
    List<NewsAuthor>? viewers,
  }) {
    return NewsItem(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      contentHtml: contentHtml ?? this.contentHtml,
      date: date ?? this.date,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      likesCount: likesCount ?? this.likesCount,
      viewsCount: viewsCount ?? this.viewsCount,
      isLiked: isLiked ?? this.isLiked,
      myReaction: clearReaction ? null : (myReaction ?? this.myReaction),
      reactions: reactions ?? this.reactions,
      isViewed: isViewed ?? this.isViewed,
      isPinned: isPinned ?? this.isPinned,
      author: author ?? this.author,
      likers: likers ?? this.likers,
      viewers: viewers ?? this.viewers,
    );
  }

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId == null ? '' : rawId.toString();

    final title = (json['title'] as String?)?.trim() ?? '';

    final rawText = (json['text'] as String?) ?? (json['content'] as String?) ?? '';
    final content = HtmlTextUtils.toPlainText(rawText).trim();
    final contentHtml = rawText.trim();

    final rawDate = (json['created_at'] as String?) ?? (json['date'] as String?) ?? '';
    final date = _parseBackendDate(rawDate) ?? DateTime.now();

    final imageUrls = <String>[];
    final pics = json['pictures'] ?? json['media'];
    if (pics is List) {
      for (final pic in pics) {
        final normalized = MediaUrlUtils.normalizeFirstUrl(pic);
        if (normalized != null && normalized.isNotEmpty) {
          imageUrls.add(normalized);
        }
      }
    } else {
      final single = MediaUrlUtils.normalizeFirstUrl(pics);
      if (single != null && single.isNotEmpty) {
        imageUrls.add(single);
      }
    }
    final imageUrl = imageUrls.isEmpty ? null : imageUrls.first;

    final likesRaw = json['likes_count'] ?? json['likes'] ?? json['like_count'] ?? json['likesCount'];
    final viewsRaw = json['views_count'] ?? json['views'] ?? json['view_count'] ?? json['viewsCount'];

    final likers = _parseAuthors(
      json['liked_users'] ??
          json['likes_users'] ??
          json['likers'] ??
          json['liked'] ??
          (likesRaw is List ? likesRaw : null),
    );
    final viewers = _parseAuthors(
      json['viewed_users'] ??
          json['views_users'] ??
          json['viewers'] ??
          json['viewed'] ??
          (viewsRaw is List ? viewsRaw : null),
    );

    final likesCount = likesRaw is List
        ? likers.length
        : _parseInt(likesRaw);
    final viewsCount = viewsRaw is List
        ? viewers.length
        : _parseInt(viewsRaw);

    NewsAuthor? author;
    final rawAuthor = json['author'];
    if (rawAuthor is Map<String, dynamic>) {
      author = NewsAuthor.fromJson(rawAuthor);
    } else if (rawAuthor is Map) {
      author = NewsAuthor.fromJson(Map<String, dynamic>.from(rawAuthor));
    }

    return NewsItem(
      id: id,
      title: title,
      content: content,
      contentHtml: contentHtml,
      date: date,
      imageUrl: imageUrl,
      imageUrls: imageUrls,
      likesCount: likesCount,
      viewsCount: viewsCount,
      isLiked: _parseIsLiked(json),
      myReaction: _parseMyReaction(json),
      reactions: _parseReactions(json['reactions']),
      isViewed: _parseBool(json['is_viewed'] ?? json['isViewed']),
      isPinned: _parseBool(json['is_pinned'] ?? json['isPinned']),
      author: author,
      likers: likers,
      viewers: viewers,
    );
  }

  /// Общее число реакций на пост.
  int get reactionsCount => reactions.fold(0, (sum, r) => sum + r.count);

  /// Локально применяет реакцию текущего пользователя так же, как сервер:
  /// `null` снимает реакцию, иначе ставит/заменяет её на [emoji].
  /// [me] добавляется/убирается из списков `users` соответствующих групп.
  NewsItem withMyReaction(String? emoji, {NewsAuthor? me}) {
    final previous = myReaction;
    if (previous == emoji) return this;

    final groups = <NewsReaction>[];
    var added = false;
    for (final r in reactions) {
      var group = r;
      if (previous != null && r.emoji == previous) {
        group = group.withoutUser(me);
      }
      if (emoji != null && r.emoji == emoji) {
        group = group.withUser(me);
        added = true;
      }
      if (group.count > 0) groups.add(group);
    }
    if (emoji != null && !added) {
      groups.add(
        NewsReaction(emoji: emoji, count: 1, users: [?me]),
      );
    }

    return emoji == null
        ? copyWith(clearReaction: true, reactions: groups)
        : copyWith(myReaction: emoji, reactions: groups);
  }

  static List<NewsReaction> _parseReactions(Object? raw) {
    if (raw is! List) return const [];
    final out = <NewsReaction>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final reaction = NewsReaction.fromJson(Map<String, dynamic>.from(e));
      if (reaction.emoji.isNotEmpty && reaction.count > 0) out.add(reaction);
    }
    return out;
  }

  static List<NewsAuthor> _parseAuthors(Object? raw) {
    if (raw is! List) return const [];
    final out = <NewsAuthor>[];
    for (final e in raw) {
      if (e is Map<String, dynamic>) {
        out.add(NewsAuthor.fromJson(e));
      } else if (e is Map) {
        out.add(NewsAuthor.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return out;
  }

  static DateTime? _parseBackendDate(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return null;

    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;

    final parts = trimmed.split('.');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  static int _parseInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }

  static bool _parseIsLiked(Map<String, dynamic> json) {
    for (final key in [
      'is_liked',
      'isLiked',
      'has_like',
      'has_liked',
      'user_liked',
    ]) {
      if (!json.containsKey(key)) continue;
      final v = json[key];
      if (v is Map) return v.isNotEmpty;
      if (v is List) return v.isNotEmpty;
      if (v is bool) return v;
      if (v is num) return v == 1;
      final s = v.toString().trim().toLowerCase();
      if (s == 'true' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no' || s.isEmpty) return false;
      if (s == '1') return true;
    }
    return false;
  }

  /// Реакция текущего пользователя на пост — приходит в поле `user_reaction`
  /// (см. `NewsResource::toArray` на бэкенде).
  static String? _parseMyReaction(Map<String, dynamic> json) {
    for (final key in ['user_reaction', 'my_reaction', 'reaction']) {
      final v = json[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is Map) {
        final emoji = v['emoji'];
        if (emoji is String && emoji.trim().isNotEmpty) return emoji.trim();
      }
    }
    return null;
  }

  static bool _parseBool(Object? v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }
}

/// Группа реакций с одним эмодзи: `{ emoji, count, users }`.
class NewsReaction {
  final String emoji;
  final int count;
  final List<NewsAuthor> users;

  const NewsReaction({
    required this.emoji,
    required this.count,
    this.users = const [],
  });

  factory NewsReaction.fromJson(Map<String, dynamic> json) {
    final users = NewsItem._parseAuthors(json['users']);
    final rawCount = json['count'];
    return NewsReaction(
      emoji: json['emoji']?.toString().trim() ?? '',
      count: rawCount == null ? users.length : NewsItem._parseInt(rawCount),
      users: users,
    );
  }

  NewsReaction withUser(NewsAuthor? user) => NewsReaction(
    emoji: emoji,
    count: count + 1,
    users: [
      ?user,
      ...users.where((u) => user == null || u.id != user.id),
    ],
  );

  NewsReaction withoutUser(NewsAuthor? user) => NewsReaction(
    emoji: emoji,
    count: count > 0 ? count - 1 : 0,
    users: user == null ? users : users.where((u) => u.id != user.id).toList(),
  );
}

class NewsAuthor {
  final String id;
  final String fullName;
  final String? avatarUrl;

  const NewsAuthor({
    required this.id,
    required this.fullName,
    this.avatarUrl,
  });

  factory NewsAuthor.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId == null ? '' : rawId.toString();

    final surname = (json['surname'] as String?)?.trim();
    final name = (json['name'] as String?)?.trim();

    final parts = <String>[
      if (surname != null && surname.isNotEmpty) surname,
      if (name != null && name.isNotEmpty) name,
    ];

    return NewsAuthor(
      id: id,
      fullName: parts.isEmpty ? 'Автор' : parts.join(' '),
      avatarUrl: MediaUrlUtils.normalizeFirstUrl(json['media']),
    );
  }
}
