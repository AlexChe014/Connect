import 'package:flutter/cupertino.dart';

import '../config/app_icons.dart';
import 'create_instant_meeting_screen.dart';
import 'schedule_video_meeting_screen.dart';

/// Раздел «Коннектор»: мгновенная встреча или планирование в календаре.
class ConnectorScreen extends StatefulWidget {
  const ConnectorScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<ConnectorScreen> createState() => _ConnectorScreenState();
}

class _ConnectorScreenState extends State<ConnectorScreen> {
  void _openCreateInstant() {
    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (context) => const CreateInstantMeetingScreen(),
      ),
    );
  }

  void _openSchedule() {
    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (context) => const ScheduleVideoMeetingScreen(),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return CupertinoListTile(
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
      trailing: const CupertinoListTileChevron(),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 16,
        ),
        child: CustomScrollView(
          slivers: [
            const CupertinoSliverNavigationBar(
              largeTitle: Text('Коннектор'),
              backgroundColor: CupertinoColors.systemGroupedBackground,
              border: null,
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  'Видеоконференции ConnectHub',
                  style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: CupertinoListSection.insetGrouped(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  _actionTile(
                    icon: AppIcons.videoMeeting,
                    color: CupertinoColors.systemBlue,
                    title: 'Создать видеовстречу',
                    subtitle: 'Пригласить участников и сразу начать',
                    onTap: _openCreateInstant,
                  ),
                  _actionTile(
                    icon: AppIcons.scheduleMeeting,
                    color: CupertinoColors.systemOrange,
                    title: 'Запланировать видеовстречу',
                    subtitle: 'Создать запись в календаре с участниками',
                    onTap: _openSchedule,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
