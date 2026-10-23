import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../config/app_theme.dart';
import '../models/bonus_program/roulette_config.dart';
import '../models/bonus_program/roulette_prize.dart';
import '../models/bonus_program/roulette_spin.dart';
import '../repositories/bonus_program_repository.dart';
import '../services/api_client.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/bonus_glass.dart';
import '../widgets/home_shortcut_button.dart';
import 'bonus_roulette_prizes_screen.dart';

/// Неотрицательный остаток от деления (Dart `%` уже такой для num,
/// но здесь это гарантируется явно — от него зависит позиция остановки ленты).
double _mod(double a, double b) {
  final m = a % b;
  return m < 0 ? m + b : m;
}

/// Колесо фортуны: горизонтальная лента призов — крупная карточка текущего
/// приза сверху и маленькие превью соседних призов снизу, крутится и
/// останавливается ровно на призе, который вернул сервер (`spinRoulette`).
/// Полный список призов — на отдельном экране за кнопкой «?».
class BonusRouletteScreen extends StatefulWidget {
  const BonusRouletteScreen({super.key});

  @override
  State<BonusRouletteScreen> createState() => _BonusRouletteScreenState();
}

class _BonusRouletteScreenState extends State<BonusRouletteScreen>
    with TickerProviderStateMixin {
  RouletteConfig? _config;
  List<RoulettePrize> _prizes = [];
  bool _isLoading = true;
  bool _isSpinning = false;
  String? _errorMessage;

  late final AnimationController _spinController;

  /// Фоновая «жизнь» экрана: вращение лучей, бегущие огоньки, парящий приз.
  late final AnimationController _ambient;
  Animation<double>? _reelAnimation;
  double? _restPosition;
  late final VoidCallback _releaseHomeSuppress;

  @override
  void initState() {
    super.initState();
    // «Домой» легла бы поверх кнопки «Крутить» (см. HomeShortcutButton).
    _releaseHomeSuppress = HomeShortcutButton.suppress();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _load();
  }

  @override
  void dispose() {
    _releaseHomeSuppress();
    _spinController.dispose();
    _ambient.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      // После вращения лимит обновляется тихо — без мигания загрузкой.
      _isLoading = _config == null;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        BonusProgramRepository.instance.getRouletteConfig(),
        BonusProgramRepository.instance.getRoulettePrizes(),
      ]);
      if (!mounted) return;
      setState(() {
        _config = results[0] as RouletteConfig;
        _prizes = results[1] as List<RoulettePrize>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is ApiException
            ? e.message
            : 'Не удалось получить настройки колеса фортуны';
      });
    }
  }

  Future<void> _spin() async {
    final config = _config;
    if (config == null || !config.canSpin || _isSpinning || _prizes.isEmpty) {
      return;
    }

    setState(() => _isSpinning = true);
    HapticFeedback.lightImpact();

    RouletteSpin spin;
    try {
      spin = await BonusProgramRepository.instance.spinRoulette();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSpinning = false);
      final message = e is ApiException
          ? e.message
          : 'Не удалось крутить колесо';
      _showMessageDialog(message);
      return;
    }
    if (!mounted) return;

    final n = _prizes.length;
    final won = spin.prize;
    int? targetIndex;
    if (won != null) {
      final idx = _prizes.indexWhere((p) => p.id == won.id);
      if (idx != -1) targetIndex = idx;
    }
    // Без приза лента всё равно останавливается на каком-то элементе —
    // визуально это просто ещё один прогон, а что реально произошло,
    // объясняет карточка результата.
    targetIndex ??= Random().nextInt(n);

    final startPosition = _restPosition ?? 0.0;
    const extraLoops = 4;
    final deltaToAlign = _mod(targetIndex - startPosition, n.toDouble());
    final finalPosition = startPosition + extraLoops * n + deltaToAlign;

    _reelAnimation = Tween<double>(begin: startPosition, end: finalPosition)
        .animate(
          CurvedAnimation(parent: _spinController, curve: Curves.easeOutCubic),
        );

    await _spinController.forward(from: 0);
    if (!mounted) return;
    setState(() {
      _restPosition = finalPosition;
      _isSpinning = false;
    });
    HapticFeedback.heavyImpact();

    await _showResult(spin);
    if (!mounted) return;
    await _load();
  }

  void _showMessageDialog(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        content: Text(
          message,
          style: const TextStyle(decoration: TextDecoration.none),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Ок',
              style: TextStyle(decoration: TextDecoration.none),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showResult(RouletteSpin spin) {
    final prize = spin.prize;
    final pending = spin.prizeRequest?.isPending == true;
    return showBonusCelebration(
      context,
      title: prize != null ? '🎉 Поздравляем!' : 'Почти получилось',
      message: prize != null
          ? 'Вы выиграли:\n«${prize.name}»'
          : 'В этот раз без приза — попробуйте ещё раз в следующем месяце!',
      status: prize != null && pending
          ? 'Заявка на выдачу отправлена на согласование'
          : null,
      statusColor: CupertinoColors.systemOrange,
      photoUrl: prize?.photoUrl,
      icon: prize != null ? CupertinoIcons.gift_fill : CupertinoIcons.sparkles,
      celebrate: prize != null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BonusGlassScaffold(
      title: 'Колесо фортуны',
      trailing: _isLoading
          ? null
          : CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: () => Navigator.of(context).push(
                CupertinoPageRoute(
                  builder: (_) => BonusRoulettePrizesScreen(prizes: _prizes),
                ),
              ),
              child: Icon(
                CupertinoIcons.question_circle,
                size: 24,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
      glow: const _FestiveGlow(),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }

    if (_errorMessage != null) {
      return AppEmptyState(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: _errorMessage!,
        onRetry: _load,
      );
    }

    final config = _config;
    if (config == null || !config.enabled) {
      return AppEmptyState(
        icon: CupertinoIcons.sparkles,
        message: 'Колесо фортуны сейчас недоступно',
        onRetry: _load,
      );
    }

    final remaining = config.spinsRemainingThisMonth;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Column(
      children: [
        const SizedBox(height: 4),
        const Text(
          'Испытайте удачу! 🎁',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Каждое вращение — шанс забрать приз',
          style: TextStyle(fontSize: 15, color: secondary),
        ),
        Expanded(child: Center(child: _buildReel())),
        Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.paddingOf(context).bottom + 12,
          ),
          child: Column(
            children: [
              if (remaining != null) ...[
                Text(
                  remaining > 0
                      ? '🎟 Осталось вращений в этом месяце: $remaining'
                      : 'Лимит вращений на этот месяц исчерпан',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
                const SizedBox(height: 10),
              ],
              _SpinButton(
                label: config.canSpin
                    ? 'Крутить за ${formatPoints(config.spinCost)}'
                    : 'Колесо недоступно',
                isSpinning: _isSpinning,
                pulse: _ambient,
                onPressed: config.canSpin ? _spin : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReel() {
    if (_prizes.isEmpty) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: Listenable.merge([_spinController, _ambient]),
      builder: (context, child) {
        final position = _isSpinning && _reelAnimation != null
            ? _reelAnimation!.value
            : (_restPosition ?? 0.0);
        final n = _prizes.length;
        final centerIndex = ((position.round() % n) + n) % n;
        final currentPrize = _prizes[centerIndex];
        final t = _ambient.value;
        // Приз чуть покачивается вверх-вниз, пока колесо стоит.
        final float = _isSpinning ? 0.0 : sin(t * 2 * pi * 8) * 4;
        // Сцена на стекле: крупный приз и лента превью под ним, за ней —
        // вращающиеся лучи.
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: OverflowBox(
                maxWidth: 640,
                maxHeight: 640,
                child: IgnorePointer(
                  child: Transform.rotate(
                    angle: t * 2 * pi * (_isSpinning ? 3 : 1),
                    child: const CustomPaint(
                      size: Size(640, 640),
                      painter: _SunburstPainter(),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppGlass(
                borderRadius: BorderRadius.circular(32),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.translate(
                        offset: Offset(0, float),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: _HeroPrize(
                            key: ValueKey(currentPrize.id),
                            prize: currentPrize,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: _ReelStrip(prizes: _prizes, position: position),
                      ),
                      const SizedBox(height: 4),
                      const Icon(
                        CupertinoIcons.arrowtriangle_up_fill,
                        color: _kWarmAccent,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Тёплый акцент колеса — рамка текущего приза и стрелка.
const _kWarmAccent = Color(0xFFFF7A45);

/// Тёплое праздничное пятно вместо синего [AppGlassGlow]: оранжевый
/// сверху переходит в розовый и растворяется в фоне.
class _FestiveGlow extends StatelessWidget {
  const _FestiveGlow();

  @override
  Widget build(BuildContext context) {
    final groupedBg = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFFFFB547).withValues(alpha: 0.38),
                const Color(0xFFFF6FA3).withValues(alpha: 0.22),
                const Color(0xFFB57CFF).withValues(alpha: 0.12),
                groupedBg.withValues(alpha: 0),
              ],
              stops: const [0, 0.35, 0.65, 1],
            ),
          ),
        ),
      ),
    );
  }
}

/// Лучи «солнышка» за сценой — под стеклом они размываются в мягкое
/// мерцание, а вокруг карточки видны как праздничный фон.
class _SunburstPainter extends CustomPainter {
  const _SunburstPainter();

  static const _rays = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFC94D).withValues(alpha: 0.55),
          const Color(0xFFFF8A65).withValues(alpha: 0.25),
          const Color(0x00FF8A65),
        ],
        stops: const [0.15, 0.55, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    const sweep = pi / _rays;
    for (var i = 0; i < _rays; i++) {
      final start = i * 2 * sweep;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius),
          start,
          sweep,
          false,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SunburstPainter oldDelegate) => false;
}

/// Кнопка «Крутить»: тёплый градиент и мягкая пульсация, пока колесо
/// ждёт вращения.
class _SpinButton extends StatelessWidget {
  const _SpinButton({
    required this.label,
    required this.isSpinning,
    required this.pulse,
    required this.onPressed,
  });

  final String label;
  final bool isSpinning;
  final Animation<double> pulse;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isSpinning;
    final button = CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: enabled ? onPressed : null,
      child: Container(
        width: double.infinity,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          gradient: onPressed == null
              ? null
              : const LinearGradient(
                  colors: [Color(0xFFFF9F43), Color(0xFFFF5E8A)],
                ),
          color: onPressed == null
              ? CupertinoColors.systemGrey4.resolveFrom(context)
              : null,
          boxShadow: onPressed == null
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFFFF5E8A).withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: isSpinning
            ? const CupertinoActivityIndicator(color: CupertinoColors.white)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onPressed != null) ...[
                    const Icon(
                      CupertinoIcons.sparkles,
                      size: 20,
                      color: CupertinoColors.white,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: onPressed == null
                          ? CupertinoColors.secondaryLabel.resolveFrom(context)
                          : CupertinoColors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
    if (!enabled) return button;
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) => Transform.scale(
        scale: 1 + 0.025 * (0.5 + 0.5 * sin(pulse.value * 2 * pi * 12)),
        child: child,
      ),
      child: button,
    );
  }
}

/// Содержимое миниатюры приза — фото с сервера как есть (не обрезаем и не
/// кладём на подложку: изображения уже приходят готовыми, со своим фоном),
/// либо иконка подарка как заглушка.
class _PrizeThumb extends StatelessWidget {
  const _PrizeThumb({required this.prize, required this.size});

  final RoulettePrize prize;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconSize = size * 0.55;
    if (prize.photoUrl != null) {
      return CachedNetworkImage(
        imageUrl: prize.photoUrl!,
        fit: BoxFit.contain,
        width: size,
        height: size,
        errorWidget: (context, url, error) => Icon(
          CupertinoIcons.gift_fill,
          color: AppColors.primary,
          size: iconSize,
        ),
      );
    }
    return Icon(
      CupertinoIcons.gift_fill,
      color: AppColors.primary,
      size: iconSize,
    );
  }
}

/// Крупное изображение текущего приза — то единственное, что видно на весь
/// экран в моменте, вместо целого колеса со всеми секторами разом. Без
/// плашки-подложки и без подписи названия — только сам приз, максимально
/// акцентно.
class _HeroPrize extends StatelessWidget {
  const _HeroPrize({super.key, required this.prize});

  final RoulettePrize prize;

  @override
  Widget build(BuildContext context) {
    const size = 230.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: prize.photoUrl != null
              ? CachedNetworkImage(
                  imageUrl: prize.photoUrl!,
                  fit: BoxFit.contain,
                  errorWidget: (context, url, error) => const Icon(
                    CupertinoIcons.gift_fill,
                    color: AppColors.primary,
                    size: 120,
                  ),
                )
              : const Icon(
                  CupertinoIcons.gift_fill,
                  color: AppColors.primary,
                  size: 120,
                ),
        ),
        Transform.translate(
          offset: const Offset(0, -10),
          child: Container(
            width: 150,
            height: 16,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x47141C22), Color(0x00141C22)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Лента маленьких превью вокруг текущей позиции: то, что уже проехало,
/// текущий приз (крупнее, с акцентной обводкой) и то, что едет следующим.
/// `position` — дробный индекс в списке призов, во время вращения плавно
/// увеличивается, и тайлы едут навстречу как в игровом автомате.
class _ReelStrip extends StatelessWidget {
  const _ReelStrip({required this.prizes, required this.position});

  final List<RoulettePrize> prizes;
  final double position;

  static const double _tileExtent = 84;
  static const double _maxSize = 66;
  static const double _minSize = 46;

  RoulettePrize _prizeAt(int i, int n) => prizes[((i % n) + n) % n];

  @override
  Widget build(BuildContext context) {
    final n = prizes.length;
    const width = _tileExtent * 3;
    final base = position.floor();
    final tiles = <Widget>[
      for (var i = base - 2; i <= base + 2; i++) _buildTile(i, n),
    ];
    return ClipRect(
      child: SizedBox(
        width: width,
        height: _maxSize + 14,
        child: Stack(clipBehavior: Clip.none, children: tiles),
      ),
    );
  }

  Widget _buildTile(int i, int n) {
    final dist = (i - position).abs();
    final closeness = (1 - dist).clamp(0.0, 1.0);
    final size = _minSize + (_maxSize - _minSize) * closeness;
    final isCurrent = closeness > 0.85;
    final x = _tileExtent * 1.5 + (i - position) * _tileExtent - size / 2;
    final radius = size * 0.2;
    return Positioned(
      left: x,
      top: 7 + (_maxSize - size) / 2,
      child: Opacity(
        opacity: (0.4 + 0.6 * closeness).clamp(0.0, 1.0),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: isCurrent
                ? Border.all(color: _kWarmAccent, width: 2.5)
                : null,
          ),
          child: Center(
            child: _PrizeThumb(prize: _prizeAt(i, n), size: size * 0.82),
          ),
        ),
      ),
    );
  }
}
