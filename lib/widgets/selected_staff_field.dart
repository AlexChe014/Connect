import 'package:flutter/cupertino.dart';

import '../models/staff_user.dart';
import 'app_glass.dart';
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
      onUserDeselected: widget.onUserRemoved,
    );
  }

  @override
  Widget build(BuildContext context) {
    final participants = widget.participants;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    // Список строк, а не чипы: длинные ФИО в чипах обрезались и
    // складывались в рваную лесенку разной ширины.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppGlassSectionLabel(
          participants.isEmpty
              ? widget.label
              : '${widget.label} (${participants.length})',
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
        ),
        AppGlassSection(
          margin: EdgeInsets.zero,
          children: [
            for (final user in participants)
              CupertinoListTile(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
                leading: MemberAvatar(
                  displayName: user.fullName,
                  avatarUrl: user.avatarUrl,
                  radius: 15,
                ),
                title: Text(
                  user.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
                trailing: CupertinoButton(
                  padding: const EdgeInsets.all(6),
                  minimumSize: Size.zero,
                  onPressed: () => widget.onUserRemoved(user),
                  child: Icon(
                    CupertinoIcons.xmark_circle_fill,
                    size: 20,
                    color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                  ),
                ),
              ),
            CupertinoListTile(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 14, 8),
              leading: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CupertinoColors.tertiarySystemFill.resolveFrom(
                    context,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  CupertinoIcons.plus,
                  size: 16,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
              title: Text(
                'Добавить участника',
                style: TextStyle(
                  fontSize: 15,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
              additionalInfo: participants.isEmpty
                  ? Text(
                      'Никого',
                      style: TextStyle(fontSize: 15, color: secondary),
                    )
                  : null,
              onTap: _openPicker,
            ),
          ],
        ),
      ],
    );
  }
}
