import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';

import '../models/bonus_program/achievement_type.dart';
import '../models/bonus_program/form_config.dart';
import '../repositories/bonus_program_repository.dart';
import '../services/api_client.dart';
import '../widgets/achievement_type_picker_sheet.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';

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

  Widget _iconBadge(IconData icon, Color color) {
    return Container(
      width: 29,
      height: 29,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 17, color: CupertinoColors.white),
    );
  }

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
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Форма достижений'),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: CupertinoColors.label.resolveFrom(context),
          decoration: TextDecoration.none,
        ),
        child: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const AppPageLoader();

    final config = _config;
    if (config == null) {
      return AppEmptyState(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: _errorMessage ?? 'Не удалось загрузить форму',
        onRetry: _load,
      );
    }

    if (!config.periodOpen) {
      return AppEmptyState(
        icon: CupertinoIcons.calendar_badge_minus,
        message: 'Форма недоступна в этом месяце. Попробуйте позже.',
        onRetry: _load,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        Text(
          config.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        if (config.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            config.description,
            style: const TextStyle(
              fontSize: 13,
              color: CupertinoColors.secondaryLabel,
            ),
          ),
        ],
        const SizedBox(height: 16),
        ..._entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _AchievementCard(
              entry: entry,
              onRemove: () => _removeEntry(entry),
              onAttach: () => _attachFiles(entry),
              onRebuild: () => setState(() {}),
            ),
          ),
        ),
        if (_availableTypes.isNotEmpty)
          CupertinoListSection.insetGrouped(
            margin: EdgeInsets.zero,
            children: [
              CupertinoListTile(
                leading: _iconBadge(
                  CupertinoIcons.add,
                  CupertinoColors.systemBlue,
                ),
                title: const Text('Добавить достижение'),
                trailing: const CupertinoListTileChevron(),
                onTap: _addAchievement,
              ),
            ],
          ),
        if (config.feedbackEnabled) ...[
          const SizedBox(height: 8),
          CupertinoListSection.insetGrouped(
            margin: EdgeInsets.zero,
            header: const Text('ОБРАТНАЯ СВЯЗЬ'),
            footer: config.feedbackDescription.isNotEmpty
                ? Text(
                    config.feedbackDescription,
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  )
                : null,
            children: [
              CupertinoTextField(
                controller: _feedbackController,
                placeholder: 'Ваш отзыв',
                maxLines: 4,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: null,
              ),
            ],
          ),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: CupertinoColors.systemRed),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: CupertinoButton.filled(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                : const Text('Отправить'),
          ),
        ),
      ],
    );
  }
}

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
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${entry.type.title} · ${entry.type.pointsCost} баллов',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onRemove,
                child: const Icon(
                  CupertinoIcons.xmark_circle_fill,
                  size: 20,
                  color: CupertinoColors.systemGrey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CupertinoTextField(
            controller: entry.descriptionController,
            placeholder: 'Описание (необязательно)',
            maxLines: 2,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...entry.files.map(
                (file) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey5.resolveFrom(context),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.doc, size: 14),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () {
                          entry.files.remove(file);
                          onRebuild();
                        },
                        child: const Icon(CupertinoIcons.xmark, size: 12),
                      ),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: onAttach,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey6.resolveFrom(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: CupertinoColors.systemGrey4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.paperclip, size: 14),
                      SizedBox(width: 4),
                      Text('Прикрепить файл', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
