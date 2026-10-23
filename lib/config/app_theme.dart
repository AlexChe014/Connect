import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Общая цветовая палитра и тема приложения.
abstract final class AppColors {
  AppColors._();

  static const primary = Color(0xFF1677FF);
  static const onPrimary = Colors.white;

  /// Второстепенный текст на фирменной заливке и градиентах.
  static const onPrimaryMuted = Color(0xD9FFFFFF);
  static const surface = Colors.white;
  static const background = Colors.white;
  static const onSurface = Color(0xFF111827);
  static const onSurfaceVariant = Color(0xFF52525B);
  static const surfaceElevated = Color(0xFFF7F8FA);
  static const outline = Color(0xFFE5E7EB);
  static const outlineStrong = Color(0xFFD1D5DB);
  static const error = Color(0xFFDC2626);

  /// Свои сообщения в чате и кнопка отправки — единственный цветной
  /// акцент в переписке: сразу видно, где ваши сообщения.
  static const outgoingBubble = primary;

  // Фоны экранов и карточек. В тёмной теме не чистый чёрный, а графит
  // с холодным оттенком: на #000 стеклу нечего размывать, карточки
  // держатся только на кромке, а свечение под шапкой обрывается пятном.
  static const screenBackground = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF0F1115),
  );
  static const groupedBackground = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF2F2F7),
    darkColor: Color(0xFF0F1115),
  );
  static const groupedSurface = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF1C1E22),
  );

  /// Бегунок сегментного переключателя.
  static const segmentThumb = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF3A3D43),
  );

  // Liquid Glass: заливка и кромка плавающих панелей и карточек.
  // Динамические — читать через `.resolveFrom(context)`.
  static const glassFill = CupertinoDynamicColor.withBrightness(
    color: Color(0xCCFFFFFF),
    darkColor: Color(0x80303032),
  );
  static const glassGradientTop = CupertinoDynamicColor.withBrightness(
    color: Color(0xCCFFFFFF),
    darkColor: Color(0x803A3A3C),
  );
  static const glassGradientBottom = CupertinoDynamicColor.withBrightness(
    color: Color(0x99FFFFFF),
    darkColor: Color(0x661C1C1E),
  );

  /// Заливка плавающей панели там, где размытие выключено
  /// ([AppGlass.blurSupported]): без него контент под панелью не должен
  /// читаться сквозь неё.
  static const glassSolidFill = CupertinoDynamicColor.withBrightness(
    color: Color(0xF5FFFFFF),
    darkColor: Color(0xF22C2C2E),
  );
  static const glassBorder = CupertinoDynamicColor.withBrightness(
    color: Color(0xB3FFFFFF),
    darkColor: Color(0x26FFFFFF),
  );

  /// Поле ввода внутри стеклянной панели.
  static const glassInputFill = CupertinoDynamicColor.withBrightness(
    color: Color(0x0F000000),
    darkColor: Color(0x1FFFFFFF),
  );

  // Скелетон загрузки и заглушка картинки, которая не загрузилась.
  static const skeletonBase = CupertinoDynamicColor.withBrightness(
    color: outline,
    darkColor: Color(0xFF2C2C2E),
  );
  static const skeletonHighlight = CupertinoDynamicColor.withBrightness(
    color: surfaceElevated,
    darkColor: Color(0xFF3A3A3C),
  );
  static const placeholderFill = CupertinoDynamicColor.withBrightness(
    color: surfaceElevated,
    darkColor: Color(0xFF1C1C1E),
  );
  static const placeholderIcon = CupertinoDynamicColor.withBrightness(
    color: Color(0x8052525B),
    darkColor: Color(0x80AEAEB2),
  );

  // Тени: крупная плавающая панель, мелкий элемент, тонкий контур.
  static const shadowPanel = Color(0x1F000000);
  static const shadowControl = Color(0x14000000);
  static const shadowHairline = Color(0x0A000000);

  // Затемнение поверх фото и модальных подложек — от темы не зависит.
  static const scrimFaint = Color(0x2E000000);
  static const scrim = Color(0x66000000);
  static const scrimStrong = Color(0x8C000000);
  static const scrimButton = Color(0x99000000);

  /// Аватар без фото — нейтральный серый градиент.
  static const avatarPlaceholderGradient = [
    Color(0xFFA5ABB8),
    Color(0xFF858994),
  ];

  /// Подложка HTML-письма. Письма свёрстаны под белый фон: в тёмной теме
  /// их цвета инвертируются, и белый становится этим графитом. Если
  /// пользователь вернул письму исходные цвета — подложка снова белая.
  static const mailBodyBackground = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF1C1E22),
  );

  static const double radius = 12;
  static const double buttonRadius = 12;

  /// Мягкая тень для карточек с фото (комнаты, новости) — там плоский
  /// стиль (elevation 0 + outline-бордер) выглядит невыразительно.
  static List<BoxShadow> get cardPhotoShadow => [
    BoxShadow(
      color: onSurface.withValues(alpha: 0.08),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];
}

/// Праздничная палитра бонусной программы: колесо, карточки, медали,
/// конфетти. Декоративная, одинаковая в светлой и тёмной теме.
abstract final class AppFestiveColors {
  AppFestiveColors._();

  /// Рамка текущего приза и стрелка колеса.
  static const warmAccent = Color(0xFFFF7A45);
  static const orange = Color(0xFFFF9F43);
  static const pink = Color(0xFFFF5E8A);
  static const violet = Color(0xFF7B5CFF);

  /// Кнопка «Крутить», карточка рулетки.
  static const buttonGradient = [orange, pink];

  /// Карточка баланса.
  static const balanceGradient = [AppColors.primary, violet];

  // Пятно за шапкой рулетки: оранжевый → розовый → сиреневый.
  static const glowOrange = Color(0xFFFFB547);
  static const glowPink = Color(0xFFFF6FA3);
  static const glowViolet = Color(0xFFB57CFF);

  // Лучи «солнышка» за колесом.
  static const sunburstCore = Color(0xFFFFC94D);
  static const sunburstEdge = Color(0xFFFF8A65);

  /// Тень под колесом.
  static const wheelShadow = Color(0xFF141C22);

  /// Медаль полученного достижения.
  static const medalGradient = [Color(0xFFFFD966), Color(0xFFE0A200)];

  static const confettiGold = Color(0xFFFFC542);
  static const confettiNavy = Color(0xFF0B2545);
}

/// Единая шкала отступов, чтобы padding/gap не подбирались на глаз по экрану.
/// Экран звонка. Тёмный в обеих темах, как звонок в iOS: видео и аватар
/// читаются лучше на тёмном, а светлый экран слепит в темноте у уха.
abstract final class AppCallColors {
  AppCallColors._();

  // Фон: глубокий синий сверху в графит снизу.
  static const backgroundTop = Color(0xFF14213D);
  static const backgroundBottom = Color(0xFF0B0E14);

  // Мягкие пятна света за аватаром — стеклу кнопок есть что размывать.
  static const glowBlue = Color(0xFF1677FF);
  static const glowViolet = Color(0xFF6E5BFF);
  static const glowCyan = Color(0xFF22B8CF);

  /// Подложка карточки с видео, пока Jitsi не отрисовал первый кадр.
  static const stage = Color(0xFF040404);

  // Круглые стеклянные кнопки.
  static const buttonFill = Color(0x2EFFFFFF);
  static const buttonBorder = Color(0x33FFFFFF);

  /// Включённое состояние («микрофон выключен», «динамик») — светлая
  /// кнопка с тёмной иконкой, как в Телефоне iOS.
  static const buttonActiveFill = Color(0xF2FFFFFF);
  static const buttonActiveIcon = Color(0xFF111827);
  static const hangUp = Color(0xFFFF3B30);
  static const accept = Color(0xFF34C759);

  static const textPrimary = Colors.white;
  static const textSecondary = Color(0xB3FFFFFF);
  static const textTertiary = Color(0x80FFFFFF);

  /// Значок «микрофон выключен» у собеседника.
  static const mutedBadge = Color(0xFFFF453A);

  /// Тень свёрнутого окошка звонка над приложением.
  static const miniShadow = Color(0x66000000);
}

abstract final class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Цвета, которые различаются в светлой и тёмной теме Material-части
/// (диалоги, пикеры, поля ввода). Cupertino-экраны берут цвета из
/// динамических `CupertinoColors` и [AppColors.glassFill] и т.п.
class _Palette {
  const _Palette({
    required this.brightness,
    required this.surface,
    required this.background,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.surfaceElevated,
    required this.surfaceContainerHighest,
    required this.secondaryContainer,
    required this.outline,
    required this.outlineStrong,
    required this.error,
  });

  final Brightness brightness;
  final Color surface;
  final Color background;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color surfaceElevated;
  final Color surfaceContainerHighest;
  final Color secondaryContainer;
  final Color outline;
  final Color outlineStrong;
  final Color error;

  static const light = _Palette(
    brightness: Brightness.light,
    surface: AppColors.surface,
    background: AppColors.background,
    onSurface: AppColors.onSurface,
    onSurfaceVariant: AppColors.onSurfaceVariant,
    surfaceElevated: AppColors.surfaceElevated,
    surfaceContainerHighest: Color(0xFFF9FAFB),
    secondaryContainer: Color(0xFFE8F1FF),
    outline: AppColors.outline,
    outlineStrong: AppColors.outlineStrong,
    error: AppColors.error,
  );

  /// Графитовая тёмная палитра — те же фоны, что у
  /// [AppColors.groupedBackground] и [AppColors.groupedSurface].
  static const dark = _Palette(
    brightness: Brightness.dark,
    surface: Color(0xFF1C1E22),
    background: Color(0xFF0F1115),
    onSurface: Color(0xFFF2F2F7),
    onSurfaceVariant: Color(0xFFAEAEB2),
    surfaceElevated: Color(0xFF26292E),
    surfaceContainerHighest: Color(0xFF26292E),
    secondaryContainer: Color(0xFF0E2A4D),
    outline: Color(0xFF2E3138),
    outlineStrong: Color(0xFF3E424A),
    error: Color(0xFFFF453A),
  );
}

abstract final class AppTheme {
  AppTheme._();

  /// Светлый фон → тёмные системные иконки (назад / домой / недавние).
  /// Иначе на Android без жестов кнопки навигации сливаются с таббаром.
  static const SystemUiOverlayStyle systemUiOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: true,
  );

  /// Тёмный фон → светлые системные иконки.
  static const SystemUiOverlayStyle systemUiOverlayDark = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: true,
  );

  static SystemUiOverlayStyle systemUiOverlayFor(Brightness brightness) =>
      brightness == Brightness.dark ? systemUiOverlayDark : systemUiOverlay;

  static ThemeData get light => _build(_Palette.light);

  static ThemeData get dark => _build(_Palette.dark);

  static ThemeData _build(_Palette p) {
    const radius = AppColors.radius;
    final borderRadius = BorderRadius.circular(radius);

    OutlineInputBorder inputBorder({Color? color, double width = 1}) {
      return OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: color ?? p.outlineStrong, width: width),
      );
    }

    // Через copyWith от базовой схемы: незаданные surfaceContainer* и т.п.
    // наследуют surface, как раньше у ColorScheme.light.
    final base = p.brightness == Brightness.dark
        ? const ColorScheme.dark()
        : const ColorScheme.light();
    final colorScheme = base.copyWith(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.primary,
      onSecondary: AppColors.onPrimary,
      secondaryContainer: p.secondaryContainer,
      onSecondaryContainer: AppColors.primary,
      surface: p.surface,
      onSurface: p.onSurface,
      onSurfaceVariant: p.onSurfaceVariant,
      surfaceContainerHighest: p.surfaceContainerHighest,
      outline: p.outline,
      outlineVariant: p.outlineStrong,
      error: p.error,
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppColors.buttonRadius),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      // Крупные заголовки экранов (CupertinoSliverNavigationBar): системные
      // 34 pt выглядели слишком громоздко рядом с карточками — чуть меньше.
      cupertinoOverrideTheme: const CupertinoThemeData(
        textTheme: CupertinoTextThemeData(
          primaryColor: AppColors.primary,
          navLargeTitleTextStyle: TextStyle(
            inherit: false,
            fontFamily: 'CupertinoSystemDisplay',
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.36,
            color: CupertinoColors.label,
          ),
        ),
      ),
      textTheme: TextTheme(
        headlineSmall: TextStyle(
          color: p.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
        titleLarge: TextStyle(
          color: p.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        titleMedium: TextStyle(
          color: p.onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        titleSmall: TextStyle(
          color: p.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        bodyLarge: TextStyle(color: p.onSurface, fontSize: 16, height: 1.4),
        bodyMedium: TextStyle(color: p.onSurface, height: 1.4),
        bodySmall: TextStyle(color: p.onSurfaceVariant, height: 1.4),
        labelMedium: TextStyle(color: p.onSurfaceVariant),
        labelSmall: TextStyle(color: p.onSurfaceVariant),
      ),
      splashColor: AppColors.primary.withValues(alpha: 0.08),
      highlightColor: AppColors.primary.withValues(alpha: 0.05),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: p.surfaceElevated,
        foregroundColor: p.onSurface,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: systemUiOverlayFor(p.brightness),
        shape: Border(bottom: BorderSide(color: p.outline, width: 1)),
        titleTextStyle: TextStyle(
          color: p.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(thickness: 1, space: 1, color: p.outline),
      listTileTheme: ListTileThemeData(
        iconColor: p.onSurface,
        textColor: p.onSurface,
        selectedColor: AppColors.primary,
        horizontalTitleGap: 12,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: p.surface,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(color: p.outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        labelStyle: TextStyle(color: p.onSurfaceVariant),
        hintStyle: TextStyle(color: p.onSurfaceVariant),
        border: inputBorder(),
        enabledBorder: inputBorder(),
        focusedBorder: inputBorder(color: AppColors.primary, width: 1.5),
        errorBorder: inputBorder(color: p.error),
        focusedErrorBorder: inputBorder(color: p.error, width: 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: p.outline,
          disabledForegroundColor: p.onSurfaceVariant,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          minimumSize: const Size(64, 48),
          shape: buttonShape,
          textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          disabledForegroundColor: p.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          minimumSize: const Size(64, 48),
          side: BorderSide(color: p.outlineStrong),
          shape: buttonShape,
          textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: buttonShape,
          textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          minimumSize: const Size(64, 48),
          shape: buttonShape,
          textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        // Ненулевая тень нужна, чтобы FAB читался как элемент "над" списком,
        // а не сливался с карточкой контента под ним при скролле.
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: AppColors.primary.withValues(alpha: 0.12),
        disabledColor: p.outline,
        labelStyle: TextStyle(color: p.onSurface),
        secondaryLabelStyle: TextStyle(color: p.onSurface),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        side: BorderSide(color: p.outlineStrong),
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: p.surface,
          border: inputBorder(),
          enabledBorder: inputBorder(),
          focusedBorder: inputBorder(color: AppColors.primary, width: 1.5),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(AppColors.onPrimary),
        side: BorderSide(color: p.outlineStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.onPrimary;
          return p.outlineStrong;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary.withValues(alpha: 0.55);
          }
          return p.outline;
        }),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        titleTextStyle: TextStyle(
          color: p.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(color: p.onSurface, fontSize: 14),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      // Плавающая тёмная капсула над нижним меню. Отступ снизу держит её
      // выше таб-бара, поля ввода чата и кнопок «домой»/«написать».
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xF2232326),
        contentTextStyle: TextStyle(
          fontFamily: '.SF Pro Text',
          fontSize: 15,
          height: 1.3,
          color: AppColors.onPrimary,
        ),
        actionTextColor: const Color(0xFF5AA9FF),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 84),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
    );
  }
}
