import 'package:connect/models/chat/chat_active_call.dart';
import 'package:connect/widgets/app_glass.dart';
import 'package:flutter/cupertino.dart';

/// Плашка «идёт видеозвонок» над лентой сообщений.
class ChatActiveCallBanner extends StatelessWidget {
  const ChatActiveCallBanner({
    super.key,
    required this.call,
    required this.isGroup,
    required this.peerName,
    required this.onJoin,
    this.joining = false,
  });

  final ChatActiveCall call;
  final bool isGroup;
  final String peerName;
  final VoidCallback onJoin;
  final bool joining;

  @override
  Widget build(BuildContext context) {
    final title = isGroup
        ? (call.topic?.isNotEmpty == true
              ? 'Видеозвонок «${call.topic}»'
              : 'Идёт видеозвонок в группе')
        : call.isIncoming
        ? 'Входящий звонок от $peerName'
        : 'Вы начали звонок';

    final subtitle = isGroup
        ? 'Присоединяйтесь — пока кто-то на линии'
        : call.isIncoming
        ? 'Нажмите, чтобы ответить'
        : 'Собеседник может подключиться по ссылке в чате';

    // Стекло с лёгкой зелёной подсветкой: баннер висит поверх ленты
    // сообщений вместе с остальными плавающими панелями чата.
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: AppGlass(
        borderRadius: BorderRadius.circular(18),
        shadows: AppGlass.controlShadow,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          color: CupertinoColors.systemGreen.withValues(alpha: 0.12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGreen.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.video_camera_solid,
                  color: CupertinoColors.systemGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                minimumSize: Size.zero,
                color: CupertinoColors.systemGreen,
                borderRadius: BorderRadius.circular(20),
                onPressed: joining ? null : onJoin,
                child: joining
                    ? const CupertinoActivityIndicator(
                        color: CupertinoColors.white,
                      )
                    : Text(
                        call.isIncoming && !isGroup ? 'Ответить' : 'Войти',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.white,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
