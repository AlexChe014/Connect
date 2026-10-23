import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../repositories/profile_repository.dart';
import '../services/auth_service.dart';
import '../services/document_pending_service.dart';
import '../services/notification_unread_service.dart';
import '../services/survey_pending_service.dart';
import '../services/theme_mode_service.dart';
import '../utils/media_url_utils.dart';
import '../utils/user_display_name.dart';
import '../widgets/app_glass.dart';
import '../widgets/app_icon_badge.dart';
import '../widgets/chat_avatar.dart';
import 'bonus_program_screen.dart';
import 'bookings_screen.dart';
import 'calendar_screen.dart';
import 'disk_screen.dart';
import 'documents_signing_screen.dart';
import 'employees_screen.dart';
import 'favorites_screen.dart';
import 'global_search_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'surveys_screen.dart';

/// Вкладка «Ещё»: профиль, поиск и все разделы, которым не хватило места
/// в нижнем меню, — список в духе «Настроек» iOS вместо бокового меню.
/// Без крупного заголовка: «Ещё» уже подписано на вкладке, а наверху
/// сразу карточка профиля. Иконки — мягкие цветные подложки, как в профиле.
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  static const _knowledgeBaseUrl =
      'https://support.xon-connect.ru/books/rukovodstvo-polzovatelia-xonconnect/page/avtorizaciia';

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  Map<String, dynamic>? _profile;
  final _pending = DocumentPendingService.instance;
  final _surveys = SurveyPendingService.instance;
  final _notifications = NotificationUnreadService.instance;

  @override
  void initState() {
    super.initState();
    _pending.addListener(_onPendingChanged);
    _surveys.addListener(_onPendingChanged);
    _notifications.addListener(_onPendingChanged);
    _loadProfile();
  }

  @override
  void dispose() {
    _pending.removeListener(_onPendingChanged);
    _surveys.removeListener(_onPendingChanged);
    _notifications.removeListener(_onPendingChanged);
    super.dispose();
  }

  void _onPendingChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadProfile() async {
    final stored = await AuthService.instance.getStoredUser();
    if (mounted && stored != null) setState(() => _profile = stored);
    try {
      final api = await ProfileRepository.instance.getProfile();
      if (mounted && api.isNotEmpty) setState(() => _profile = api);
    } catch (_) {
      // Остаёмся на закэшированных данных из getStoredUser, если API недоступен.
    }
  }

  String? get _position {
    final p = _profile;
    if (p == null) return null;
    for (final key in ['position', 'job_title', 'post', 'appointment']) {
      final raw = p[key];
      if (raw == null) continue;
      if (raw is Map) {
        final v = raw['name'] ?? raw['title'] ?? raw['label'];
        final t = v?.toString().trim();
        if (t != null && t.isNotEmpty) return t;
        continue;
      }
      final t = raw.toString().trim();
      if (t.isNotEmpty && !t.startsWith('{')) return t;
    }
    return null;
  }

  Future<void> _open(Widget screen) {
    return Navigator.of(
      context,
    ).push<void>(CupertinoPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _openProfile() async {
    await _open(const ProfileScreen());
    // Аватар и должность могли поменяться в профиле.
    if (mounted) _loadProfile();
  }

  Widget _profileCard(BuildContext context) {
    final name = userDisplayNameFromJson(_profile ?? const {});
    final position = _position;
    return CupertinoListTile(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 14, 12),
      leadingSize: 56,
      leading: MemberAvatar(
        displayName: name,
        avatarUrl: MediaUrlUtils.normalizeFirstUrl(_profile?['media']),
        radius: 28,
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        (position ?? '').isNotEmpty ? position! : 'Профиль',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
      trailing: const CupertinoListTileChevron(),
      onTap: _openProfile,
    );
  }

  /// Поле-кнопка: сам поиск живёт на отдельном экране.
  Widget _searchField() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(const GlobalSearchScreen()),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: AbsorbPointer(
          child: CupertinoSearchTextField(
            placeholder: 'Люди, чаты, письма, файлы…',
            enabled: false,
          ),
        ),
      ),
    );
  }

  Widget _item({
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
    int badgeCount = 0,
    bool isExternal = false,
  }) {
    return CupertinoListTile(
      leading: AppIconBadge(icon: icon, color: color),
      title: Text(title),
      additionalInfo: badgeCount > 0 ? _Badge(count: badgeCount) : null,
      trailing: isExternal
          ? Icon(
              CupertinoIcons.arrow_up_right,
              size: 16,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            )
          : const CupertinoListTileChevron(),
      onTap: onTap,
    );
  }

  static const _themeModeLabels = {
    ThemeMode.light: 'Светлое',
    ThemeMode.dark: 'Тёмное',
    ThemeMode.system: 'Как в системе',
  };

  Future<void> _pickThemeMode() async {
    final current = ThemeModeService.instance.mode.value;
    final choice = await showCupertinoModalPopup<ThemeMode>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Оформление'),
        actions: [
          for (final entry in _themeModeLabels.entries)
            CupertinoActionSheetAction(
              isDefaultAction: entry.key == current,
              onPressed: () => Navigator.pop(context, entry.key),
              child: Text(entry.value),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (choice != null) await ThemeModeService.instance.setMode(choice);
  }

  Widget _themeModeItem(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeModeService.instance.mode,
      builder: (context, mode, _) => CupertinoListTile(
        leading: AppIconBadge(
          icon: CupertinoIcons.circle_lefthalf_fill,
          color: CupertinoColors.systemIndigo.resolveFrom(context),
        ),
        title: const Text('Оформление'),
        additionalInfo: Text(_themeModeLabels[mode]!),
        trailing: const CupertinoListTileChevron(),
        onTap: _pickThemeMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppGlassBarBlur(
      builder: (context, blur) => CupertinoPageScaffold(
        backgroundColor: AppColors.groupedBackground.resolveFrom(context),
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
                  SliverToBoxAdapter(
                    child: AppGlassSection(
                      margin: EdgeInsets.fromLTRB(
                        16,
                        MediaQuery.paddingOf(context).top + 16,
                        16,
                        0,
                      ),
                      children: [_profileCard(context)],
                    ),
                  ),
                  SliverToBoxAdapter(child: _searchField()),
                  SliverToBoxAdapter(
                    child: AppGlassSection(
                      children: [
                        _item(
                          icon: CupertinoIcons.bell_fill,
                          color: CupertinoColors.systemRed.resolveFrom(context),
                          title: 'Уведомления',
                          badgeCount: _notifications.unreadCount,
                          onTap: () => _open(const NotificationsScreen()),
                        ),
                      ],
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: AppGlassSection(
                      children: [
                        _item(
                          icon: CupertinoIcons.calendar,
                          color: CupertinoColors.systemRed.resolveFrom(context),
                          title: 'Календарь',
                          onTap: () => _open(const CalendarScreen()),
                        ),
                        _item(
                          icon: CupertinoIcons.doc_text_fill,
                          color: CupertinoColors.systemOrange.resolveFrom(
                            context,
                          ),
                          title: 'Согласование',
                          badgeCount: _pending.totalCount,
                          onTap: () => _open(const DocumentsSigningScreen()),
                        ),
                        _item(
                          icon: CupertinoIcons.chart_bar_square_fill,
                          color: CupertinoColors.systemPurple.resolveFrom(
                            context,
                          ),
                          title: 'Опросы',
                          badgeCount: _surveys.pendingCount,
                          onTap: () => _open(const SurveysScreen()),
                        ),
                        _item(
                          icon: CupertinoIcons.person_2_fill,
                          color: CupertinoColors.systemBlue.resolveFrom(
                            context,
                          ),
                          title: 'Сотрудники',
                          onTap: () => _open(const EmployeesScreen()),
                        ),
                        _item(
                          icon: CupertinoIcons.bookmark_fill,
                          color: CupertinoColors.systemIndigo.resolveFrom(
                            context,
                          ),
                          title: 'Бронирования',
                          onTap: () => _open(const BookingsScreen()),
                        ),
                        _item(
                          icon: CupertinoIcons.folder_fill,
                          color: CupertinoColors.systemTeal.resolveFrom(
                            context,
                          ),
                          title: 'Диск',
                          onTap: () => _open(const DiskScreen()),
                        ),
                      ],
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: AppGlassSection(
                      children: [
                        _item(
                          icon: CupertinoIcons.star_fill,
                          color: CupertinoColors.systemYellow.resolveFrom(
                            context,
                          ),
                          title: 'Избранное',
                          onTap: () => _open(const FavoritesScreen()),
                        ),
                        _item(
                          icon: CupertinoIcons.gift_fill,
                          color: CupertinoColors.systemPink.resolveFrom(
                            context,
                          ),
                          title: 'Бонусная программа',
                          onTap: () => _open(const BonusProgramScreen()),
                        ),
                      ],
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: AppGlassSection(
                      margin: EdgeInsets.fromLTRB(
                        16,
                        20,
                        16,
                        MediaQuery.paddingOf(context).bottom + 32,
                      ),
                      children: [
                        _themeModeItem(context),
                        _item(
                          icon: CupertinoIcons.book_fill,
                          color: CupertinoColors.systemGrey.resolveFrom(
                            context,
                          ),
                          title: 'База знаний',
                          isExternal: true,
                          onTap: () => launchUrl(
                            Uri.parse(MoreScreen._knowledgeBaseUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Шапки нет — под статус-баром размываем уехавший контент,
              // чтобы он не мешался с часами и индикаторами.
              if (blur)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.paddingOf(context).top,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: ColoredBox(
                        color: AppColors.groupedBackground
                            .resolveFrom(context)
                            .withValues(alpha: 0.7),
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

/// Красный счётчик в строке раздела — как бейдж непрочитанного в «Настройках».
class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: CupertinoColors.systemRed.resolveFrom(context),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: CupertinoColors.white,
        ),
      ),
    );
  }
}
