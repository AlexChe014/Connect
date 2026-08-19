import 'package:flutter/cupertino.dart';

import '../config/notification_topics.dart';
import '../services/notification_preferences_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  Map<String, bool> _values = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = <String, bool>{};
    for (final topic in NotificationTopics.all) {
      values[topic.id] = await NotificationPreferencesService.instance
          .isEnabled(topic.id);
    }
    if (!mounted) return;
    setState(() {
      _values = values;
      _isLoading = false;
    });
  }

  Future<void> _toggle(String topicId, bool value) async {
    setState(() => _values = {..._values, topicId: value});
    await NotificationPreferencesService.instance.setEnabled(topicId, value);
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
      child: Icon(icon, size: 16, color: CupertinoColors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Уведомления'),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 16,
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CupertinoActivityIndicator(radius: 14))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'PUSH-УВЕДОМЛЕНИЯ',
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    CupertinoListSection.insetGrouped(
                      margin: EdgeInsets.zero,
                      children: [
                        for (final topic in NotificationTopics.all)
                          CupertinoListTile(
                            leading: _iconBadge(topic.icon, topic.color),
                            title: Text(
                              topic.title,
                              maxLines: 2,
                              softWrap: true,
                            ),
                            subtitle: Text(
                              topic.description,
                              maxLines: 2,
                              softWrap: true,
                            ),
                            trailing: CupertinoSwitch(
                              value: _values[topic.id] ?? true,
                              onChanged: (value) => _toggle(topic.id, value),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Выключенные категории не будут присылать push. '
                        'Настройка хранится на этом устройстве.',
                        style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
