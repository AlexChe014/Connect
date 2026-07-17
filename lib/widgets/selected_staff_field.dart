import 'package:flutter/material.dart';

import '../models/staff_user.dart';
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
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _openPicker,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: 'Нажмите, чтобы добавить',
              suffixIcon: const Icon(Icons.person_add_outlined),
            ),
            child: participants.isEmpty
                ? Text(
                    'Не выбраны',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        if (participants.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: participants.map((user) {
              return InputChip(
                avatar: _StaffChipAvatar(user: user),
                label: Text(user.fullName),
                onDeleted: () => widget.onUserRemoved(user),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

class _StaffChipAvatar extends StatelessWidget {
  const _StaffChipAvatar({required this.user});

  final StaffUser user;

  @override
  Widget build(BuildContext context) {
    final url = user.avatarUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        backgroundImage: NetworkImage(url),
        onBackgroundImageError: (exception, stackTrace) {},
        child: Text(user.initials, style: const TextStyle(fontSize: 10)),
      );
    }
    return CircleAvatar(
      child: Text(user.initials, style: const TextStyle(fontSize: 10)),
    );
  }
}
