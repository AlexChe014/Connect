import 'dart:async';
import 'dart:io';

import 'package:connect/services/chat_voice_player.dart';
import 'package:connect/utils/chat_voice_note.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Записанное голосовое, готовое к отправке.
@immutable
class ChatVoiceRecording {
  const ChatVoiceRecording({
    required this.file,
    required this.duration,
    required this.levels,
  });

  final File file;
  final Duration duration;
  final List<double> levels;

  String get fileName =>
      ChatVoiceNote.fileName(duration: duration, levels: levels);
}

/// Запись голосовых в AAC/m4a: этот формат играют и iOS, и Android,
/// и браузеры на портале.
class ChatVoiceRecorder {
  ChatVoiceRecorder._();
  static final ChatVoiceRecorder instance = ChatVoiceRecorder._();

  /// Короче — это случайное касание, а не сообщение.
  static const Duration minDuration = Duration(milliseconds: 800);

  /// Лимит загрузки 10 МБ; при 48 кбит/с это ~25 минут, берём с запасом.
  static const Duration maxDuration = Duration(minutes: 15);

  static const Duration _sampleInterval = Duration(milliseconds: 100);

  AudioRecorder? _recorder;
  StreamSubscription<Amplitude>? _amplitudeSub;
  Timer? _ticker;
  DateTime? _startedAt;
  String? _path;
  final List<double> _levels = [];

  /// Сколько уже записано; `null` — запись не идёт.
  final ValueNotifier<Duration?> elapsed = ValueNotifier(null);

  /// Текущая громкость 0…1 — для пульсации индикатора.
  final ValueNotifier<double> level = ValueNotifier(0);

  bool get isRecording => elapsed.value != null;

  /// `false` — нет доступа к микрофону или запись не запустилась.
  Future<bool> start() async {
    if (isRecording) return true;
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) return false;

    await ChatVoicePlayer.instance.stop();
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 48000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
    } catch (e) {
      debugPrint('ChatVoiceRecorder start: $e');
      return false;
    }

    _path = path;
    _levels.clear();
    _startedAt = DateTime.now();
    elapsed.value = Duration.zero;
    _amplitudeSub = recorder.onAmplitudeChanged(_sampleInterval).listen((a) {
      final v = ChatVoiceNote.levelFromDbfs(a.current);
      _levels.add(v);
      level.value = v;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final started = _startedAt;
      if (started == null) return;
      final d = DateTime.now().difference(started);
      elapsed.value = d;
      if (d >= maxDuration) unawaited(stop());
    });
    return true;
  }

  /// Останавливает запись; `null` — слишком коротко или сбой.
  Future<ChatVoiceRecording?> stop() async {
    if (!isRecording) return null;
    final duration = DateTime.now().difference(_startedAt!);
    final levels = List<double>.of(_levels);
    final path = await _finish();
    final recorded = path ?? _path;
    _path = null;
    if (recorded == null) return null;
    final file = File(recorded);
    if (duration < minDuration || !await file.exists()) {
      await _deleteQuietly(file);
      return null;
    }
    return ChatVoiceRecording(file: file, duration: duration, levels: levels);
  }

  /// Отмена свайпом: файл стирается.
  Future<void> cancel() async {
    if (!isRecording) return;
    final path = await _finish();
    final recorded = path ?? _path;
    _path = null;
    if (recorded != null) await _deleteQuietly(File(recorded));
  }

  Future<String?> _finish() async {
    _ticker?.cancel();
    _ticker = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _startedAt = null;
    elapsed.value = null;
    level.value = 0;
    try {
      return await _recorder?.stop();
    } catch (e) {
      debugPrint('ChatVoiceRecorder stop: $e');
      return null;
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Временная папка — ОС почистит сама.
    }
  }
}
