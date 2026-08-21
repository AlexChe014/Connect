import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;
import 'package:url_launcher/url_launcher.dart';

import '../config/app_icons.dart';
import '../repositories/videoconference_repository.dart';
import '../services/api_client.dart';
import 'schedule_video_meeting_screen.dart';

/// Раздел «Коннектор»: мгновенная встреча или планирование в календаре.
class ConnectorScreen extends StatefulWidget {
  const ConnectorScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<ConnectorScreen> createState() => _ConnectorScreenState();
}

class _ConnectorScreenState extends State<ConnectorScreen> {
  bool _isCreatingInstant = false;

  Future<void> _createInstantMeeting() async {
    if (_isCreatingInstant) return;
    setState(() => _isCreatingInstant = true);
    try {
      final now = DateTime.now();
      final meeting = await VideoconferenceRepository.instance.create(
        topic: 'Видеовстреча',
        startSeconds: now.millisecondsSinceEpoch ~/ 1000,
      );
      if (!mounted) return;
      final uri = Uri.tryParse(meeting.url);
      if (uri == null) {
        _showMessage('Некорректная ссылка на конференцию');
        return;
      }
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        _showMessage('Не удалось открыть конференцию');
      }
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : 'Не удалось создать видеовстречу';
      _showMessage(message);
    } finally {
      if (mounted) setState(() => _isCreatingInstant = false);
    }
  }

  void _openSchedule() {
    Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (context) => const ScheduleVideoMeetingScreen(),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _actionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool busy = false,
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
        child: busy
            ? const CupertinoActivityIndicator(radius: 9)
            : Icon(icon, size: 18, color: color),
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
      onTap: busy ? null : onTap,
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
                    subtitle: 'Мгновенно открыть окно конференции',
                    busy: _isCreatingInstant,
                    onTap: _createInstantMeeting,
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
