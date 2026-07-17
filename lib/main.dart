import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/calendar_screen.dart';
import 'screens/chats_list_screen.dart';
import 'screens/bookings_screen.dart';
import 'screens/news_feed_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/employees_screen.dart';
import 'screens/mail_screen.dart';
import 'screens/documents_signing_screen.dart';
import 'config/app_icons.dart';
import 'config/app_theme.dart';
import 'config/branding.dart';
import 'services/app_navigation_service.dart';
import 'services/auth_service.dart';
import 'services/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  await AuthService.instance.init();
  await PushNotificationService.instance.init();
  runApp(const ConnectApp());
}

class ConnectApp extends StatelessWidget {
  const ConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AppNavigationService.navigatorKey,
      title: 'Connect — Бронирования',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ru', 'RU'),
        Locale('en', 'US'),
      ],
      locale: const Locale('ru', 'RU'),
      initialRoute: AuthService.instance.isAuthenticated ? '/home' : '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          final initialIndex =
              args is Map ? (args['initialIndex'] as int?) : null;
          final homeSection =
              args is Map ? (args['homeSection'] as String?) : null;
          final openNewsId =
              args is Map ? (args['openNewsId'] as String?) : null;
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

enum _HomeSection { news, bookings, employees, mail, documents }

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late int _currentIndex;
  late _HomeSection _homeSection;

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
      'employees' => _HomeSection.employees,
      'mail' => _HomeSection.mail,
      'documents' => _HomeSection.documents,
      _ => _HomeSection.news,
    };
  }

  Widget _homeBody() {
    switch (_homeSection) {
      case _HomeSection.news:
        return NewsFeedScreen(
          showAppBar: false,
          openNewsId: widget.openNewsId,
        );
      case _HomeSection.bookings:
        return const BookingsScreen(showAppBar: false);
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
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Column(
                  children: [
                    BrandingLoginLogo(height: 56),
                    const SizedBox(height: 10),
                    const Text(
                      'Меню',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              ListTileTheme(
                data: const ListTileThemeData(
                  tileColor: Colors.transparent,
                  selectedTileColor: Colors.transparent, // no background in menu
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const AppIcon(AppIcons.news),
                      title: const Text('Новости'),
                      selected: _homeSection == _HomeSection.news,
                      onTap: () {
                        setState(() {
                          _homeSection = _HomeSection.news;
                          _currentIndex = 0;
                        });
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      leading: const AppIcon(AppIcons.bookings),
                      title: const Text('Бронирования'),
                      selected: _homeSection == _HomeSection.bookings,
                      onTap: () {
                        setState(() {
                          _homeSection = _HomeSection.bookings;
                          _currentIndex = 0;
                        });
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      leading: const AppIcon(AppIcons.users),
                      title: const Text('Сотрудники'),
                      selected: _homeSection == _HomeSection.employees,
                      onTap: () {
                        setState(() {
                          _homeSection = _HomeSection.employees;
                          _currentIndex = 0;
                        });
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      leading: const AppIcon(AppIcons.mailAt),
                      title: const Text('Почта'),
                      selected: _homeSection == _HomeSection.mail,
                      onTap: () {
                        setState(() {
                          _homeSection = _HomeSection.mail;
                          _currentIndex = 0;
                        });
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      leading: const AppIcon(AppIcons.documents),
                      title: const Text('Подписание'),
                      selected: _homeSection == _HomeSection.documents,
                      onTap: () {
                        setState(() {
                          _homeSection = _HomeSection.documents;
                          _currentIndex = 0;
                        });
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: body,
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surfaceElevated,
          border: Border(top: BorderSide(color: AppColors.outline)),
        ),
        child: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          if (index == 0) {
            _scaffoldKey.currentState?.openDrawer();
            return;
          }
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: _LogoNavIcon(selected: false),
            selectedIcon: _LogoNavIcon(selected: true),
            label: '',
          ),
          NavigationDestination(
            icon: AppIcon(AppIcons.calendar),
            selectedIcon: AppIcon(AppIcons.calendar),
            label: '',
          ),
          NavigationDestination(
            icon: AppIcon(AppIcons.chat),
            selectedIcon: AppIcon(AppIcons.chat),
            label: '',
          ),
          NavigationDestination(
            icon: AppIcon(AppIcons.user),
            selectedIcon: AppIcon(AppIcons.user),
            label: '',
          ),
        ],
      ),
      ),
    );
  }
}

class _LogoNavIcon extends StatelessWidget {
  const _LogoNavIcon({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = selected ? scheme.primary : scheme.outline.withValues(alpha: 0.45);
    final fill = selected ? scheme.primary.withValues(alpha: 0.10) : Colors.transparent;
    final fg = selected ? scheme.primary : scheme.onSurface.withValues(alpha: 0.70);

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 1.5),
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        BrandingAssets.loginLogoPng,
        width: 22,
        height: 22,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            AppIcon(AppIcons.dashboard, size: 18, color: fg),
      ),
    );
  }
}
