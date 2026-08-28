import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:intl/date_symbol_data_local.dart';
import 'package:url_launcher/url_launcher.dart';

import 'screens/calendar_screen.dart';
import 'screens/chats_list_screen.dart';
import 'screens/bookings_screen.dart';
import 'screens/news_feed_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/employees_screen.dart';
import 'screens/mail_screen.dart';
import 'screens/documents_signing_screen.dart';
import 'screens/connector_screen.dart';
import 'config/api_config.dart';
import 'config/app_theme.dart';
import 'config/branding.dart';
import 'repositories/profile_repository.dart';
import 'services/app_navigation_service.dart';
import 'services/auth_service.dart';
import 'services/location_gate_service.dart';
import 'services/notification_preferences_service.dart';
import 'services/push_notification_service.dart';
import 'utils/media_url_utils.dart';
import 'utils/user_display_name.dart';
import 'widgets/chat_avatar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  await ApiConfig.init();
  await AuthService.instance.init();
  await PushNotificationService.instance.init();
  runApp(const ConnectApp());
}

class ConnectApp extends StatefulWidget {
  const ConnectApp({super.key});

  @override
  State<ConnectApp> createState() => _ConnectAppState();
}

class _ConnectAppState extends State<ConnectApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (AuthService.instance.isAuthenticated) {
        await PushNotificationService.instance.registerAfterLogin();
        await NotificationPreferencesService.instance.syncAll();
        await LocationGateService.instance.verifyForCurrentUser();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AppNavigationService.navigatorKey,
      title: 'Connect — Корпоративный сервис',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru', 'RU'), Locale('en', 'US')],
      locale: const Locale('ru', 'RU'),
      initialRoute: AuthService.instance.isAuthenticated ? '/home' : '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          final initialIndex = args is Map
              ? (args['initialIndex'] as int?)
              : null;
          final openNewsId = args is Map
              ? (args['openNewsId'] as String?)
              : null;
          return MainNavigationScreen(
            initialIndex: initialIndex ?? 0,
            openNewsId: openNewsId,
          );
        },
      },
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({
    super.key,
    this.initialIndex = 0,
    this.openNewsId,
  });

  final int initialIndex;
  final String? openNewsId;

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late int _currentIndex;
  bool _isDrawerOpen = false;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 3);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppNavigationService.processPendingNavigation();
    });
    _loadDrawerProfile();
  }

  Future<void> _loadDrawerProfile() async {
    final stored = await AuthService.instance.getStoredUser();
    if (mounted && stored != null) setState(() => _profile = stored);
    try {
      final api = await ProfileRepository.instance.getProfile();
      if (mounted && api.isNotEmpty) setState(() => _profile = api);
    } catch (_) {
      // Остаёмся на закэшированных данных из getStoredUser, если API недоступен.
    }
  }

  String get _drawerDisplayName => userDisplayNameFromJson(_profile ?? const {});

  String? get _drawerAvatarUrl =>
      MediaUrlUtils.normalizeFirstUrl(_profile?['media']);

  String? get _drawerPosition {
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

  @override
  Widget build(BuildContext context) {
    final body = switch (_currentIndex) {
      0 => NewsFeedScreen(showAppBar: false, openNewsId: widget.openNewsId),
      1 => const CalendarScreen(),
      2 => const ChatsListScreen(),
      _ => const ProfileScreen(),
    };

    return Scaffold(
      key: _scaffoldKey,
      drawerScrimColor: Colors.transparent,
      onDrawerChanged: (isOpened) => setState(() => _isDrawerOpen = isOpened),
      drawer: Drawer(
        backgroundColor: AppColors.surfaceElevated,
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _DrawerHeaderCard(
                displayName: _drawerDisplayName,
                position: _drawerPosition,
                avatarUrl: _drawerAvatarUrl,
                onProfileTap: () {
                  Navigator.pop(context);
                  setState(() => _currentIndex = 3);
                },
              ),
              const SizedBox(height: 10),
              _DrawerMenuCard(
                children: [
                  _DrawerItem(
                    icon: CupertinoIcons.bookmark,
                    label: 'Бронирования',
                    selected: false,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        CupertinoPageRoute(
                          builder: (_) => const BookingsScreen(),
                        ),
                      );
                    },
                  ),
                  _DrawerItem(
                    icon: CupertinoIcons.videocam,
                    label: 'Коннектор',
                    selected: false,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        CupertinoPageRoute(
                          builder: (_) => const ConnectorScreen(),
                        ),
                      );
                    },
                  ),
                  _DrawerItem(
                    icon: CupertinoIcons.person_2,
                    label: 'Сотрудники',
                    selected: false,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        CupertinoPageRoute(
                          builder: (_) => const EmployeesScreen(),
                        ),
                      );
                    },
                  ),
                  _DrawerItem(
                    icon: CupertinoIcons.mail,
                    label: 'Почта',
                    selected: false,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(
                        context,
                      ).push(CupertinoPageRoute(builder: (_) => const MailScreen()));
                    },
                  ),
                  _DrawerItem(
                    icon: CupertinoIcons.doc_text,
                    label: 'Согласование',
                    selected: false,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        CupertinoPageRoute(
                          builder: (_) => const DocumentsSigningScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _DrawerMenuCard(
                children: [
                  _DrawerItem(
                    icon: CupertinoIcons.book,
                    label: 'База знаний',
                    selected: false,
                    isExternal: true,
                    onTap: () {
                      Navigator.pop(context);
                      launchUrl(
                        Uri.parse(
                          'https://support.xon-connect.ru/books/rukovodstvo-polzovatelia-xonconnect/page/avtorizaciia',
                        ),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final content = body;
                if (constraints.maxWidth < 900) return content;
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: content,
                  ),
                );
              },
            ),
          ),
          if (_isDrawerOpen)
            Positioned.fill(
              child: IgnorePointer(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(color: Colors.black.withValues(alpha: 0.05)),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: CupertinoTabBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          HapticFeedback.selectionClick();
          setState(() => _currentIndex = index);
        },
        backgroundColor: CupertinoColors.systemGroupedBackground
            .resolveFrom(context)
            .withValues(alpha: 0.9),
        activeColor: CupertinoColors.activeBlue,
        inactiveColor: CupertinoColors.systemGrey,
        iconSize: 26,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.square_grid_2x2),
            activeIcon: Icon(CupertinoIcons.square_grid_2x2_fill),
            label: 'Лента',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.calendar),
            label: 'Календарь',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.chat_bubble_2),
            activeIcon: Icon(CupertinoIcons.chat_bubble_2_fill),
            label: 'Чаты',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person_crop_circle),
            activeIcon: Icon(CupertinoIcons.person_crop_circle_fill),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }
}

/// Карточка-шапка меню: лого приложения + профиль текущего пользователя.
/// Белый фон карточки совпадает с фоном лого — благодаря этому у логотипа
/// больше нет шва с серой подложкой меню.
class _DrawerHeaderCard extends StatelessWidget {
  const _DrawerHeaderCard({
    required this.displayName,
    required this.position,
    required this.avatarUrl,
    required this.onProfileTap,
  });

  final String displayName;
  final String? position;
  final String? avatarUrl;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          BrandingLoginLogo(height: 32),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.outline),
          const SizedBox(height: 14),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onProfileTap,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    MemberAvatar(
                      displayName: displayName,
                      avatarUrl: avatarUrl,
                      radius: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurface,
                            ),
                          ),
                          if ((position ?? '').isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              position!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Сгруппированный список пунктов меню в виде белой карточки с обводкой —
/// вместо серого фона меню "просвечивающего" между пунктами.
class _DrawerMenuCard extends StatelessWidget {
  const _DrawerMenuCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.outline),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.isExternal = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// `true` — пункт открывает внешнюю ссылку, а не раздел приложения:
  /// вместо синей заливки показывает иконку внешней ссылки.
  final bool isExternal;

  @override
  Widget build(BuildContext context) {
    final tint = selected ? AppColors.primary : AppColors.onSurface;
    return Material(
      color: selected ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 20, color: tint),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    color: tint,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (isExternal)
                Icon(
                  CupertinoIcons.arrow_up_right_square,
                  size: 18,
                  color: AppColors.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
