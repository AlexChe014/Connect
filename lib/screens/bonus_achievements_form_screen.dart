import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';

import '../config/app_theme.dart';
import '../models/bonus_program/achievement_type.dart';
import '../models/bonus_program/form_config.dart';
import '../repositories/bonus_program_repository.dart';
import '../services/api_client.dart';
import '../widgets/achievement_type_picker_sheet.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/bonus_glass.dart';
import '../widgets/booking_glass_form.dart';

class _AchievementEntry {
  _AchievementEntry(this.type);

  final AchievementType type;
  final TextEditingController descriptionController = TextEditingController();
  final List<PlatformFile> files = [];

  void dispose() => descriptionController.dispose();
}

/// Ежемесячная форма достижений: выбор типов достижений, описание,
/// вложения и отправка на модерацию HR.
class BonusAchievementsFormScreen extends StatefulWidget {
  const BonusAchievementsFormScreen({super.key});

  @override
  State<BonusAchievementsFormScreen> createState() =>
      _BonusAchievementsFormScreenState();
}

class _BonusAchievementsFormScreenState
    extends State<BonusAchievementsFormScreen> {
  final _feedbackController = TextEditingController();

  FormConfig? _config;
  List<AchievementType> _types = [];
  final List<_AchievementEntry> _entries = [];

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        BonusProgramRepository.instance.getFormConfig(),
        BonusProgramRepository.instance.getAchievementTypes(),
      ]);
      if (!mounted) return;
      setState(() {
        _config = results[0] as FormConfig;
        _types = results[1] as List<AchievementType>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is ApiException
            ? e.message
            : 'Не удалось получить форму достижений';
      });
    }
  }

  Widget _iconBadge(IconData icon, Color color) =>
      AppIconBadge(icon: icon, color: color);

  List<AchievementType> get _availableTypes {
    final usedIds = _entries.map((e) => e.type.id).toSet();
    return _types.where((t) => t.isActive && !usedIds.contains(t.id)).toList();
  }

  void _addAchievement() {
    final available = _availableTypes;
    if (available.isEmpty) return;

    AchievementTypePickerSheet.show(
      context,
      types: available,
      selectedIds: const {},
      onTypeSelected: (type) {
        setState(() => _entries.add(_AchievementEntry(type)));
      },
    );
  }

  void _removeEntry(_AchievementEntry entry) {
    setState(() => _entries.remove(entry));
    entry.dispose();
  }

  Future<void> _attachFiles(_AchievementEntry entry) async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx'],
    );
    if (result == null || result.files.isEmpty) return;
    setState(
      () => entry.files.addAll(result.files.where((f) => f.bytes != null)),
    );
  }

  Future<void> _submit() async {
    if (_entries.isEmpty) {
      setState(() => _errorMessage = 'Добавьте хотя бы одно достижение');
      return;
    }
    final feedbackEnabled = _config?.feedbackEnabled ?? false;
    if (feedbackEnabled && _feedbackController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Заполните поле обратной связи');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final drafts = _entries
          .map(
            (entry) => FormAchievementDraft(
              achievementTypeId: entry.type.id,
              description: entry.descriptionController.text,
              files: entry.files
                  .map(
                    (f) =>
                        FormAchievementFile(filename: f.name, bytes: f.bytes!),
                  )
                  .toList(),
            ),
          )
          .toList();

      await BonusProgramRepository.instance.submitForm(
        achievements: drafts,
        feedback: feedbackEnabled ? _feedbackController.text : null,
      );

      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Заявка отправлена'),
          content: const Text('Форма достижений отправлена на согласование.'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context),
              child: const Text('Ок'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = e is ApiException
            ? e.message
            : 'Не удалось отправить форму';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BonusGlassScaffold(
      title: 'Форма достижений',
      canPop: !_isSubmitting,
      slivers: [_buildBody()],
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const BonusSliverLoader();

    final config = _config;
    if (config == null) {
      return SliverAppEmptyState(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: _errorMessage ?? 'Не удалось загрузить форму',
        onRetry: _load,
      );
    }

    if (!config.periodOpen) {
      return SliverAppEmptyState(
        icon: CupertinoIcons.calendar_badge_minus,
        message: 'Форма недоступна в этом месяце. Попробуйте позже.',
        onRetry: _load,
      );
    }

    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return SliverList.list(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                config.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (config.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  config.description,
                  style: TextStyle(fontSize: 14, height: 1.3, color: secondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        ..._entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _AchievementCard(
              entry: entry,
              onRemove: () => _removeEntry(entry),
              onAttach: () => _attachFiles(entry),
              onRebuild: () => setState(() {}),
            ),
          ),
        ),
        if (_availableTypes.isNotEmpty)
          AppGlassSection(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              CupertinoListTile(
                leading: _iconBadge(
                  CupertinoIcons.add,
                  CupertinoColors.systemBlue.resolveFrom(context),
                ),
                title: const Text(
                  'Добавить достижение',
                  style: TextStyle(fontSize: 16),
                ),
                trailing: const CupertinoListTileChevron(),
                onTap: _addAchievement,
              ),
            ],
          ),
        if (config.feedbackEnabled) ...[
          const AppGlassSectionLabel('Обратная связь'),
          AppGlassSection(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              CupertinoTextField(
                controller: _feedbackController,
                placeholder: 'Ваш отзыв',
                textCapitalization: TextCapitalization.sentences,
                minLines: 3,
                maxLines: 6,
                style: TextStyle(
                  fontSize: 16,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: const BoxDecoration(),
              ),
            ],
          ),
          if (config.feedbackDescription.isNotEmpty)
            BookingFootnote(config.feedbackDescription),
        ],
        if (_errorMessage != null)
          BookingFootnote(_errorMessage!, isError: true),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: AppPrimaryButton(
            label: 'Отправить',
            isLoading: _isSubmitting,
            onPressed: _submit,
          ),
        ),
      ],
    );
  }
}

/// Выбранное достижение на стекле: тип и баллы, описание, вложения.
class _AchievementCard extends StatelessWidget {
  const _AchievementCard({
    required this.entry,
    required this.onRemove,
    required this.onAttach,
    required this.onRebuild,
  });

  final _AchievementEntry entry;
  final VoidCallback onRemove;
  final VoidCallback onAttach;
  final VoidCallback onRebuild;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final chipFill = CupertinoColors.tertiarySystemFill.resolveFrom(context);
    return AppGlass(
      borderRadius: BorderRadius.circular(22),
      shadows: AppGlass.controlShadow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
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
                        entry.type.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        formatPoints(entry.type.pointsCost),
                        style: TextStyle(fontSize: 13, color: secondary),
                      ),
                    ],
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.all(8),
                  minimumSize: Size.zero,
                  onPressed: onRemove,
                  child: Icon(
                    CupertinoIcons.xmark_circle_fill,
                    size: 22,
                    color: CupertinoColors.systemGrey3.resolveFrom(context),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 0.5,
            margin: const EdgeInsets.only(left: 16),
            color: CupertinoColors.separator.resolveFrom(context),
          ),
          CupertinoTextField(
            controller: entry.descriptionController,
            placeholder: 'Описание (необязательно)',
            textCapitalization: TextCapitalization.sentences,
            minLines: 1,
            maxLines: 4,
            style: TextStyle(fontSize: 15, color: label),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...entry.files.map(
                  (file) => Container(
                    padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                    decoration: BoxDecoration(
                      color: chipFill,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.doc, size: 14, color: secondary),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 2),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            entry.files.remove(file);
                            onRebuild();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              CupertinoIcons.xmark,
                              size: 12,
                              color: secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: onAttach,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.paperclip,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Прикрепить файл',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
