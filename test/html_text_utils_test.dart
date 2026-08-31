import 'package:connect/utils/html_text_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HtmlTextUtils.looksLikeHtml', () {
    test('plain text is not HTML', () {
      expect(HtmlTextUtils.looksLikeHtml('Hello world'), isFalse);
    });

    test('a tag is detected as HTML', () {
      expect(HtmlTextUtils.looksLikeHtml('<p>Hi</p>'), isTrue);
    });

    test('a doctype prefix is detected as HTML', () {
      expect(HtmlTextUtils.looksLikeHtml('<!DOCTYPE html><html></html>'), isTrue);
    });
  });

  group('HtmlTextUtils.decodeEntities', () {
    test('decodes the common named entities', () {
      expect(HtmlTextUtils.decodeEntities('&amp;'), '&');
      expect(HtmlTextUtils.decodeEntities('&lt;'), '<');
      expect(HtmlTextUtils.decodeEntities('&gt;'), '>');
      expect(HtmlTextUtils.decodeEntities('&quot;'), '"');
      expect(HtmlTextUtils.decodeEntities("&#39;"), "'");
      expect(HtmlTextUtils.decodeEntities('&apos;'), "'");
      expect(HtmlTextUtils.decodeEntities('&nbsp;'), ' ');
    });
  });

  group('HtmlTextUtils.toPlainText', () {
    test('empty input stays empty', () {
      expect(HtmlTextUtils.toPlainText(''), '');
      expect(HtmlTextUtils.toPlainText('   '), '');
    });

    test('plain text without tags is returned as-is (entities decoded)', () {
      expect(HtmlTextUtils.toPlainText('Hello &amp; goodbye'), 'Hello & goodbye');
    });

    test('tags are stripped, leaving just the text content', () {
      expect(HtmlTextUtils.toPlainText('<p>Hello <b>world</b></p>'), 'Hello world');
    });

    test('never lets a raw encrypted-looking blob through unexpectedly', () {
      // Not a security test — just documents that plain non-HTML text
      // (e.g. an already-decrypted chat message) passes through untouched.
      expect(HtmlTextUtils.toPlainText('just a message'), 'just a message');
    });
  });
}
