import 'package:flutter/cupertino.dart';

import '../models/staff_user.dart';
import 'chat_avatar.dart';
import 'staff_user_picker_sheet.dart';

/// Поле выбора участников брони с чипами и поиском.
class SelectedStaffField extends StatefulWidget {
  const SelectedStaffField({
    super.key,
    required this.participants,
    required this.onUserAdded,
    required this.onUserRemoved,
    this.label = 'Участники',
  });

  final List<StaffUser> participants;
  final ValueChanged<StaffUser> onUserAdded;
  final ValueChanged<StaffUser> onUserRemoved;
  final String label;

  @override
  State<SelectedStaffField> createState() => _SelectedStaffFieldState();
}

class _SelectedStaffFieldState extends State<SelectedStaffField> {
  Future<void> _openPicker() async {
    await StaffUserPickerSheet.show(
      context,
      selectedIds: widget.participants.map((u) => u.id).toSet(),
      onUserSelected: widget.onUserAdded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final participants = widget.participants;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CupertinoListSection.insetGrouped(
          margin: EdgeInsets.zero,
          children: [
            CupertinoListTile(
              leading: Container(
                width: 29,
                height: 29,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGreen,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  CupertinoIcons.person_2_fill,
                  size: 17,
                  color: CupertinoColors.white,
                ),
              ),
              title: Text(widget.label),
              additionalInfo: participants.isEmpty
                  ? const Text(
                      'Не выбраны',
                      style: TextStyle(color: CupertinoColors.secondaryLabel),
                    )
                  : null,
              trailing: const CupertinoListTileChevron(),
              onTap: _openPicker,
            ),
          ],
        ),
        if (participants.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: participants.map((user) {
              return _StaffChip(
                user: user,
                onRemove: () => widget.onUserRemoved(user),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

class _StaffChip extends StatelessWidget {
  const _StaffChip({required this.user, required this.onRemove});

  final StaffUser user;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey5.resolveFrom(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MemberAvatar(
            displayName: user.fullName,
            avatarUrl: user.avatarUrl,
            radius: 11,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              user.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: CupertinoColors.label),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 16,
              color: CupertinoColors.systemGrey,
            ),
          ),
        ],
      ),
    );
  }
}
