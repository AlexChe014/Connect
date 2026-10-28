import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:connect/models/chat/chat_file.dart';
import 'package:connect/services/chat_file_downloads.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Что сейчас играет: одно голосовое на всё приложение.
@immutable
class ChatVoicePlayback {
  const ChatVoicePlayback({
    required this.fileId,
    this.playing = false,
    this.loading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  final int fileId;
  final bool playing;

  /// Файл скачивается или открывается.
  final bool loading;
  final Duration position;

  /// Длина по данным плеера; `zero`, пока файл не открыт.
  final Duration duration;

  ChatVoicePlayback copyWith({
    bool? playing,
    bool? loading,
    Duration? position,
    Duration? duration,
  }) => ChatVoicePlayback(
    fileId: fileId,
    playing: playing ?? this.playing,
    loading: loading ?? this.loading,
    position: position ?? this.position,
    duration: duration ?? this.duration,
  );
}

/// Проигрывание голосовых через libmpv (`media_kit`): он, в отличие от
/// AVPlayer, умеет webm/opus, в котором пишет голосовые портал в Chrome.
class ChatVoicePlayer {
  ChatVoicePlayer._();
  static final ChatVoicePlayer instance = ChatVoicePlayer._();

  static const List<double> speeds = [1, 1.5, 2];

  /// `null` — ничего не выбрано.
  final ValueNotifier<ChatVoicePlayback?> current = ValueNotifier(null);

  /// Скорость общая для всех голосовых, как в Telegram.
  final ValueNotifier<double> speed = ValueNotifier(1);

  Player? _player;
  final List<StreamSubscription<Object?>> _subs = [];

  /// Защита от гонки: пока качался один файл, нажали другой.
  int _openGeneration = 0;

  Player _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = Player();
    _subs.addAll([
      player.stream.playing.listen((playing) {
        _update((p) => p.copyWith(playing: playing));
      }),
      player.stream.position.listen((position) {
        _update((p) => p.copyWith(position: position));
      }),
      player.stream.duration.listen((duration) {
        if (duration > Duration.zero) {
          _update((p) => p.copyWith(duration: duration));
        }
      }),
      player.stream.completed.listen((completed) {
        if (completed) unawaited(stop());
      }),
      player.stream.error.listen((error) {
        debugPrint('ChatVoicePlayer error: $error');
      }),
    ]);
    _player = player;
    return player;
  }

  void _update(ChatVoicePlayback Function(ChatVoicePlayback) change) {
    final p = current.value;
    if (p != null) current.value = change(p);
  }

  bool isCurrent(int fileId) => current.value?.fileId == fileId;

  /// Играть или поставить на паузу [file]; другое голосовое останавливается.
  Future<void> toggle(ChatFile file) async {
    final p = current.value;
    final player = _player;
    if (p != null && p.fileId == file.id && player != null && !p.loading) {
      await player.playOrPause();
      return;
    }
    await _open(file);
  }

  Future<void> _open(ChatFile file) async {
    final generation = ++_openGeneration;
    await _player?.stop();
    current.value = ChatVoicePlayback(fileId: file.id, loading: true);

    final local = await ChatFileDownloads.instance.download(file);
    if (generation != _openGeneration) return;
    if (local == null) {
      current.value = null; // Скачивание отменили.
      return;
    }

    await _activateSession();
    final player = _ensurePlayer();
    await player.setRate(speed.value);
    await player.open(Media(local.path));
    if (generation != _openGeneration) return;
    _update((p) => p.copyWith(loading: false));
  }

  /// Перемотка по доле 0…1 текущего голосового.
  Future<void> seekFraction(int fileId, double fraction) async {
    final p = current.value;
    final player = _player;
    if (p == null || p.fileId != fileId || player == null) return;
    if (p.duration <= Duration.zero) return;
    await player.seek(p.duration * fraction.clamp(0.0, 1.0));
  }

  Future<void> cycleSpeed() async {
    final i = speeds.indexOf(speed.value);
    speed.value = speeds[(i + 1) % speeds.length];
    await _player?.setRate(speed.value);
  }

  Future<void> stop() async {
    _openGeneration++;
    current.value = null;
    await _player?.stop();
    await _deactivateSession();
  }

  /// Выход из аккаунта или начало звонка.
  Future<void> reset() async {
    await stop();
    speed.value = 1;
  }

  /// Голос — «озвучка»: играет при выключенном звуке и приглушает музыку.
  Future<void> _activateSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      await session.setActive(true);
    } catch (e) {
      debugPrint('ChatVoicePlayer session: $e');
    }
  }

  Future<void> _deactivateSession() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {
      // Сессию мог забрать звонок — это нормально.
    }
  }
}
