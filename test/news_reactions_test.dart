import 'package:connect/models/news_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const me = NewsAuthor(id: '1', fullName: 'Иванов Иван');

  NewsItem parse(Map<String, dynamic> extra) => NewsItem.fromJson({
    'id': 10,
    'title': 'Новость',
    'text': '',
    'created_at': '2026-10-09T10:00:00Z',
    ...extra,
  });

  test('парсит user_reaction и сгруппированные reactions', () {
    final news = parse({
      'user_reaction': '🔥',
      'reactions': [
        {
          'emoji': '🔥',
          'count': 3,
          'users': [
            {'id': 1, 'name': 'Иван', 'surname': 'Иванов'},
          ],
        },
        {'emoji': '👍', 'count': 1, 'users': []},
      ],
    });

    expect(news.myReaction, '🔥');
    expect(news.reactions.map((r) => r.emoji), ['🔥', '👍']);
    expect(news.reactions.first.count, 3);
    expect(news.reactions.first.users.single.fullName, 'Иванов Иван');
    expect(news.reactionsCount, 4);
  });

  test('без реакций — пустой список и null', () {
    final news = parse({'user_reaction': null});
    expect(news.myReaction, isNull);
    expect(news.reactions, isEmpty);
  });

  test('created: новая группа с текущим пользователем', () {
    final news = parse({}).withMyReaction('🔥', me: me);
    expect(news.myReaction, '🔥');
    expect(news.reactions.single.count, 1);
    expect(news.reactions.single.users.single.id, '1');
  });

  test('updated: реакция переносится в другую группу', () {
    final news = parse({
      'user_reaction': '👍',
      'reactions': [
        {
          'emoji': '👍',
          'count': 1,
          'users': [
            {'id': 1, 'name': 'Иван'},
          ],
        },
        {'emoji': '🔥', 'count': 2, 'users': []},
      ],
    }).withMyReaction('🔥', me: me);

    expect(news.myReaction, '🔥');
    expect(news.reactions.single.emoji, '🔥');
    expect(news.reactions.single.count, 3);
    expect(news.reactions.single.users.first.id, '1');
  });

  test('removed: реакция снимается', () {
    final news = parse({
      'user_reaction': '🔥',
      'reactions': [
        {
          'emoji': '🔥',
          'count': 2,
          'users': [
            {'id': 1, 'name': 'Иван'},
            {'id': 2, 'name': 'Пётр'},
          ],
        },
      ],
    }).withMyReaction(null, me: me);

    expect(news.myReaction, isNull);
    expect(news.reactions.single.count, 1);
    expect(news.reactions.single.users.single.id, '2');
  });
}
