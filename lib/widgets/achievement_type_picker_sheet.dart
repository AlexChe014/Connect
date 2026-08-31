import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show showModalBottomSheet;

import '../models/bonus_program/achievement_type.dart';

/// Мульти-выбор типов достижений: тап сразу добавляет запись в форму,
/// шторка остаётся открытой, пока не нажата «Готово».
class AchievementTypePickerSheet extends StatefulWidget {
  const AchievementTypePickerSheet({
    super.key,
    required this.types,
    required this.selectedIds,
    required this.onTypeSelected,
  });

  final List<AchievementType> types;
  final Set<int> selectedIds;
  final ValueChanged<AchievementType> onTypeSelected;

  static Future<void> show(
    BuildContext context, {
    required List<AchievementType> types,
    required Set<int> selectedIds,
    required ValueChanged<AchievementType> onTypeSelected,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        final maxHeight =
            (mediaQuery.size.height - mediaQuery.padding.top - 24).clamp(
              200.0,
              mediaQuery.size.height,
            );
        final height = (mediaQuery.size.height * 0.7).clamp(0.0, maxHeight);
        return SizedBox(
          height: height,
          child: AchievementTypePickerSheet(
            types: types,
            selectedIds: selectedIds,
            onTypeSelected: onTypeSelected,
          ),
        );
      },
    );
  }

  @override
  State<AchievementTypePickerSheet> createState() =>
      _AchievementTypePickerSheetState();
}

class _AchievementTypePickerSheetState
    extends State<AchievementTypePickerSheet> {
  late Set<int> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<int>.from(widget.selectedIds);
  }

  void _onTypeTap(AchievementType type) {
    if (_selectedIds.contains(type.id)) return;
    setState(() => _selectedIds.add(type.id));
    widget.onTypeSelected(type);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: '.SF Pro Text',
        decoration: TextDecoration.none,
        color: CupertinoColors.label.resolveFrom(context),
        fontSize: 16,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'Выберите достижение',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.label,
                ),
              ),
            ),
            Expanded(
              child: widget.types.isEmpty
                  ? const Center(
                      child: Text(
                        'Нет доступных достижений',
                        style: TextStyle(
                          color: CupertinoColors.secondaryLabel,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: widget.types.length,
                      itemBuilder: (context, index) {
                        final type = widget.types[index];
                        final isSelected = _selectedIds.contains(type.id);
                        return _PickerTypeTile(
                          type: type,
                          isSelected: isSelected,
                          onTap: () => _onTypeTap(type),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Готово'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerTypeTile extends StatelessWidget {
  const _PickerTypeTile({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  final AchievementType type;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? CupertinoColors.systemGrey5.resolveFrom(context)
            : CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
                context,
              ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isSelected ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${type.pointsCost} баллов',
                      style: const TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.secondaryLabel,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isSelected)
                const Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  color: CupertinoColors.activeBlue,
                )
              else
                const Icon(
                  CupertinoIcons.plus_circle,
                  color: CupertinoColors.systemGrey,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
