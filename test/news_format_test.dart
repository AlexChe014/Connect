import 'package:connect/models/news_item.dart';
import 'package:connect/utils/html_text_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HtmlTextUtils.compactParagraphs', () {
    test('убирает пустые абзацы редактора портала', () {
      const html =
          '<p>Гулия, С днем Рождения!&nbsp;</p><p><br></p>'
          '<p>Ты не просто руководитель</p><p><br/></p><p>&nbsp;</p>'
          '<p>Будь счастлива</p>';
      expect(
        HtmlTextUtils.compactParagraphs(html),
        '<p>Гулия, С днем Рождения!</p><p>Ты не просто руководитель</p>'
        '<p>Будь счастлива</p>',
      );
    });

    test('не трогает абзацы с текстом и заголовки', () {
      const html = '<p>Текст <strong>жирный</strong></p><h3>Раздел</h3>';
      expect(HtmlTextUtils.compactParagraphs(html), html);
    });
  });

  group('HtmlTextUtils.toParagraphText', () {
    test('абзацы — с новой строки, без пустых строк', () {
      const html =
          '<p>Фариз, С днем Рождения!</p><p><br></p>'
          '<p>Желаем роста</p><h3>💬 Стикеры</h3><p>Теперь можно</p>';
      expect(
        HtmlTextUtils.toParagraphText(html),
        'Фариз, С днем Рождения!\nЖелаем роста\n💬 Стикеры\nТеперь можно',
      );
    });

    test('обычный текст возвращает как есть', () {
      expect(
        HtmlTextUtils.toParagraphText('Привет &amp; пока'),
        'Привет & пока',
      );
    });
  });

  group('NewsItem.fromJson', () {
    Map<String, dynamic> json() => {
      'id': 52,
      'title': 'PWA',
      'text': '<p>Текст</p>',
      'created_at': '06.10.2026',
      'publish_at': 1792558800,
      'documents': [
        {
          'id': 3138,
          'name': 'Инструкция для сохранения PWA',
          'file_name': 'Инструкция-для-сохранения-PWA.pdf',
          'mime_type': 'application/pdf',
          'size': 4606380,
          'original_url':
              'http://10.5.10.63:9000/test/3138/Инструкция-для-сохранения-PWA.pdf',
          'preview_url': '',
        },
        {'id': 1, 'name': 'без ссылки'},
      ],
    };

    test('дата — время публикации, а не создания', () {
      final news = NewsItem.fromJson(json());
      expect(news.date, DateTime.fromMillisecondsSinceEpoch(1792558800 * 1000));
    });

    test('без publish_at — дата создания', () {
      final news = NewsItem.fromJson(json()..remove('publish_at'));
      expect(news.date, DateTime(2026, 10, 6));
    });

    test('разбирает файлы поста, файлы без ссылки пропускает', () {
      final news = NewsItem.fromJson(json());
      expect(news.documents, hasLength(1));
      final document = news.documents.single;
      expect(document.name, 'Инструкция-для-сохранения-PWA.pdf');
      expect(document.mimeType, 'application/pdf');
      expect(document.size, 4606380);
      expect(document.url, isNot(contains('10.5.10.63')));
    });
  });
}
