import 'package:connect/models/chat/chat_file.dart';
import 'package:connect/utils/chat_voice_note.dart';
import 'package:flutter_test/flutter_test.dart';

ChatFile _file(String name, String mime) => ChatFile(
  id: 1,
  filename: 'x',
  originalName: name,
  mimeType: mime,
  size: 100,
);

void main() {
  test('разбирает имя голосового портала', () {
    final note = ChatVoiceNote.fromFileName('voice-12-0fv.webm')!;
    expect(note.duration, const Duration(seconds: 12));
    expect(note.levels, [0, 15 / 31, 1]);
  });

  test('голосовое без волны тоже распознаётся', () {
    expect(ChatVoiceNote.fromFileName('voice-3-.m4a')?.levels, isEmpty);
  });

  test('обычные файлы не считаются голосовыми', () {
    expect(ChatVoiceNote.fromFileName('voice.webm'), isNull);
    expect(ChatVoiceNote.fromFileName('voice-12-zz.webm'), isNull);
    expect(ChatVoiceNote.fromFileName('voice-12-ab.mp3'), isNull);
  });

  test('webm-голосовое — не видео', () {
    final f = _file('voice-5-abc.webm', 'audio/webm');
    expect(f.isVoice, isTrue);
    expect(f.isVideo, isFalse);
    expect(_file('clip.webm', 'video/webm').isVideo, isTrue);
  });

  test('имя для отправки читается обратно', () {
    final levels = List<double>.generate(300, (i) => (i % 10) / 9);
    final name = ChatVoiceNote.fileName(
      duration: const Duration(milliseconds: 12400),
      levels: levels,
    );
    final note = ChatVoiceNote.fromFileName(name)!;
    expect(name, startsWith('voice-12-'));
    expect(name, endsWith('.m4a'));
    expect(note.levels.length, ChatVoiceNote.maxLevels);
    expect(ChatVoiceNote.mimeForFileName(name), 'audio/mp4');
  });

  test('короткая запись — минимум 1 секунда', () {
    expect(
      ChatVoiceNote.fileName(duration: Duration.zero, levels: const []),
      'voice-1-.m4a',
    );
  });
}
