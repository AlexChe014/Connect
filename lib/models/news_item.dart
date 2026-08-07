import 'package:connect/config/api_config.dart';

class NewsItem {
  final String id;
  final String title;
  final String content;
  final DateTime date;
  final String? imageUrl;
  final List<String> imageUrls;
  final int likesCount;
  final int viewsCount;
  final bool isLiked;
  final bool isViewed;
  final bool isPinned;
  final NewsAuthor? author;
  final List<NewsAuthor> likers;
  final List<NewsAuthor> viewers;

  const NewsItem({
    required this.id,
    required this.title,
    required this.content,
    required this.date,
    this.imageUrl,
    this.imageUrls = const [],
    this.likesCount = 0,
    this.viewsCount = 0,
    this.isLiked = false,
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
    DateTime? date,
    String? imageUrl,
    List<String>? imageUrls,
    int? likesCount,
    int? viewsCount,
    bool? isLiked,
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
      date: date ?? this.date,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      likesCount: likesCount ?? this.likesCount,
      viewsCount: viewsCount ?? this.viewsCount,
      isLiked: isLiked ?? this.isLiked,
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
    final content = _stripHtml(rawText).trim();

    final rawDate = (json['created_at'] as String?) ?? (json['date'] as String?) ?? '';
    final date = _parseBackendDate(rawDate) ?? DateTime.now();

    final imageUrls = <String>[];
    final pics = json['pictures'];
    if (pics is List) {
      for (final pic in pics) {
        if (pic is! Map) continue;
        final map = Map<String, dynamic>.from(pic);
        String? url = (map['preview_url'] as String?)?.trim();
        if (url == null || url.isEmpty) {
          url = (map['original_url'] as String?)?.trim();
        }
        final normalized = ApiConfig.normalizeFileUrl(url);
        if (normalized != null && normalized.isNotEmpty) {
          imageUrls.add(normalized);
        }
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
      date: date,
      imageUrl: imageUrl,
      imageUrls: imageUrls,
      likesCount: likesCount,
      viewsCount: viewsCount,
      isLiked: _parseBool(json['is_liked'] ?? json['isLiked']),
      isViewed: _parseBool(json['is_viewed'] ?? json['isViewed']),
      isPinned: _parseBool(json['is_pinned'] ?? json['isPinned']),
      author: author,
      likers: likers,
      viewers: viewers,
    );
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

  static String _stripHtml(String s) {
    return s.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  static int _parseInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }

  static bool _parseBool(Object? v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }
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

    final avatarUrl = ApiConfig.normalizeFileUrl(_extractMediaUrl(json['media']));

    return NewsAuthor(
      id: id,
      fullName: parts.isEmpty ? 'Автор' : parts.join(' '),
      avatarUrl: avatarUrl,
    );
  }

  static String? _extractMediaUrl(Object? media) {
    if (media == null) return null;
    if (media is String) return media.trim();
    if (media is Map<String, dynamic>) {
      final candidates = [
        media['url'],
        media['link'],
        media['path'],
        media['src'],
        media['preview_url'],
        media['original_url'],
      ];
      for (final c in candidates) {
        final s = c?.toString().trim();
        if (s != null && s.isNotEmpty) return s;
      }
    }
    return media.toString().trim().isEmpty ? null : media.toString().trim();
  }
}
