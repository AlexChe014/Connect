import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';

import '../config/app_theme.dart';
import '../config/connect_icons.dart';
import '../models/call_conference.dart';
import '../services/app_navigation_service.dart';
import '../services/jitsi_meeting_service.dart';
import 'call_glass.dart';
import 'chat_avatar.dart';

/// Экран звонка поверх всего приложения (кладётся в `MaterialApp.builder`
/// над Navigator).
///
/// Встроенный вид Jitsi живёт здесь всё время звонка и только меняет
/// размер: на весь экран — в карточке между шапкой и кнопками, свёрнут —
/// в перетаскиваемом окошке над приложением. Перенести его в другой
/// маршрут нельзя: platform view пересоздаётся, а с ним и вход в комнату.
class CallOverlayHost extends StatefulWidget {
  const CallOverlayHost({super.key});

  @override
  State<CallOverlayHost> createState() => _CallOverlayHostState();
}

enum _CallSheet { none, more, participants, audio }

class _CallOverlayHostState extends State<CallOverlayHost> {
  static const _miniSize = Size(108, 152);
  static const _miniMargin = 12.0;

  final JitsiMeetingService _service = JitsiMeetingService.instance;

  /// Один и тот же вид Jitsi при любой раскладке.
  final GlobalKey _viewKey = GlobalKey();

  _CallBackBarrierRoute? _barrier;
  Offset? _miniOffset;
  bool _dragging = false;
  _CallSheet _sheet = _CallSheet.none;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final c = _service.conference;
    if (c == null) {
      _miniOffset = null;
      _sheet = _CallSheet.none;
    } else if (c.minimized || c.phase == CallPhase.ending) {
      _sheet = _CallSheet.none;
    }
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncBarrier());
  }

  /// «Назад» на Android в полноэкранном звонке сворачивает звонок, а не
  /// закрывает экран под ним. Navigator под оверлеем, поэтому ловим
  /// нажатие невидимым маршрутом поверх стека.
  void _syncBarrier() {
    final c = _service.conference;
    final want = c != null && !c.minimized;
    final navigator = AppNavigationService.navigatorKey.currentState;
    if (want && _barrier == null && navigator != null) {
      final route = _CallBackBarrierRoute(
        onBack: _onBackPressed,
        onGone: () {
          _barrier = null;
          // Поверх звонка открыли экран (тап по пушу) или сбросили стек —
          // сворачиваем, чтобы этот экран было видно.
          _service.minimize();
        },
      );
      _barrier = route;
      navigator.push(route);
    } else if (!want && _barrier != null) {
      final route = _barrier!;
      _barrier = null;
      route.removeQuietly();
    }
  }

  void _onBackPressed() {
    if (_sheet != _CallSheet.none) {
      setState(() => _sheet = _CallSheet.none);
      return;
    }
    _service.minimize();
  }

  void _openSheet(_CallSheet sheet) => setState(() => _sheet = sheet);

  void _closeSheet() => setState(() => _sheet = _CallSheet.none);

  Future<void> _onSpeakerPressed(CallConference c) async {
    if (c.hasExternalAudio) {
      if (Platform.isIOS) {
        await _service.showAudioRoutePicker();
      } else {
        _openSheet(_CallSheet.audio);
      }
      return;
    }
    await _service.setAudioRoute(
      c.audioRoute == CallAudioRoute.speaker
          ? CallAudioRoute.earpiece
          : CallAudioRoute.speaker,
    );
  }

  Rect _miniRect(Size screen, EdgeInsets padding) {
    final minX = _miniMargin;
    final maxX = screen.width - _miniSize.width - _miniMargin;
    final minY = padding.top + _miniMargin;
    final maxY = screen.height - padding.bottom - _miniSize.height - 96;
    final offset = _miniOffset ?? Offset(maxX, padding.top + 56);
    return Offset(
          offset.dx.clamp(minX, maxX),
          offset.dy.clamp(minY, maxY < minY ? minY : maxY),
        ) &
        _miniSize;
  }

  void _onMiniDragEnd(Size screen, EdgeInsets padding) {
    final rect = _miniRect(screen, padding);
    // Прилипает к ближайшему краю, как окошко FaceTime.
    final toLeft = rect.center.dx < screen.width / 2;
    setState(() {
      _dragging = false;
      _miniOffset = Offset(
        toLeft ? _miniMargin : screen.width - _miniSize.width - _miniMargin,
        rect.top,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _service.conference;
    if (c == null) return const SizedBox.shrink();

    final media = MediaQuery.of(context);
    final screen = media.size;
    final padding = media.padding;
    final minimized = c.minimized;
    final audioStage = c.showsAudioStage;
    final ending = c.phase == CallPhase.ending;

    const headerHeight = 60.0;
    final controlsHeight = padding.bottom + 132;
    final Rect stageRect;
    if (minimized) {
      stageRect = _miniRect(screen, padding);
    } else if (audioStage) {
      stageRect = Offset.zero & screen;
    } else {
      stageRect = Rect.fromLTRB(
        10,
        padding.top + headerHeight,
        screen.width - 10,
        screen.height - controlsHeight,
      );
    }
    final stageRadius = minimized ? 22.0 : (audioStage ? 0.0 : 28.0);

    final overlay = Stack(
      children: [
        // Фон вокруг карточки с видео.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: minimized,
            child: TickerMode(
              enabled: !minimized,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: minimized ? 0 : 1,
                child: const CallBackground(),
              ),
            ),
          ),
        ),
        AnimatedPositioned.fromRect(
          rect: stageRect,
          duration: _dragging
              ? Duration.zero
              : const Duration(milliseconds: 340),
          curve: Curves.easeOutCubic,
          child: _Stage(
            viewKey: _viewKey,
            conference: c,
            radius: stageRadius,
            minimized: minimized,
            audioStage: audioStage,
            onFlipCamera: _service.flipCamera,
            onExpand: _service.expand,
            onDragUpdate: (delta) => setState(() {
              _dragging = true;
              _miniOffset = _miniRect(screen, padding).topLeft + delta;
            }),
            onDragEnd: () => _onMiniDragEnd(screen, padding),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: minimized,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: minimized ? 0 : 1,
              child: Column(
                children: [
                  SizedBox(height: padding.top),
                  _Header(
                    conference: c,
                    height: headerHeight,
                    showTitle: !audioStage,
                    onMinimize: ending ? null : _service.minimize,
                    onParticipants: () => _openSheet(_CallSheet.participants),
                  ),
                  const Spacer(),
                  _Controls(
                    conference: c,
                    onSpeaker: () => _onSpeakerPressed(c),
                    onMore: () => _openSheet(_CallSheet.more),
                  ),
                  SizedBox(height: padding.bottom + 20),
                ],
              ),
            ),
          ),
        ),
        if (!minimized)
          Positioned.fill(
            child: _SheetLayer(
              sheet: _sheet,
              conference: c,
              bottomPadding: padding.bottom,
              onClose: _closeSheet,
              onOpenParticipants: () => _openSheet(_CallSheet.participants),
            ),
          ),
      ],
    );

    if (minimized) return overlay;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: overlay,
    );
  }
}

/// Карточка с видео Jitsi (или аватаром для 1:1 без видео).
class _Stage extends StatelessWidget {
  const _Stage({
    required this.viewKey,
    required this.conference,
    required this.radius,
    required this.minimized,
    required this.audioStage,
    required this.onFlipCamera,
    required this.onExpand,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final GlobalKey viewKey;
  final CallConference conference;
  final double radius;
  final bool minimized;
  final bool audioStage;
  final VoidCallback onFlipCamera;
  final VoidCallback onExpand;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final c = conference;
    final card = TweenAnimationBuilder<double>(
      tween: Tween(end: radius),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      builder: (context, r, child) =>
          ClipRRect(borderRadius: BorderRadius.circular(r), child: child),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppCallColors.stage),
          // Свёрнуто — касания окошку, а не плиткам Jitsi.
          IgnorePointer(
            ignoring: minimized,
            child: JitsiMeetConferenceView(key: viewKey, options: c.options),
          ),
          // Аватар поверх кадра Jitsi: сам вид продолжает работать под ним.
          IgnorePointer(
            ignoring: !audioStage,
            child: TickerMode(
              enabled: audioStage,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 280),
                opacity: audioStage ? 1 : 0,
                child: CallAudioStage(conference: c, compact: minimized),
              ),
            ),
          ),
          if (!minimized && !audioStage && !c.videoMuted)
            Positioned(
              top: 12,
              right: 12,
              child: CallIconButton(
                icon: CupertinoIcons.camera_rotate_fill,
                semanticLabel: 'Перевернуть камеру',
                onPressed: onFlipCamera,
              ),
            ),
          if (!minimized &&
              !audioStage &&
              c.isDirect &&
              c.peer?.audioOn == false)
            const Positioned(
              left: 12,
              bottom: 12,
              child: CallPill(
                icon: CupertinoIcons.mic_slash_fill,
                iconColor: AppCallColors.mutedBadge,
                text: 'Микрофон выключен',
              ),
            ),
          if (minimized) _MiniChrome(conference: c),
        ],
      ),
    );

    final framed = AnimatedContainer(
      duration: const Duration(milliseconds: 340),
      foregroundDecoration: minimized
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: AppCallColors.buttonBorder, width: 1),
            )
          : null,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: minimized
            ? const [
                BoxShadow(
                  color: AppCallColors.miniShadow,
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: card,
    );

    if (!minimized) return framed;
    // Свёрнуто: касания — окошку (развернуть, перетащить), а не Jitsi.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onExpand();
      },
      onPanUpdate: (d) => onDragUpdate(d.delta),
      onPanEnd: (_) => onDragEnd(),
      onPanCancel: onDragEnd,
      child: framed,
    );
  }
}

/// Таймер и значок микрофона в свёрнутом окошке.
class _MiniChrome extends StatelessWidget {
  const _MiniChrome({required this.conference});

  final CallConference conference;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppCallColors.backgroundBottom.withValues(alpha: 0),
              AppCallColors.backgroundBottom.withValues(alpha: 0.85),
            ],
          ),
        ),
        child: Row(
          children: [
            if (conference.audioMuted) ...[
              const Icon(
                CupertinoIcons.mic_slash_fill,
                size: 13,
                color: AppCallColors.mutedBadge,
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: CallStatusText(
                conference: conference,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  color: AppCallColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.conference,
    required this.height,
    required this.showTitle,
    required this.onMinimize,
    required this.onParticipants,
  });

  final CallConference conference;
  final double height;
  final bool showTitle;
  final VoidCallback? onMinimize;
  final VoidCallback onParticipants;

  @override
  Widget build(BuildContext context) {
    final c = conference;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            CallIconButton(
              icon: CupertinoIcons.chevron_down,
              semanticLabel: 'Свернуть звонок',
              onPressed: onMinimize,
            ),
            Expanded(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: showTitle ? 1 : 0,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppCallColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    CallStatusText(
                      conference: c,
                      style: const TextStyle(
                        color: AppCallColors.textSecondary,
                        fontSize: 13,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (c.isDirect)
              const SizedBox(width: 40)
            else
              CallPill(
                icon: CupertinoIcons.person_2_fill,
                text: '${c.participants.length + 1}',
                onTap: onParticipants,
              ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.conference,
    required this.onSpeaker,
    required this.onMore,
  });

  final CallConference conference;
  final VoidCallback onSpeaker;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final c = conference;
    final service = JitsiMeetingService.instance;
    final enabled = c.phase != CallPhase.ending;

    final mic = CallRoundButton(
      icon: c.audioMuted
          ? CupertinoIcons.mic_slash_fill
          : CupertinoIcons.mic_fill,
      label: 'Микрофон',
      active: c.audioMuted,
      onPressed: enabled ? service.toggleMicrophone : null,
    );
    final camera = CallRoundButton(
      icon: c.videoMuted
          ? ConnectIcons.icon14CameraOff
          : ConnectIcons.icon14CameraOn,
      label: 'Камера',
      active: !c.videoMuted,
      onPressed: enabled ? service.toggleCamera : null,
    );
    final canToggleSpeaker =
        c.hasExternalAudio ||
        c.availableRoutes.isEmpty ||
        c.availableRoutes.contains(CallAudioRoute.earpiece);
    final speaker = CallRoundButton(
      icon: _routeIcon(c.audioRoute),
      label: _routeLabel(c.audioRoute, c.hasExternalAudio),
      active:
          c.audioRoute != CallAudioRoute.earpiece &&
          c.audioRoute != CallAudioRoute.unknown,
      onPressed: enabled && canToggleSpeaker ? onSpeaker : null,
    );
    final hangUp = CallRoundButton(
      icon: CupertinoIcons.phone_down_fill,
      label: 'Завершить',
      destructive: true,
      onPressed: enabled ? service.hangUp : null,
    );

    final buttons = c.isDirect
        ? [speaker, camera, mic, hangUp]
        : [
            mic,
            camera,
            speaker,
            CallRoundButton(
              icon: CupertinoIcons.ellipsis,
              label: 'Ещё',
              badge: c.unreadChat,
              onPressed: enabled ? onMore : null,
            ),
            hangUp,
          ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [for (final b in buttons) Expanded(child: Center(child: b))],
      ),
    );
  }

  static IconData _routeIcon(CallAudioRoute route) => switch (route) {
    CallAudioRoute.headphones => CupertinoIcons.headphones,
    CallAudioRoute.bluetooth => CupertinoIcons.bluetooth,
    _ => CupertinoIcons.speaker_3_fill,
  };

  static String _routeLabel(CallAudioRoute route, bool external) =>
      switch (route) {
        CallAudioRoute.headphones => 'Наушники',
        CallAudioRoute.bluetooth => 'Bluetooth',
        _ => external ? 'Звук' : 'Динамик',
      };
}

/// Шторки «Ещё», «Участники», «Звук» — внутри оверлея: Navigator приложения
/// под экраном звонка, его шторки оказались бы под ним.
class _SheetLayer extends StatelessWidget {
  const _SheetLayer({
    required this.sheet,
    required this.conference,
    required this.bottomPadding,
    required this.onClose,
    required this.onOpenParticipants,
  });

  final _CallSheet sheet;
  final CallConference conference;
  final double bottomPadding;
  final VoidCallback onClose;
  final VoidCallback onOpenParticipants;

  @override
  Widget build(BuildContext context) {
    final open = sheet != _CallSheet.none;
    return IgnorePointer(
      ignoring: !open,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: open ? 1 : 0,
                child: const ColoredBox(color: Color(0x73000000)),
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              offset: open ? Offset.zero : const Offset(0, 1.2),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: KeyedSubtree(key: ValueKey(sheet), child: _sheetBody()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetBody() {
    final service = JitsiMeetingService.instance;
    final c = conference;
    final List<Widget> children;
    switch (sheet) {
      case _CallSheet.none:
        return const SizedBox.shrink();
      case _CallSheet.more:
        children = [
          if (!c.videoMuted)
            _SheetRow(
              icon: CupertinoIcons.camera_rotate_fill,
              title: 'Перевернуть камеру',
              onTap: () {
                onClose();
                service.flipCamera();
              },
            ),
          if (!c.isDirect)
            _SheetRow(
              icon: CupertinoIcons.chat_bubble_2_fill,
              title: 'Чат встречи',
              badge: c.unreadChat,
              onTap: () {
                onClose();
                service.openChat();
              },
            ),
          _SheetRow(
            icon: CupertinoIcons.person_2_fill,
            title: 'Участники',
            trailing: '${c.participants.length + 1}',
            onTap: onOpenParticipants,
          ),
          if (Platform.isAndroid && !c.isDirect)
            _SheetRow(
              icon: CupertinoIcons.rectangle_on_rectangle,
              title: c.screenSharing
                  ? 'Остановить демонстрацию'
                  : 'Демонстрация экрана',
              onTap: () {
                onClose();
                service.toggleScreenShare();
              },
            ),
          _SheetRow(
            icon: CupertinoIcons.arrow_down_right_arrow_up_left,
            title: 'Свернуть звонок',
            onTap: () {
              onClose();
              service.minimize();
            },
          ),
        ];
      case _CallSheet.participants:
        final self = c.options.userInfo?.displayName?.trim();
        children = [
          _SheetTitle('Участники · ${c.participants.length + 1}'),
          _ParticipantRow(
            name: self == null || self.isEmpty ? 'Вы' : '$self (вы)',
            audioOn: !c.audioMuted,
            videoOn: !c.videoMuted,
          ),
          for (final p in c.participants.values)
            _ParticipantRow(
              name: p.name.isEmpty ? 'Участник' : p.name,
              audioOn: p.audioOn,
              videoOn: p.videoOn,
            ),
        ];
      case _CallSheet.audio:
        children = [
          const _SheetTitle('Вывод звука'),
          for (final route in c.availableRoutes)
            _SheetRow(
              icon: _Controls._routeIcon(route),
              title: switch (route) {
                CallAudioRoute.speaker => 'Динамик',
                CallAudioRoute.earpiece => 'Телефон',
                CallAudioRoute.headphones => 'Наушники',
                CallAudioRoute.bluetooth => 'Bluetooth',
                CallAudioRoute.unknown => '',
              },
              selected: route == c.audioRoute,
              onTap: () {
                onClose();
                service.setAudioRoute(route);
              },
            ),
        ];
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 460),
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + bottomPadding * 0.6),
      decoration: BoxDecoration(
        color: const Color(0xF21C1E24),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppCallColors.buttonBorder, width: 0.8),
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            color: AppCallColors.textTertiary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailing,
    this.badge = 0,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? trailing;
  final int badge;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size.fromHeight(52),
      onPressed: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppCallColors.buttonFill,
              ),
              child: Icon(icon, size: 19, color: AppCallColors.textPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppCallColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppCallColors.mutedBadge,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    color: AppCallColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (trailing != null)
              Text(
                trailing!,
                style: const TextStyle(
                  color: AppCallColors.textTertiary,
                  fontSize: 15,
                ),
              ),
            if (selected)
              const Icon(
                CupertinoIcons.checkmark_alt,
                size: 20,
                color: AppColors.primary,
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.name,
    required this.audioOn,
    required this.videoOn,
  });

  final String name;

  /// `null` — неизвестно (участник из веб-портала).
  final bool? audioOn;
  final bool? videoOn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          MemberAvatar(displayName: name, radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppCallColors.textPrimary,
                fontSize: 16,
              ),
            ),
          ),
          if (videoOn == true)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(
                CupertinoIcons.video_camera_solid,
                size: 18,
                color: AppCallColors.textSecondary,
              ),
            ),
          if (audioOn != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                audioOn!
                    ? CupertinoIcons.mic_fill
                    : CupertinoIcons.mic_slash_fill,
                size: 18,
                color: audioOn!
                    ? AppCallColors.textSecondary
                    : AppCallColors.mutedBadge,
              ),
            ),
        ],
      ),
    );
  }
}

/// Невидимый маршрут поверх стека, пока звонок на весь экран: системное
/// «назад» достаётся ему (см. _CallOverlayHostState._syncBarrier).
class _CallBackBarrierRoute extends PopupRoute<void> {
  _CallBackBarrierRoute({required this.onBack, required this.onGone});

  final VoidCallback onBack;

  /// Маршрут убрали не мы: сбросили стек или открыли экран поверх.
  final VoidCallback onGone;

  bool _quiet = false;
  bool _gone = false;

  void removeQuietly() {
    _quiet = true;
    if (isActive) navigator?.removeRoute(this);
  }

  void _reportGone() {
    if (_gone || _quiet) return;
    _gone = true;
    onGone();
  }

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    super.didChangeNext(nextRoute);
    if (nextRoute != null) {
      // Экран открыли поверх звонка — убираемся с дороги.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reportGone();
        removeQuietly();
      });
    }
  }

  @override
  void dispose() {
    _reportGone();
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack();
      },
      child: const SizedBox.shrink(),
    );
  }
}
