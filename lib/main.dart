import 'dart:async';
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
import 'screens/favorites_screen.dart';
import 'screens/mail_screen.dart';
import 'screens/documents_signing_screen.dart';
import 'screens/connector_screen.dart';
import 'screens/disk_screen.dart';
import 'screens/global_search_screen.dart';
import 'screens/bonus_program_screen.dart';
import 'config/api_config.dart';
import 'config/app_theme.dart';
import 'widgets/app_glass.dart';
import 'config/branding.dart';
import 'models/chat.dart';
import 'repositories/profile_repository.dart';
import 'services/app_navigation_service.dart';
import 'services/auth_service.dart';
import 'services/branding_service.dart';
import 'services/chat_service.dart';
import 'services/chat_realtime_service.dart';
import 'services/crash_reporting_service.dart';
import 'services/incoming_call_service.dart';
import 'services/mail_unread_service.dart';
import 'services/document_pending_service.dart';
import 'services/notification_preferences_service.dart';
import 'services/push_notification_service.dart';
import 'services/root_stack_observer.dart';
import 'services/user_presence_service.dart';
import 'services/vpn_detector_service.dart';
import 'utils/media_url_utils.dart';
import 'utils/user_display_name.dart';
import 'widgets/chat_avatar.dart';
import 'widgets/home_shortcut_button.dart';
import 'widgets/vpn_banner.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(AppTheme.systemUiOverlay);
    await initializeDateFormatting('ru_RU', null);
    await ApiConfig.init();
    await AuthService.instance.init();
    await BrandingService.instance.init();
    // Инициализирует Firebase (нужен для CrashReportingService ниже).
    await PushNotificationService.instance.init();
    await IncomingCallService.instance.init();
    VpnDetectorService.instance.start();
    await CrashReportingService.init();
    runApp(const ConnectApp());
  }, CrashReportingService.recordError);
}

class ConnectApp extends StatefulWidget {
  const ConnectApp({super.key});

  @override
  State<ConnectApp> createState() => _ConnectAppState();
}

class _ConnectAppState extends State<ConnectApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AuthService.instance.onSessionExpired = () {
      UserPresenceService.instance.reset();
      unawaited(ChatRealtimeService.instance.stop());
      unawaited(PushNotificationService.instance.disableLocally());
      AppNavigationService.goToLogin();
    };
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (AuthService.instance.isAuthenticated) {
        await PushNotificationService.instance.registerAfterLogin();
        await NotificationPreferencesService.instance.syncAll();
        unawaited(UserPresenceService.instance.setOnline(true));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      VpnDetectorService.instance.start();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      VpnDetectorService.instance.stop();
    }
    if (!AuthService.instance.isAuthenticated) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(UserPresenceService.instance.setOnline(true));
      // Accept с lock screen / cold start мог произойти до готовности Dart.
      unawaited(IncomingCallService.instance.recoverPendingAcceptedCalls());
      unawaited(
        IncomingCallService.instance.refreshVoipRegistration(force: false),
      );
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(UserPresenceService.instance.setOnline(false));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemUiOverlay,
      child: MaterialApp(
        navigatorKey: AppNavigationService.navigatorKey,
        navigatorObservers: [
          AppNavigationService.routeObserver,
          RootStackObserver.instance,
        ],
        title: 'Connect — Корпоративный сервис',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        builder: (context, child) {
          // MaterialApp подставляет для текста без Material-предка красно-жёлтый
          // debug-стиль (см. flutter/material/app.dart, _errorTextStyle). Экраны
          // и диалоги приложения построены на Cupertino-виджетах без Material,
          // поэтому здесь задаётся собственный DefaultTextStyle на уровне всего
          // Navigator — это покрывает и showDialog/showCupertinoDialog/шторки.
          final textStyle = TextStyle(
            fontFamily: '.SF Pro Text',
            decoration: TextDecoration.none,
            color: CupertinoColors.label.resolveFrom(context),
            fontSize: 16,
          );
          return DefaultTextStyle(
            style: textStyle,
            // Тап в любом месте вне текстового поля (в т.ч. в открытых поверх
            // экранов шторках вроде выбора сотрудника на «Диске») должен
            // закрывать клавиатуру — иначе после ввода текста её нечем убрать.
            // GestureDetector — обёртка над Navigator/Overlay, поэтому не
            // мешает обычным тапам по кнопкам и не перехватывает скролл.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: Stack(
                children: [
                  // Корневой Scaffold над Navigator: ScaffoldMessenger
                  // показывает SnackBar только в самом верхнем Scaffold, и
                  // без этой обёртки им был Scaffold главного экрана —
                  // на экранах, открытых поверх него, SnackBar рисовался
                  // под ними и был не виден.
                  // Material внутри Scaffold сбрасывает DefaultTextStyle на
                  // тему — возвращаем стиль приложения.
                  Scaffold(
                    backgroundColor: Colors.transparent,
                    resizeToAvoidBottomInset: false,
                    body: DefaultTextStyle(style: textStyle, child: child!),
                  ),
                  const HomeShortcutButton(),
                  const VpnBanner(),
                ],
              ),
            ),
          );
        },
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
      ),
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

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late int _currentIndex;
  bool _isDrawerOpen = false;
  bool _isProfileOpen = false;
  Map<String, dynamic>? _profile;
  Timer? _mailRefreshTimer;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 4);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppNavigationService.processPendingNavigation();
    });
    WidgetsBinding.instance.addObserver(this);
    _loadDrawerProfile();
    ChatService.instance.addListener(_onChatsChanged);
    ChatService.instance.init();
    unawaited(ChatRealtimeService.instance.start());
    MailUnreadService.instance.addListener(_onMailUnreadChanged);
    MailUnreadService.instance.refresh();
    _mailRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        MailUnreadService.instance.refresh();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ChatService.instance.removeListener(_onChatsChanged);
    MailUnreadService.instance.removeListener(_onMailUnreadChanged);
    _mailRefreshTimer?.cancel();
    MailUnreadService.instance.reset();
    DocumentPendingService.instance.reset();
    unawaited(ChatRealtimeService.instance.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      MailUnreadService.instance.refresh();
      unawaited(ChatService.instance.refreshChats(showLoading: false));
      unawaited(ChatService.instance.reloadCachedMessages());
      unawaited(ChatRealtimeService.instance.start());
    }
  }

  void _onChatsChanged() {
    if (mounted) setState(() {});
  }

  void _onMailUnreadChanged() {
    if (mounted) setState(() {});
  }

  int get _unreadChatsCount =>
      ChatService.instance.chats.fold<int>(0, (sum, c) => sum + c.unreadCount);

  String get _unreadChatsBadge => Chat.unreadBadgeLabel(_unreadChatsCount);

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

  String get _drawerDisplayName =>
      userDisplayNameFromJson(_profile ?? const {});

  String? get _drawerAvatarUrl =>
      MediaUrlUtils.normalizeFirstUrl(_profile?['media']);

  void _openProfile() {
    setState(() => _isProfileOpen = true);
    Navigator.of(
      context,
    ).push(CupertinoPageRoute(builder: (_) => const ProfileScreen())).then((_) {
      if (mounted) setState(() => _isProfileOpen = false);
    });
  }

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
      3 => const FavoritesScreen(showAppBar: false),
      _ => const ConnectorScreen(showAppBar: false),
    };

    return Scaffold(
      key: _scaffoldKey,
      // Тот же серый, что у вкладок: плавающее меню лежит на нём.
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      drawerScrimColor: Colors.black.withValues(alpha: 0.05),
      // При открытом меню тело тянется под (спрятанный) таббар: размытие
      // ложится на весь экран одним слоем, без шва над зоной таббара.
      // Под размытием перекладка контента не видна.
      extendBody: _isDrawerOpen,
      onDrawerChanged: (isOpened) => setState(() => _isDrawerOpen = isOpened),
      drawer: Drawer(
        backgroundColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
            child: AppGlass(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _DrawerHeaderCard(
                    displayName: _drawerDisplayName,
                    position: _drawerPosition,
                    avatarUrl: _drawerAvatarUrl,
                    onProfileTap: () {
                      Navigator.pop(context);
                      _openProfile();
                    },
                  ),
                  const _DrawerDivider(),
                  _DrawerMenuCard(
                    children: [
                      _DrawerItem(
                        icon: CupertinoIcons.search,
                        label: 'Поиск',
                        selected: false,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(
                            CupertinoPageRoute(
                              builder: (_) => const GlobalSearchScreen(),
                            ),
                          );
                        },
                      ),
                      _DrawerItem(
                        icon: CupertinoIcons.news,
                        label: 'Лента',
                        selected: !_isProfileOpen && _currentIndex == 0,
                        onTap: () {
                          Navigator.pop(context);
                          setState(() => _currentIndex = 0);
                        },
                      ),
                      _DrawerItem(
                        icon: CupertinoIcons.calendar,
                        label: 'Календарь',
                        selected: !_isProfileOpen && _currentIndex == 1,
                        onTap: () {
                          Navigator.pop(context);
                          setState(() => _currentIndex = 1);
                        },
                      ),
                      _DrawerItem(
                        icon: CupertinoIcons.chat_bubble_2,
                        label: 'Чаты',
                        selected: !_isProfileOpen && _currentIndex == 2,
                        badgeLabel: _unreadChatsBadge,
                        onTap: () {
                          Navigator.pop(context);
                          setState(() => _currentIndex = 2);
                        },
                      ),
                      _DrawerItem(
                        icon: CupertinoIcons.star,
                        label: 'Избранное',
                        selected: !_isProfileOpen && _currentIndex == 3,
                        onTap: () {
                          Navigator.pop(context);
                          setState(() => _currentIndex = 3);
                        },
                      ),
                      _DrawerItem(
                        icon: CupertinoIcons.videocam,
                        label: 'Коннектор',
                        selected: !_isProfileOpen && _currentIndex == 4,
                        onTap: () {
                          Navigator.pop(context);
                          setState(() => _currentIndex = 4);
                        },
                      ),
                    ],
                  ),
                  const _DrawerDivider(),
                  _DrawerMenuCard(
                    children: [
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
                        icon: CupertinoIcons.envelope,
                        label: 'Почта',
                        selected: false,
                        badgeCount: MailUnreadService.instance.unreadCount,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.of(context)
                              .push(
                                CupertinoPageRoute(
                                  builder: (_) => const MailScreen(),
                                ),
                              )
                              .then(
                                (_) => MailUnreadService.instance.refresh(),
                              );
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
                      _DrawerItem(
                        icon: CupertinoIcons.folder,
                        label: 'Диск',
                        selected: false,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(
                            CupertinoPageRoute(
                              builder: (_) => const DiskScreen(),
                            ),
                          );
                        },
                      ),
                      _DrawerItem(
                        icon: CupertinoIcons.gift,
                        label: 'Бонусная программа',
                        selected: false,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(
                            CupertinoPageRoute(
                              builder: (_) => const BonusProgramScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const _DrawerDivider(),
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
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            top: false,
            bottom: false,
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
          if (_isDrawerOpen) const _DrawerBackdrop(),
        ],
      ),
      // При открытом меню таббар прячем: иначе он выглядит активным,
      // хотя тап по нему только закрывает меню.
      bottomNavigationBar: IgnorePointer(
        ignoring: _isDrawerOpen,
        child: AnimatedOpacity(
          opacity: _isDrawerOpen ? 0 : 1,
          duration: const Duration(milliseconds: 200),
          child: _FloatingTabBar(
            currentIndex: _currentIndex,
            onSelect: (index) {
              HapticFeedback.selectionClick();
              setState(() => _currentIndex = index);
            },
            items: [
              const _TabItem(
                icon: CupertinoIcons.news,
                activeIcon: CupertinoIcons.news_solid,
                label: 'Лента',
              ),
              const _TabItem(
                icon: CupertinoIcons.calendar,
                activeIcon: CupertinoIcons.calendar,
                label: 'Календарь',
              ),
              _TabItem(
                icon: CupertinoIcons.chat_bubble_2,
                activeIcon: CupertinoIcons.chat_bubble_2_fill,
                label: 'Чаты',
                badge: _unreadChatsCount > 0 ? _unreadChatsBadge : null,
              ),
              const _TabItem(
                icon: CupertinoIcons.star,
                activeIcon: CupertinoIcons.star_fill,
                label: 'Избранное',
              ),
              const _TabItem(
                icon: CupertinoIcons.videocam,
                activeIcon: CupertinoIcons.videocam_fill,
                label: 'Коннектор',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Размытие под открытым боковым меню.
class _DrawerBackdrop extends StatelessWidget {
  const _DrawerBackdrop();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _TabItem {
  const _TabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Подпись красного бейджа (`3`, `99+`); `null` — без бейджа.
  final String? badge;
}

/// Нижнее меню — плавающая белая капсула над серым фоном вкладок,
/// активный пункт подсвечен мягкой подложкой цвета бренда.
class _FloatingTabBar extends StatelessWidget {
  const _FloatingTabBar({
    required this.currentIndex,
    required this.onSelect,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final List<_TabItem> items;

  @override
  Widget build(BuildContext context) {
    // Капсула частично заходит в зону home indicator, как системный
    // таб-бар iOS, но не ближе 12pt к краю на устройствах без неё.
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final bottom = safeBottom > 0 ? (safeBottom - 10).clamp(12.0, 40.0) : 12.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 6, 16, bottom),
      child: Container(
        height: 62,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          borderRadius: BorderRadius.circular(31),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _TabButton(
                  item: items[i],
                  selected: i == currentIndex,
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _TabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AppColors.primary
        : CupertinoColors.secondaryLabel.resolveFrom(context);
    final badge = item.badge;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.1)
                : const Color(0x00000000),
            borderRadius: BorderRadius.circular(27),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    selected ? item.activeIcon : item.icon,
                    size: 23,
                    color: color,
                  ),
                  if (badge != null)
                    Positioned(
                      top: -5,
                      left: 15,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemRed,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: CupertinoColors
                                .secondarySystemGroupedBackground
                                .resolveFrom(context),
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          badge,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                            color: CupertinoColors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  fontFamily: '.SF Pro Text',
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Шапка меню: лого приложения + профиль текущего пользователя.
/// Лежит прямо на стеклянной панели, без своей карточки.
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
      margin: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: BrandingLoginLogo(height: 26),
          ),
          Container(
            height: 0.5,
            margin: const EdgeInsets.only(left: 16),
            color: CupertinoColors.separator.resolveFrom(context),
          ),
          CupertinoListTile(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leadingSize: 40,
            leading: MemberAvatar(
              displayName: displayName,
              avatarUrl: avatarUrl,
              radius: 20,
            ),
            title: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            subtitle: (position ?? '').isNotEmpty
                ? Text(
                    position!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  )
                : null,
            backgroundColor: const Color(0x00000000),
            trailing: const CupertinoListTileChevron(),
            onTap: onProfileTap,
          ),
        ],
      ),
    );
  }
}

/// Тонкий разделитель между группами пунктов меню.
class _DrawerDivider extends StatelessWidget {
  const _DrawerDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      color: CupertinoColors.separator.resolveFrom(context),
    );
  }
}

/// Группа пунктов меню.
class _DrawerMenuCard extends StatelessWidget {
  const _DrawerMenuCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(children: children);
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.isExternal = false,
    this.badgeCount = 0,
    this.badgeLabel,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// `true` — пункт открывает внешнюю ссылку, а не раздел приложения:
  /// справа показывается иконка внешней ссылки.
  final bool isExternal;

  /// Число непрочитанного для этого раздела — 0 скрывает бейдж.
  final int badgeCount;

  /// Готовая подпись бейджа (`10+`). Если не задана — из [badgeCount].
  final String? badgeLabel;

  @override
  Widget build(BuildContext context) {
    final text = badgeLabel ?? (badgeCount > 99 ? '99+' : '$badgeCount');
    final showBadge =
        (badgeLabel != null && badgeLabel!.isNotEmpty) || badgeCount > 0;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final labelColor = CupertinoColors.label.resolveFrom(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        pressedOpacity: 0.55,
        onPressed: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          // Выбранный пункт — светлая «стеклянная» капсула, без цвета.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected
                ? (isDark ? const Color(0x24FFFFFF) : const Color(0xE6FFFFFF))
                : const Color(0x00FFFFFF),
            border: Border.all(
              color: selected
                  ? (isDark ? const Color(0x1FFFFFFF) : const Color(0x14000000))
                  : const Color(0x00FFFFFF),
              width: 0.5,
            ),
            boxShadow: selected && !isDark
                ? const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Icon(icon, size: 19, color: labelColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    letterSpacing: -0.2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: labelColor,
                  ),
                ),
              ),
              if (showBadge)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemRed,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.white,
                    ),
                  ),
                ),
              if (isExternal)
                Icon(
                  CupertinoIcons.arrow_up_right,
                  size: 15,
                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
