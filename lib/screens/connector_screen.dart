import 'package:flutter/cupertino.dart';

import '../widgets/app_glass.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/app_title_bar.dart';
import 'create_instant_meeting_screen.dart';
import 'schedule_video_meeting_screen.dart';

/// Вкладка «Звонки» (раздел Коннектора): мгновенная встреча или
/// планирование в календаре.
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
      padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 14, 10),
      leading: AppIconBadge(icon: icon, color: color),
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
    return AppGlassBarBlur(
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: '.SF Pro Text',
            decoration: TextDecoration.none,
            color: CupertinoColors.label.resolveFrom(context),
            fontSize: 16,
          ),
          child: Stack(
            children: [
              const AppGlassGlow(),
              CustomScrollView(
                slivers: [
                  AppSliverTitleBar(
                    title: const Text('Звонки'),
                    blur: blur,
                  ),
                  const SliverToBoxAdapter(
                    child: AppGlassSectionLabel(
                      'Видеоконференции',
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 6),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: AppGlassSection(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        _actionTile(
                          icon: CupertinoIcons.video_camera_solid,
                          color: CupertinoColors.systemBlue,
                          title: 'Создать видеовстречу',
                          subtitle: 'Пригласить участников и сразу начать',
                          onTap: _openCreateInstant,
                        ),
                        _actionTile(
                          icon: CupertinoIcons.calendar_badge_plus,
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
            ],
          ),
        ),
      ),
    );
  }
}
