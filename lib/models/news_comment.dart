import 'package:connect/models/news_item.dart';

class NewsComment {
  final String id;
  final String text;
  final String newsId;
  final DateTime date;
  final NewsAuthor? author;

  const NewsComment({
    required this.id,
    required this.text,
    required this.newsId,
    required this.date,
    this.author,
  });

  factory NewsComment.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId == null ? '' : rawId.toString();

    final text = ((json['text'] as String?) ?? '').trim();

    final rawNews = json['news'] ?? json['news_id'];
    final newsId = rawNews == null ? '' : rawNews.toString();

    final rawDate = (json['created_at'] as String?) ?? (json['date'] as String?) ?? '';
    final date = _parseBackendDate(rawDate) ?? DateTime.now();

    NewsAuthor? author;
    final rawAuthor = json['author'];
    if (rawAuthor is Map<String, dynamic>) {
      author = NewsAuthor.fromJson(rawAuthor);
    } else if (rawAuthor is Map) {
      author = NewsAuthor.fromJson(Map<String, dynamic>.from(rawAuthor));
    }

    return NewsComment(
      id: id,
      text: text,
      newsId: newsId,
      date: date,
      author: author,
    );
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
}
