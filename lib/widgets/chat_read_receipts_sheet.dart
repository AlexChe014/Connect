import 'dart:async';

import 'package:connect/config/app_theme.dart';
import 'package:connect/models/chat.dart';
import 'package:connect/models/chat/chat_read_receipts.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/widgets/chat_avatar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show showModalBottomSheet;

/// Шторка «кто прочитал» для своего сообщения в группе.
Future<void> showChatReadReceiptsSheet(
  BuildContext context, {
  required String chatId,
  required String messageId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.groupedBackground.resolveFrom(context),
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: _ReadReceiptsSheet(chatId: chatId, messageId: messageId),
    ),
  );
}

class _ReadReceiptsSheet extends StatefulWidget {
  const _ReadReceiptsSheet({required this.chatId, required this.messageId});

  final String chatId;
  final String messageId;

  @override
  State<_ReadReceiptsSheet> createState() => _ReadReceiptsSheetState();
}

class _ReadReceiptsSheetState extends State<_ReadReceiptsSheet> {
  final ChatService _service = ChatService.instance;
  bool _refreshing = true;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  /// Локальная копия могла устареть, а только что отправленное сообщение
  /// приходит вообще без статусов.
  Future<void> _refresh() async {
    await _service.loadMessages(widget.chatId, force: true, showLoading: false);
    if (mounted) setState(() => _refreshing = false);
  }

  ChatReadReceipts? _receipts() {
    final members = _service.chatById(widget.chatId)?.members ?? const [];
    for (final message in _service.messagesFor(widget.chatId)) {
      if (message.id == widget.messageId) {
        return ChatReadReceipts.of(
          message,
          members,
          selfUserId: _service.selfUserId,
        );
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final receipts = _receipts();
        if (receipts == null || receipts.total == 0) {
          return Center(
            child: _refreshing
                ? const CupertinoActivityIndicator()
                : Text(
                    'Нет данных о прочтении',
                    style: TextStyle(
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (receipts.read.isNotEmpty)
              _Section(title: 'Прочитали', members: receipts.read),
            if (receipts.unread.isNotEmpty)
              _Section(title: 'Не прочитали', members: receipts.unread),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.members});

  final String title;
  final List<ChatMemberSummary> members;

  @override
  Widget build(BuildContext context) {
    return CupertinoListSection.insetGrouped(
      backgroundColor: AppColors.groupedBackground.resolveFrom(context),
      header: Text('$title · ${members.length}'),
      children: [
        for (final member in members)
          CupertinoListTile(
            leading: MemberAvatar(
              displayName: member.displayName,
              avatarUrl: member.avatarUrl,
              radius: 14,
            ),
            title: Text(member.displayName),
          ),
      ],
    );
  }
}
