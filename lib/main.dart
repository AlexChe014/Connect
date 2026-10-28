import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:intl/date_symbol_data_local.dart';

import 'screens/chats_list_screen.dart';
import 'screens/connector_screen.dart';
import 'screens/today_screen.dart';
import 'screens/login_screen.dart';
import 'screens/mail_screen.dart';
import 'screens/more_screen.dart';
import 'config/api_config.dart';
import 'config/app_theme.dart';
import 'config/home_tabs.dart';
import 'models/chat.dart';
import 'repositories/documents_repository.dart';
import 'services/api_response_cache.dart';
import 'services/app_lock_service.dart';
import 'services/app_navigation_service.dart';
import 'services/auth_service.dart';
import 'services/branding_service.dart';
import 'services/haptics_service.dart';
import 'services/home_widget_service.dart';
import 'services/live_activity_service.dart';
import 'services/chat_service.dart';
import 'services/chat_realtime_service.dart';
import 'services/crash_reporting_service.dart';
import 'services/incoming_call_service.dart';
import 'services/mail_unread_service.dart';
import 'services/document_pending_service.dart';
import 'services/notification_preferences_service.dart';
import 'services/notification_unread_service.dart';
import 'services/push_notification_service.dart';
import 'services/root_stack_observer.dart';
import 'services/survey_pending_service.dart';
import 'services/theme_mode_service.dart';
import 'services/user_presence_service.dart';
import 'services/vpn_detector_service.dart';
import 'widgets/app_lock_overlay.dart';
import 'widgets/call_overlay.dart';
import 'widgets/vpn_banner.dart';

Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    MediaKit.ensureInitialized();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(AppTheme.systemUiOverlay);
    await initializeDateFormatting('ru_RU', null);
    await ApiConfig.init();
    await ThemeModeService.instance.init();
    await AppHaptics.init();
    await AuthService.instance.init();
    await AppLockService.instance.init();
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
    LiveActivityService.instance.init();
    HomeWidgetService.instance.init();
    AuthService.instance.onSessionExpired = () {
      UserPresenceService.instance.reset();
      unawaited(ChatRealtimeService.instance.stop());
      ChatService.instance.reset();
      unawaited(ApiResponseCache.clearAll());
      unawaited(PushNotificationService.instance.disableLocally());
      AppLockService.instance.dismiss();
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
      unawaited(HomeWidgetService.instance.refresh());
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
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeModeService.instance.mode,
      builder: (context, themeMode, _) => MaterialApp(
        navigatorKey: AppNavigationService.navigatorKey,
        navigatorObservers: [
          AppNavigationService.routeObserver,
          RootStackObserver.instance,
        ],
        title: 'Connect — Корпоративный сервис',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
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
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: AppTheme.systemUiOverlayFor(Theme.of(context).brightness),
            child: DefaultTextStyle(
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
                    const VpnBanner(),
                    const AppLockOverlay(),
                    // Экран звонка — над всем, в т.ч. над Navigator: при
                    // сворачивании в окошко звонок продолжается, пока
                    // пользователь ходит по приложению.
                    const CallOverlayHost(),
                  ],
                ),
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
              initialIndex: initialIndex ?? HomeTabs.today,
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
    this.initialIndex = HomeTabs.today,
    this.openNewsId,
  });

  final int initialIndex;
  final String? openNewsId;

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  late int _currentIndex;

  /// Вкладки, которые уже открывали. Создаём их лениво, а потом держим
  /// смонтированными: при переключении сохраняются прокрутка и данные.
  final Set<int> _loadedTabs = {};
  Timer? _mailRefreshTimer;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, HomeTabs.more);
    _loadedTabs.add(_currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppNavigationService.processPendingNavigation();
    });
    WidgetsBinding.instance.addObserver(this);
    ChatService.instance.addListener(_onBadgesChanged);
    ChatService.instance.init();
    unawaited(ChatRealtimeService.instance.start());
    MailUnreadService.instance.addListener(_onBadgesChanged);
    MailUnreadService.instance.refresh();
    DocumentPendingService.instance.addListener(_onBadgesChanged);
    unawaited(_refreshPendingDocuments());
    SurveyPendingService.instance.addListener(_onBadgesChanged);
    unawaited(SurveyPendingService.instance.refreshQuietly());
    NotificationUnreadService.instance.addListener(_onBadgesChanged);
    unawaited(NotificationUnreadService.instance.refresh());
    _mailRefreshTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        MailUnreadService.instance.refresh();
        // Подстраховка к пушам: они могут быть выключены на устройстве.
        unawaited(NotificationUnreadService.instance.refresh());
        // Новые опросы приходят редко — хватает раза в 5 минут.
        if (timer.tick % 5 == 0) {
          unawaited(SurveyPendingService.instance.refreshQuietly());
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ChatService.instance.removeListener(_onBadgesChanged);
    MailUnreadService.instance.removeListener(_onBadgesChanged);
    DocumentPendingService.instance.removeListener(_onBadgesChanged);
    _mailRefreshTimer?.cancel();
    MailUnreadService.instance.reset();
    SurveyPendingService.instance.removeListener(_onBadgesChanged);
    SurveyPendingService.instance.reset();
    NotificationUnreadService.instance.removeListener(_onBadgesChanged);
    NotificationUnreadService.instance.reset();
    DocumentPendingService.instance.reset();
    unawaited(ChatRealtimeService.instance.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      MailUnreadService.instance.refresh();
      unawaited(DocumentPendingService.instance.refreshKnownServices());
      unawaited(SurveyPendingService.instance.refreshQuietly());
      unawaited(NotificationUnreadService.instance.refresh());
      unawaited(ChatService.instance.refreshChats(showLoading: false));
      unawaited(ChatService.instance.reloadCachedMessages());
      unawaited(ChatRealtimeService.instance.start());
    }
  }

  void _onBadgesChanged() {
    if (mounted) setState(() {});
  }

  /// Бейдж «Чаты» и строка «Согласование» в них. Сервисы с подписью
  /// [DocumentPendingService] сам пропускает без свежего кода доступа.
  Future<void> _refreshPendingDocuments() async {
    try {
      final services = await DocumentsRepository.instance.getActiveServices();
      await DocumentPendingService.instance.refresh(services);
    } catch (_) {
      // Нет доступа к 1С — просто без бейджа.
    }
  }

  void _selectTab(int index) {
    AppHaptics.selection();
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      _loadedTabs.add(index);
    });
    if (index == HomeTabs.mail) {
      MailUnreadService.instance.refresh();
    }
  }

  static String? _countBadge(int count) =>
      count <= 0 ? null : (count > 99 ? '99+' : '$count');

  /// Сколько строк в списке чатов ждут внимания. Строка «Согласование» —
  /// одна, сколько бы документов в ней ни было.
  int get _chatsTabCount =>
      ChatService.instance.unreadChatsCount +
      (DocumentPendingService.instance.totalCount > 0 ? 1 : 0);

  Widget _buildTab(int index) {
    return switch (index) {
      HomeTabs.today => TodayScreen(openNewsId: widget.openNewsId),
      HomeTabs.chats => const ChatsListScreen(),
      HomeTabs.calls => const ConnectorScreen(),
      HomeTabs.mail => const MailScreen(isTab: true),
      _ => const MoreScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(
      index: _currentIndex,
      children: [
        for (var i = 0; i <= HomeTabs.more; i++)
          _loadedTabs.contains(i)
              // Скрытые вкладки не крутят анимации впустую.
              ? TickerMode(enabled: i == _currentIndex, child: _buildTab(i))
              : const SizedBox.shrink(),
      ],
    );

    return Scaffold(
      // Тот же серый, что у вкладок: плавающее меню лежит на нём.
      backgroundColor: AppColors.groupedBackground.resolveFrom(context),
      // Списки уходят под плавающую капсулу, а не обрываются над ней серой
      // полосой; высоту меню вкладки получают в MediaQuery.padding.bottom.
      extendBody: true,
      body: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 900) return body;
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: body,
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: _FloatingTabBar(
        currentIndex: _currentIndex,
        onSelect: _selectTab,
        items: [
          const _TabItem(
            icon: CupertinoIcons.house,
            activeIcon: CupertinoIcons.house_fill,
            label: 'Главная',
          ),
          _TabItem(
            icon: CupertinoIcons.chat_bubble_2,
            activeIcon: CupertinoIcons.chat_bubble_2_fill,
            label: 'Чаты',
            // Документы на согласование считаем здесь, а не в «Ещё»:
            // строка «Согласование» закреплена в чатах, и один и тот же
            // документ не должен подсвечивать две вкладки сразу.
            badge: _chatsTabCount > 0
                ? Chat.unreadBadgeLabel(_chatsTabCount)
                : null,
          ),
          const _TabItem(
            icon: CupertinoIcons.phone,
            activeIcon: CupertinoIcons.phone_fill,
            label: 'Звонки',
          ),
          _TabItem(
            icon: CupertinoIcons.envelope,
            activeIcon: CupertinoIcons.envelope_fill,
            label: 'Почта',
            badge: _countBadge(MailUnreadService.instance.unreadCount),
          ),
          _TabItem(
            icon: CupertinoIcons.ellipsis_circle,
            activeIcon: CupertinoIcons.ellipsis_circle_fill,
            label: 'Ещё',
            badge: _countBadge(SurveyPendingService.instance.pendingCount),
          ),
        ],
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
          color: AppColors.groupedSurface.resolveFrom(context),
          borderRadius: BorderRadius.circular(31),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowControl,
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
            BoxShadow(
              color: AppColors.shadowHairline,
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
                : Colors.transparent,
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
                          color: CupertinoColors.systemRed.resolveFrom(context),
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
