import 'dart:math' as math;

import 'package:connect/config/app_theme.dart';
import 'package:connect/models/chat/chat_file.dart';
import 'package:connect/services/chat_file_downloads.dart';
import 'package:connect/services/chat_voice_player.dart';
import 'package:connect/utils/chat_voice_note.dart';
import 'package:flutter/cupertino.dart';

/// Голосовое в пузыре: кнопка, волна с прогрессом, время и скорость.
class ChatVoiceMessage extends StatelessWidget {
  const ChatVoiceMessage({
    super.key,
    required this.file,
    required this.note,
    required this.isOutgoing,
    required this.onBubble,
  });

  final ChatFile file;
  final ChatVoiceNote note;
  final bool isOutgoing;

  /// Цвет текста на пузыре.
  final Color onBubble;

  static const double _waveWidth = 150;
  static const double _waveHeight = 26;

  static String formatDuration(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = ChatVoicePlayer.instance;
    final buttonColor = isOutgoing
        ? CupertinoColors.white
        : AppColors.outgoingBubble;
    final iconColor = isOutgoing
        ? AppColors.outgoingBubble
        : CupertinoColors.white;

    return ValueListenableBuilder<ChatVoicePlayback?>(
      valueListenable: player.current,
      builder: (context, playback, _) {
        final active = playback?.fileId == file.id ? playback : null;
        final total = active != null && active.duration > Duration.zero
            ? active.duration
            : note.duration;
        final progress = active == null || total <= Duration.zero
            ? 0.0
            : (active.position.inMilliseconds / total.inMilliseconds).clamp(
                0.0,
                1.0,
              );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => player.toggle(file),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: buttonColor,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: active?.loading == true
                      ? _LoadingIndicator(file: file, color: iconColor)
                      : Icon(
                          active?.playing == true
                              ? CupertinoIcons.pause_fill
                              : CupertinoIcons.play_fill,
                          size: 20,
                          color: iconColor,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => player.seekFraction(
                      file.id,
                      d.localPosition.dx / _waveWidth,
                    ),
                    onHorizontalDragUpdate: (d) => player.seekFraction(
                      file.id,
                      d.localPosition.dx / _waveWidth,
                    ),
                    child: CustomPaint(
                      size: const Size(_waveWidth, _waveHeight),
                      painter: _WaveformPainter(
                        levels: note.levels,
                        progress: progress,
                        played: onBubble,
                        pending: onBubble.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatDuration(
                          active != null && active.position > Duration.zero
                              ? active.position
                              : total,
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: onBubble.withValues(alpha: 0.75),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (active != null) ...[
                        const SizedBox(width: 8),
                        _SpeedChip(color: onBubble),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator({required this.file, required this.color});

  final ChatFile file;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatFileDownloadProgress?>(
      valueListenable: ChatFileDownloads.instance.progressOf(file.id),
      builder: (context, progress, _) {
        final fraction = progress?.fraction;
        return SizedBox(
          width: 22,
          height: 22,
          child: fraction == null
              ? CupertinoActivityIndicator(radius: 9, color: color)
              : CustomPaint(
                  painter: _RingPainter(fraction: fraction, color: color),
                ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Offset.zero & size,
      -math.pi / 2,
      2 * math.pi * math.max(fraction, 0.04),
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color;
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final player = ChatVoicePlayer.instance;
    return ValueListenableBuilder<double>(
      valueListenable: player.speed,
      builder: (context, speed, _) => GestureDetector(
        onTap: player.cycleSpeed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${speed == speed.roundToDouble() ? speed.toInt() : speed}×',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.levels,
    required this.progress,
    required this.played,
    required this.pending,
  });

  final List<double> levels;
  final double progress;
  final Color played;
  final Color pending;

  static const double _barWidth = 2.5;
  static const double _gap = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final count = (size.width / (_barWidth + _gap)).floor();
    final bars = levels.isEmpty
        ? List<double>.filled(count, 0.15)
        : _stretch(ChatVoiceNote.resample(levels, count), count);
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < bars.length; i++) {
      final x = i * (_barWidth + _gap) + _barWidth / 2;
      final h = math.max(_barWidth, bars[i] * size.height);
      paint
        ..color = (i + 0.5) / bars.length <= progress ? played : pending
        ..strokeWidth = _barWidth;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2 + _barWidth / 2),
        Offset(x, (size.height + h) / 2 - _barWidth / 2),
        paint,
      );
    }
  }

  /// Короткую волну растягиваем на всю ширину, повторяя значения.
  static List<double> _stretch(List<double> values, int count) {
    if (values.length >= count || values.isEmpty) return values;
    return [for (var i = 0; i < count; i++) values[i * values.length ~/ count]];
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.levels != levels ||
      old.played != played ||
      old.pending != pending;
}
