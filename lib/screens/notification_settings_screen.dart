import 'package:flutter/cupertino.dart';

import '../config/notification_topics.dart';
import '../services/notification_preferences_service.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/booking_glass_form.dart';

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

  Widget _iconBadge(IconData icon, Color color) =>
      AppIconBadge(icon: icon, color: color);

  @override
  Widget build(BuildContext context) {
    return BookingGlassScaffold(
      title: 'Уведомления',
      children: _isLoading
          ? const [
              SizedBox(height: 160),
              Center(child: CupertinoActivityIndicator(radius: 14)),
            ]
          : [
              const AppGlassSectionLabel(
                'Push-уведомления',
                padding: EdgeInsets.fromLTRB(20, 8, 20, 6),
              ),
              AppGlassSection(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final topic in NotificationTopics.all)
                    CupertinoListTile(
                      leading: _iconBadge(topic.icon, topic.color),
                      title: Text(topic.title, maxLines: 2, softWrap: true),
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
              const BookingFootnote(
                'Выключенные категории не будут присылать push. '
                'Настройка хранится на этом устройстве.',
              ),
            ],
    );
  }
}
