import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Голосовое сообщение в формате портала: файл
/// `voice-<секунды>-<волна>.(webm|ogg|m4a)`, где волна — до 96 символов
/// `0-9a-v`, по одному уровню громкости 0…31 на символ
/// (см. `POST /api/v2/chat/:chatId/voice` в Node-бэкенде).
@immutable
class ChatVoiceNote {
  const ChatVoiceNote({required this.duration, required this.levels});

  final Duration duration;

  /// Уровни громкости 0…1; может быть пустым — тогда рисуется ровная волна.
  final List<double> levels;

  static const int maxLevels = 96;
  static const int _maxLevel = 31;
  static const int _maxSeconds = 9999;

  static final RegExp _namePattern = RegExp(
    r'^voice-(\d{1,4})-([0-9a-v]{0,96})\.(webm|ogg|m4a)$',
  );

  static const Map<String, String> _mimeByExtension = {
    'webm': 'audio/webm',
    'ogg': 'audio/ogg',
    'm4a': 'audio/mp4',
  };

  /// `null` — это не голосовое, а обычный файл.
  static ChatVoiceNote? fromFileName(String name) {
    final match = _namePattern.firstMatch(name.trim().toLowerCase());
    if (match == null) return null;
    return ChatVoiceNote(
      duration: Duration(seconds: int.parse(match.group(1)!)),
      levels: [
        for (final ch in match.group(2)!.split(''))
          int.parse(ch, radix: 32) / _maxLevel,
      ],
    );
  }

  /// Mime для имени голосового или `null`, если имя не по шаблону.
  static String? mimeForFileName(String name) {
    final match = _namePattern.firstMatch(name.trim().toLowerCase());
    return match == null ? null : _mimeByExtension[match.group(3)];
  }

  /// Имя файла для отправки: [levels] (0…1) ужимаются до [maxLevels].
  static String fileName({
    required Duration duration,
    required List<double> levels,
    String extension = 'm4a',
  }) {
    final seconds = (duration.inMilliseconds / 1000).round().clamp(
      1,
      _maxSeconds,
    );
    final wave = resample(levels, maxLevels)
        .map((v) => (v.clamp(0.0, 1.0) * _maxLevel).round().toRadixString(32))
        .join();
    return 'voice-$seconds-$wave.$extension';
  }

  /// Сжимает или растягивает [levels] до [count] значений, по каждому
  /// отрезку берётся максимум — чтобы короткие всплески не пропадали.
  static List<double> resample(List<double> levels, int count) {
    if (levels.isEmpty || count <= 0) return const [];
    if (levels.length <= count) return List.of(levels);
    final out = <double>[];
    for (var i = 0; i < count; i++) {
      final start = (i * levels.length / count).floor();
      final end = math.max(
        start + 1,
        ((i + 1) * levels.length / count).floor(),
      );
      out.add(levels.sublist(start, end).reduce(math.max));
    }
    return out;
  }

  /// Громкость из dBFS (`record` отдаёт −160…0) в 0…1; тише −50 дБ — тишина.
  static double levelFromDbfs(double dbfs) {
    if (dbfs.isNaN || dbfs.isInfinite) return 0;
    return ((dbfs + 50) / 50).clamp(0.0, 1.0);
  }
}
