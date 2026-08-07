import 'package:flutter/material.dart';

import '../config/app_icons.dart';
import '../models/news_item.dart';
import '../repositories/news_repository.dart';

enum NewsPeopleKind { likers, viewers }

/// Bottom sheet со списком лайкнувших или посмотревших новость.
class NewsPeopleSheet extends StatefulWidget {
  const NewsPeopleSheet({
    super.key,
    required this.newsId,
    required this.kind,
  });

  final String newsId;
  final NewsPeopleKind kind;

  static Future<void> show(
    BuildContext context, {
    required String newsId,
    required NewsPeopleKind kind,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: NewsPeopleSheet(newsId: newsId, kind: kind),
      ),
    );
  }

  @override
  State<NewsPeopleSheet> createState() => _NewsPeopleSheetState();
}

class _NewsPeopleSheetState extends State<NewsPeopleSheet> {
  bool _loading = true;
  String? _error;
  List<NewsAuthor> _people = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await NewsRepository.instance.getPeople(widget.newsId);
      if (!mounted) return;
      setState(() {
        _people = widget.kind == NewsPeopleKind.likers
            ? result.likers
            : result.viewers;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = widget.kind == NewsPeopleKind.likers
            ? 'Не удалось загрузить лайки'
            : 'Не удалось загрузить просмотры';
      });
    }
  }

  String get _title =>
      widget.kind == NewsPeopleKind.likers ? 'Лайкнули' : 'Посмотрели';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            _title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      );
    }
    if (_people.isEmpty) {
      return Center(
        child: Text(
          widget.kind == NewsPeopleKind.likers
              ? 'Пока никто не лайкнул'
              : 'Пока никто не посмотрел',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _people.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final person = _people[index];
        final hasAvatar =
            person.avatarUrl != null && person.avatarUrl!.trim().isNotEmpty;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            backgroundImage: hasAvatar ? NetworkImage(person.avatarUrl!) : null,
            child: hasAvatar
                ? null
                : AppIcon(
                    AppIcons.user,
                    size: 20,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
          ),
          title: Text(person.fullName),
        );
      },
    );
  }
}
