import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/news_item.dart';
import '../repositories/news_repository.dart';
import '../services/auth_service.dart';
import 'chat_avatar.dart';

/// Эмодзи, которые предлагаются в пикере. Сервер принимает любую строку
/// до 32 символов, поэтому список — только набор быстрых вариантов.
const List<String> kNewsQuickReactions = [
  '👍',
  '❤️',
  '🔥',
  '👏',
  '😂',
  '🎉',
  '😮',
  '😢',
];

/// Ставит/меняет/снимает реакцию [emoji] на [news] с оптимистичным
/// обновлением: [onUpdate] сразу получает локально пересчитанный пост, а после
/// ответа сервера — итоговый. При ошибке пост откатывается и ошибка
/// пробрасывается дальше.
Future<void> toggleNewsReaction(
  NewsItem news,
  String emoji, {
  required void Function(NewsItem news) onUpdate,
}) async {
  final me = await _currentAuthor();
  final expected = news.myReaction == emoji ? null : emoji;
  onUpdate(news.withMyReaction(expected, me: me));
  try {
    final actual = await NewsRepository.instance.toggleReaction(news.id, emoji);
    if (actual != expected) onUpdate(news.withMyReaction(actual, me: me));
  } catch (_) {
    onUpdate(news);
    rethrow;
  }
}

Future<NewsAuthor?> _currentAuthor() async {
  try {
    final user = await AuthService.instance.getStoredUser();
    if (user == null || user['id'] == null) return null;
    return NewsAuthor.fromJson(user);
  } catch (_) {
    return null;
  }
}

/// Общая высота чипов реакций, кнопки «смайлик» и счётчиков просмотров/
/// комментариев: раньше высота чипа зависела от метрик эмодзи, и ряд под
/// постом «плясал» от поста к посту.
const double kNewsReactionRowHeight = 32;

/// Ряд реакций под постом: чипы «эмодзи + счётчик» (своя реакция
/// подсвечена) и кнопка выбора новой реакции.
///
/// Тап по чипу ставит/снимает эту реакцию, долгое нажатие показывает, кто
/// её поставил. У пользователя на посте может быть только одна реакция.
class NewsReactionsBar extends StatelessWidget {
  const NewsReactionsBar({
    super.key,
    required this.news,
    required this.onToggle,
    this.isLoading = false,
  });

  final NewsItem news;
  final bool isLoading;
  final void Function(String emoji) onToggle;

  void _toggle(String emoji) {
    if (isLoading) return;
    HapticFeedback.lightImpact();
    onToggle(emoji);
  }

  Future<void> _openPicker(BuildContext context) async {
    if (isLoading) return;
    final picked = await showNewsReactionPicker(
      context,
      active: news.myReaction,
    );
    if (picked != null) _toggle(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final r in news.reactions)
          _ReactionChip(
            reaction: r,
            selected: r.emoji == news.myReaction,
            onTap: () => _toggle(r.emoji),
            onLongPress: () => NewsReactionsSheet.show(
              context,
              reactions: news.reactions,
              initialEmoji: r.emoji,
            ),
          ),
        _AddReactionButton(
          isLoading: isLoading,
          onTap: () => _openPicker(context),
        ),
      ],
    );
  }
}

/// Пикер реакции. Возвращает выбранный эмодзи (выбор уже активного снимет
/// реакцию на сервере) или `null`, если пользователь закрыл пикер.
Future<String?> showNewsReactionPicker(BuildContext context, {String? active}) {
  return showCupertinoModalPopup<String>(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: const Text('Реакция'),
      message: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final emoji in kNewsQuickReactions)
            Semantics(
              button: true,
              selected: emoji == active,
              label: emoji,
              child: GestureDetector(
                onTap: () => Navigator.pop(context, emoji),
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: emoji == active
                        ? CupertinoColors.activeBlue.withValues(alpha: 0.18)
                        : null,
                    shape: BoxShape.circle,
                  ),
                  // `message` у CupertinoActionSheet рисуется полупрозрачным
                  // серым, и цветные эмодзи наследуют эту прозрачность —
                  // выглядят выключенными. Цвет задаём явно, непрозрачный.
                  child: Text(
                    emoji,
                    style: TextStyle(
                      fontSize: 28,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: [
        if (active != null)
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, active),
            child: const Text('Убрать реакцию'),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
    ),
  );
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.reaction,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final NewsReaction reaction;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoColors.activeBlue.resolveFrom(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${reaction.emoji} ${reaction.count}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: kNewsReactionRowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : CupertinoColors.tertiarySystemFill.resolveFrom(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent : const Color(0x00000000),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                reaction.emoji,
                style: TextStyle(
                  fontSize: 15,
                  height: 1,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '${reaction.count}',
                style: TextStyle(
                  fontSize: 13,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: selected
                      ? accent
                      : CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddReactionButton extends StatelessWidget {
  const _AddReactionButton({required this.isLoading, required this.onTap});

  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Поставить реакцию',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 40,
          height: kNewsReactionRowHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
            borderRadius: BorderRadius.circular(16),
          ),
          child: isLoading
              ? const CupertinoActivityIndicator(radius: 7)
              : Icon(
                  CupertinoIcons.smiley,
                  size: 18,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
        ),
      ),
    );
  }
}

/// Счётчик рядом с реакциями (просмотры, комментарии) той же высоты, что
/// и чипы реакций, — чтобы ряд под постом стоял на одной линии.
class NewsStatChip extends StatelessWidget {
  const NewsStatChip({super.key, required this.icon, this.label, this.onTap});

  final IconData icon;
  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = CupertinoColors.secondaryLabel.resolveFrom(context);
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      minimumSize: const Size(0, kNewsReactionRowHeight),
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          if (label != null) ...[
            const SizedBox(width: 4),
            Text(
              label!,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet «Кто отреагировал»: фильтр по эмодзи и список людей.
/// Данные берутся из уже загруженного поста — отдельного GET для реакций нет.
class NewsReactionsSheet extends StatefulWidget {
  const NewsReactionsSheet({
    super.key,
    required this.reactions,
    this.initialEmoji,
  });

  final List<NewsReaction> reactions;
  final String? initialEmoji;

  static Future<void> show(
    BuildContext context, {
    required List<NewsReaction> reactions,
    String? initialEmoji,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: NewsReactionsSheet(
          reactions: reactions,
          initialEmoji: initialEmoji,
        ),
      ),
    );
  }

  @override
  State<NewsReactionsSheet> createState() => _NewsReactionsSheetState();
}

class _NewsReactionsSheetState extends State<NewsReactionsSheet> {
  /// `null` — показываем все реакции.
  late String? _filter = widget.initialEmoji;

  List<({NewsAuthor user, String emoji})> get _rows => [
    for (final r in widget.reactions)
      if (_filter == null || r.emoji == _filter)
        for (final u in r.users) (user: u, emoji: r.emoji),
  ];

  @override
  Widget build(BuildContext context) {
    final total = widget.reactions.fold(0, (sum, r) => sum + r.count);
    final rows = _rows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'Реакции',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _FilterChip(
                label: 'Все $total',
                selected: _filter == null,
                onTap: () => setState(() => _filter = null),
              ),
              for (final r in widget.reactions)
                _FilterChip(
                  label: '${r.emoji} ${r.count}',
                  selected: _filter == r.emoji,
                  onTap: () => setState(() => _filter = r.emoji),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    'Пока нет реакций',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      leading: MemberAvatar(
                        displayName: row.user.fullName,
                        avatarUrl: row.user.avatarUrl,
                      ),
                      title: Text(row.user.fullName),
                      trailing: Text(
                        row.emoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoColors.activeBlue.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : CupertinoColors.tertiarySystemFill.resolveFrom(context),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected
                  ? accent
                  : CupertinoColors.label.resolveFrom(context),
            ),
          ),
        ),
      ),
    );
  }
}
