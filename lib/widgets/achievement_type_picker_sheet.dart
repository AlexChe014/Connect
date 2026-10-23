import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show showModalBottomSheet;

import '../config/app_theme.dart';
import '../models/bonus_program/achievement_type.dart';
import 'app_glass.dart';
import 'app_icon_badge.dart';
import 'bonus_glass.dart';

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
        final maxHeight = (mediaQuery.size.height - mediaQuery.padding.top - 24)
            .clamp(200.0, mediaQuery.size.height);
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
            Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'Выберите достижение',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
            ),
            Expanded(
              child: widget.types.isEmpty
                  ? Center(
                      child: Text(
                        'Нет доступных достижений',
                        style: TextStyle(
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
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
    // Заливка и кромка как у AppGlass, но без размытия: строк в списке
    // много, а BackdropFilter под каждой дорог.
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? CupertinoColors.tertiarySystemFill.resolveFrom(context)
            : AppColors.glassFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.glassBorder.resolveFrom(context)),
        boxShadow: isSelected ? null : AppGlass.controlShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isSelected ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              AppIconBadge(
                icon: CupertinoIcons.rosette,
                color: CupertinoColors.systemGreen.resolveFrom(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatPoints(type.pointsCost),
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.secondaryLabel.resolveFrom(
                          context,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isSelected)
                const Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  color: AppColors.primary,
                )
              else
                Icon(
                  CupertinoIcons.plus_circle,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
