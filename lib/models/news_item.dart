class NewsItem {
  final String id;
  final String title;
  final String content;
  final DateTime date;
  final String? imageUrl;

  const NewsItem({
    required this.id,
    required this.title,
    required this.content,
    required this.date,
    this.imageUrl,
  });

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    return NewsItem(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      imageUrl: json['imageUrl'] as String?,
    );
  }
}
