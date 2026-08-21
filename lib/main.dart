import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
import 'services/app_navigation_service.dart';
import 'services/auth_service.dart';
import 'services/location_gate_service.dart';
import 'services/notification_preferences_service.dart';
import 'services/push_notification_service.dart';

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
        await PushNotificationService.instance.requestPermissions();
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
          final homeSection = args is Map
              ? (args['homeSection'] as String?)
              : null;
          final openNewsId = args is Map
              ? (args['openNewsId'] as String?)
              : null;
          return MainNavigationScreen(
            initialIndex: initialIndex ?? 0,
            initialHomeSection: homeSection,
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
    this.initialHomeSection,
    this.openNewsId,
  });

  final int initialIndex;
  final String? initialHomeSection;
  final String? openNewsId;

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

enum _HomeSection { news, bookings, connector, employees, mail, documents }

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late int _currentIndex;
  late _HomeSection _homeSection;
  bool _isDrawerOpen = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 3);
    _homeSection = _parseHomeSection(widget.initialHomeSection);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppNavigationService.processPendingNavigation();
    });
  }

  _HomeSection _parseHomeSection(String? value) {
    return switch (value) {
      'bookings' => _HomeSection.bookings,
      'connector' => _HomeSection.connector,
      'employees' => _HomeSection.employees,
      'mail' => _HomeSection.mail,
      'documents' => _HomeSection.documents,
      _ => _HomeSection.news,
    };
  }

  Widget _homeBody() {
    switch (_homeSection) {
      case _HomeSection.news:
        return NewsFeedScreen(showAppBar: false, openNewsId: widget.openNewsId);
      case _HomeSection.bookings:
        return const BookingsScreen(showAppBar: false);
      case _HomeSection.connector:
        return const ConnectorScreen(showAppBar: false);
      case _HomeSection.employees:
        return const EmployeesScreen(showAppBar: false);
      case _HomeSection.mail:
        return const MailScreen(showAppBar: false);
      case _HomeSection.documents:
        return const DocumentsSigningScreen(showAppBar: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_currentIndex) {
      0 => _homeBody(),
      1 => const CalendarScreen(),
      2 => const ChatsListScreen(),
      _ => const ProfileScreen(),
    };

    return Scaffold(
      key: _scaffoldKey,
      drawerScrimColor: Colors.transparent,
      onDrawerChanged: (isOpened) => setState(() => _isDrawerOpen = isOpened),
      drawer: Drawer(
        backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
          context,
        ),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Column(children: [BrandingLoginLogo(height: 56)]),
              ),
              CupertinoListSection.insetGrouped(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _DrawerItem(
                    icon: CupertinoIcons.square_grid_2x2,
                    label: 'Лента',
                    selected:
                        _currentIndex == 0 && _homeSection == _HomeSection.news,
                    onTap: () {
                      setState(() {
                        _homeSection = _HomeSection.news;
                        _currentIndex = 0;
                      });
                      Navigator.pop(context);
                    },
                  ),
                  _DrawerItem(
                    icon: CupertinoIcons.bookmark,
                    label: 'Бронирования',
                    selected:
                        _currentIndex == 0 &&
                        _homeSection == _HomeSection.bookings,
                    onTap: () {
                      setState(() {
                        _homeSection = _HomeSection.bookings;
                        _currentIndex = 0;
                      });
                      Navigator.pop(context);
                    },
                  ),
                  _DrawerItem(
                    icon: CupertinoIcons.videocam,
                    label: 'Коннектор',
                    selected:
                        _currentIndex == 0 &&
                        _homeSection == _HomeSection.connector,
                    onTap: () {
                      setState(() {
                        _homeSection = _HomeSection.connector;
                        _currentIndex = 0;
                      });
                      Navigator.pop(context);
                    },
                  ),
                  _DrawerItem(
                    icon: CupertinoIcons.person_2,
                    label: 'Сотрудники',
                    selected:
                        _currentIndex == 0 &&
                        _homeSection == _HomeSection.employees,
                    onTap: () {
                      setState(() {
                        _homeSection = _HomeSection.employees;
                        _currentIndex = 0;
                      });
                      Navigator.pop(context);
                    },
                  ),
                  _DrawerItem(
                    icon: CupertinoIcons.mail,
                    label: 'Почта',
                    selected:
                        _currentIndex == 0 && _homeSection == _HomeSection.mail,
                    onTap: () {
                      setState(() {
                        _homeSection = _HomeSection.mail;
                        _currentIndex = 0;
                      });
                      Navigator.pop(context);
                    },
                  ),
                  _DrawerItem(
                    icon: CupertinoIcons.doc_text,
                    label: 'Согласование',
                    selected:
                        _currentIndex == 0 &&
                        _homeSection == _HomeSection.documents,
                    onTap: () {
                      setState(() {
                        _homeSection = _HomeSection.documents;
                        _currentIndex = 0;
                      });
                      Navigator.pop(context);
                    },
                  ),
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
          if (index == 0) {
            _scaffoldKey.currentState?.openDrawer();
            return;
          }
          setState(() => _currentIndex = index);
        },
        backgroundColor: CupertinoColors.systemGroupedBackground
            .resolveFrom(context)
            .withValues(alpha: 0.94),
        activeColor: CupertinoColors.activeBlue,
        inactiveColor: CupertinoColors.systemGrey,
        iconSize: 26,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.line_horizontal_3),
            label: 'Меню',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.calendar),
            label: 'Календарь',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.chat_bubble_2),
            label: 'Чаты',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person_crop_circle),
            label: 'Профиль',
          ),
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
  /// вместо галочки «выбрано» показывает иконку внешней ссылки.
  final bool isExternal;

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      onTap: onTap,
      leading: Icon(icon, size: 22, color: CupertinoColors.activeBlue),
      title: Text(label),
      trailing: isExternal
          ? Icon(
              CupertinoIcons.arrow_up_right_square,
              size: 18,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            )
          : selected
          ? const Icon(
              CupertinoIcons.checkmark_alt,
              size: 20,
              color: CupertinoColors.activeBlue,
            )
          : null,
    );
  }
}
