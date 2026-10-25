import 'package:flutter/cupertino.dart';

import '../config/app_theme.dart';
import '../models/call_conference.dart';
import '../services/haptics_service.dart';
import '../services/jitsi_meeting_service.dart';
import 'call_glass.dart';
import 'chat_avatar.dart';

/// Чат встречи — свой вместо окна Jitsi (у того свой стиль и вкладка
/// «Опросы»). Сообщения ходят через Jitsi и живут только до конца звонка.
///
/// Лежит внутри CallOverlayHost, над Navigator, поэтому у поля ввода свой
/// Overlay — без него не показать меню «Вставить» и ручки выделения.
class CallChatSheet extends StatefulWidget {
  const CallChatSheet({
    super.key,
    required this.conference,
    required this.open,
    required this.onClose,
  });

  final CallConference conference;
  final bool open;
  final VoidCallback onClose;

  @override
  State<CallChatSheet> createState() => _CallChatSheetState();
}

class _CallChatSheetState extends State<CallChatSheet> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant CallChatSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open && !widget.open) {
      _focus.unfocus();
      _dragOffset = 0;
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    AppHaptics.light();
    JitsiMeetingService.instance.sendChatMessage(text);
    _input.clear();
  }

  void _onDragEnd(DragEndDetails details) {
    final fling = (details.primaryVelocity ?? 0) > 700;
    if (fling || _dragOffset > 120) {
      widget.onClose();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final open = widget.open;

    return IgnorePointer(
      ignoring: !open,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: open ? 1 : 0,
                child: const ColoredBox(color: Color(0x73000000)),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: media.padding.top + 12,
            bottom: 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              offset: open ? Offset.zero : const Offset(0, 1.05),
              child: Transform.translate(
                offset: Offset(0, _dragOffset),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF1C1E24),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    border: Border(
                      top: BorderSide(
                        color: AppCallColors.buttonBorder,
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: Overlay(
                    initialEntries: [
                      OverlayEntry(
                        builder: (context) => Column(
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onVerticalDragUpdate: (d) => setState(() {
                                _dragOffset = (_dragOffset + d.delta.dy).clamp(
                                  0,
                                  double.infinity,
                                );
                              }),
                              onVerticalDragEnd: _onDragEnd,
                              child: _ChatHeader(onClose: widget.onClose),
                            ),
                            Expanded(
                              child: _MessageList(
                                messages: widget.conference.chatMessages,
                              ),
                            ),
                            _Composer(
                              controller: _input,
                              focusNode: _focus,
                              bottomInset: keyboard > 0
                                  ? keyboard
                                  : media.padding.bottom,
                              onSend: _send,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: AppCallColors.buttonBorder,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(width: 40),
              const Expanded(
                child: Column(
                  children: [
                    Text(
                      'Чат встречи',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppCallColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Видят все участники',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppCallColors.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              CallIconButton(
                icon: CupertinoIcons.xmark,
                semanticLabel: 'Закрыть чат',
                onPressed: onClose,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.messages});

  final List<CallChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.chat_bubble_2,
                size: 44,
                color: AppCallColors.textTertiary,
              ),
              SizedBox(height: 12),
              Text(
                'Сообщений пока нет',
                style: TextStyle(
                  color: AppCallColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Сообщения видны участникам только во время встречи',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppCallColors.textSecondary,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // reverse: новые снизу, и список сам держится у последнего сообщения.
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final index = messages.length - 1 - i;
        final m = messages[index];
        final prev = index > 0 ? messages[index - 1] : null;
        final next = index < messages.length - 1 ? messages[index + 1] : null;
        return _Bubble(
          message: m,
          firstInGroup: prev == null || !_sameAuthor(prev, m),
          lastInGroup: next == null || !_sameAuthor(m, next),
        );
      },
    );
  }

  static bool _sameAuthor(CallChatMessage a, CallChatMessage b) =>
      a.isOwn == b.isOwn &&
      a.senderId == b.senderId &&
      b.time.difference(a.time).inMinutes < 3;
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.firstInGroup,
    required this.lastInGroup,
  });

  final CallChatMessage message;
  final bool firstInGroup;
  final bool lastInGroup;

  static const _avatarRadius = 14.0;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final own = m.isOwn;
    final name = m.senderName.isEmpty ? 'Участник' : m.senderName;
    const big = Radius.circular(18);
    const small = Radius.circular(6);

    final bubble = Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
      decoration: BoxDecoration(
        color: own ? AppColors.primary : AppCallColors.buttonFill,
        borderRadius: BorderRadius.only(
          topLeft: own || firstInGroup ? big : small,
          bottomLeft: own || lastInGroup ? big : small,
          topRight: !own || firstInGroup ? big : small,
          bottomRight: !own || lastInGroup ? big : small,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.isPrivate)
            const Padding(
              padding: EdgeInsets.only(bottom: 2),
              child: Text(
                'Лично вам',
                style: TextStyle(
                  color: AppCallColors.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            children: [
              Text(
                m.text,
                style: const TextStyle(
                  color: AppCallColors.textPrimary,
                  fontSize: 16,
                  height: 1.25,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Text(
                  _time(m.time),
                  style: TextStyle(
                    color: own
                        ? AppCallColors.textSecondary
                        : AppCallColors.textTertiary,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final maxWidth = MediaQuery.sizeOf(context).width * 0.74;
    return Padding(
      padding: EdgeInsets.only(top: firstInGroup ? 10 : 2),
      child: Column(
        crossAxisAlignment: own
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (!own && firstInGroup)
            Padding(
              padding: const EdgeInsets.only(
                left: _avatarRadius * 2 + 8 + 12,
                bottom: 3,
              ),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppCallColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: own
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!own) ...[
                if (lastInGroup)
                  MemberAvatar(displayName: name, radius: _avatarRadius)
                else
                  const SizedBox(width: _avatarRadius * 2),
                const SizedBox(width: 8),
              ],
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: bubble,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.bottomInset,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final double bottomInset;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final canSend = controller.text.trim().isNotEmpty;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomInset),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppCallColors.buttonFill, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              focusNode: focusNode,
              placeholder: 'Сообщение',
              placeholderStyle: const TextStyle(
                color: AppCallColors.textTertiary,
                fontSize: 16,
              ),
              style: const TextStyle(
                color: AppCallColors.textPrimary,
                fontSize: 16,
              ),
              cursorColor: AppColors.primary,
              keyboardAppearance: Brightness.dark,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: AppCallColors.buttonFill,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppCallColors.buttonBorder,
                  width: 0.6,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: canSend ? 1 : 0.4,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(38, 38),
              onPressed: canSend ? onSend : null,
              child: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                ),
                child: const Icon(
                  CupertinoIcons.arrow_up,
                  size: 20,
                  color: CupertinoColors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
