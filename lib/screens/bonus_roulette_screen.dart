import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show RefreshIndicator;
import 'package:flutter/services.dart' show HapticFeedback;

import '../config/app_theme.dart';
import '../models/bonus_program/roulette_config.dart';
import '../models/bonus_program/roulette_prize.dart';
import '../models/bonus_program/roulette_spin.dart';
import '../repositories/bonus_program_repository.dart';
import '../services/api_client.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/confetti_overlay.dart';
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
    with SingleTickerProviderStateMixin {
  RouletteConfig? _config;
  List<RoulettePrize> _prizes = [];
  bool _isLoading = true;
  bool _isSpinning = false;
  String? _errorMessage;

  late final AnimationController _spinController;
  Animation<double>? _reelAnimation;
  double? _restPosition;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    _load();
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
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

    _reelAnimation = Tween<double>(begin: startPosition, end: finalPosition).animate(
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
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'roulette-result',
      barrierColor: const Color(0x99000000),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return Opacity(
          opacity: anim.value.clamp(0, 1),
          child: Transform.scale(
            scale: 0.7 + 0.3 * curved.value.clamp(0, 1.2),
            child: Center(child: _ResultCard(prize: prize, pending: pending)),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFB3402F),
      navigationBar: CupertinoNavigationBar(
        middle: const Text(
          'Колесо фортуны',
          style: TextStyle(color: CupertinoColors.white),
        ),
        backgroundColor: const Color(0x00000000),
        border: null,
        brightness: Brightness.dark,
        trailing: _isLoading
            ? null
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (_) => BonusRoulettePrizesScreen(prizes: _prizes),
                  ),
                ),
                child: const Icon(CupertinoIcons.question_circle, color: CupertinoColors.white),
              ),
      ),
      child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.0,
            colors: [Color(0xFFFFC38A), Color(0xFFFF8A5C), Color(0xFFB3402F)],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CupertinoActivityIndicator(radius: 14, color: CupertinoColors.white),
      );
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
      return RefreshIndicator(
        onRefresh: _load,
        child: const AppEmptyState(
          icon: CupertinoIcons.sparkles,
          message: 'Колесо фортуны сейчас недоступно',
        ),
      );
    }

    return Column(
      children: [
        Expanded(child: Center(child: _buildReel())),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _buildSpinButton(config),
        ),
      ],
    );
  }

  Widget _buildReel() {
    if (_prizes.isEmpty) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _spinController,
      builder: (context, child) {
        final position = _isSpinning && _reelAnimation != null
            ? _reelAnimation!.value
            : (_restPosition ?? 0.0);
        final n = _prizes.length;
        final centerIndex = ((position.round() % n) + n) % n;
        final currentPrize = _prizes[centerIndex];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: _HeroPrize(
                key: ValueKey(currentPrize.id),
                prize: currentPrize,
              ),
            ),
            const SizedBox(height: 22),
            Center(child: _ReelStrip(prizes: _prizes, position: position)),
            const SizedBox(height: 8),
            const Icon(
              CupertinoIcons.arrowtriangle_up_fill,
              color: Color(0xFFFFD166),
              size: 16,
            ),
          ],
        );
      },
    );
  }

  Widget _buildSpinButton(RouletteConfig config) {
    final enabled = config.canSpin && !_isSpinning;
    final label = _isSpinning
        ? 'Крутим...'
        : (config.canSpin
              ? 'Крутить за ${config.spinCost} баллов'
              : 'Колесо недоступно');
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton(
        onPressed: enabled ? _spin : null,
        padding: const EdgeInsets.symmetric(vertical: 16),
        borderRadius: BorderRadius.circular(28),
        color: CupertinoColors.white,
        disabledColor: CupertinoColors.white.withValues(alpha: 0.5),
        child: _isSpinning
            ? const CupertinoActivityIndicator(color: AppColors.primary)
            : Text(
                label,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
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
        errorWidget: (context, url, error) =>
            Icon(CupertinoIcons.gift_fill, color: AppColors.primary, size: iconSize),
      );
    }
    return Icon(CupertinoIcons.gift_fill, color: AppColors.primary, size: iconSize);
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
    const size = 260.0;
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
                    color: Color(0xFF242833),
                    size: 130,
                  ),
                )
              : const Icon(
                  CupertinoIcons.gift_fill,
                  color: Color(0xFF242833),
                  size: 130,
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
          padding: EdgeInsets.all(size * 0.08),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [CupertinoColors.white, Color(0xFFE3ECFF), Color(0xFFBFD3FF)],
            ),
            border: isCurrent ? Border.all(color: const Color(0xFFFFD166), width: 2.5) : null,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2A1208).withValues(alpha: isCurrent ? 0.4 : 0.26),
                blurRadius: isCurrent ? 14 : 8,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius * 0.7),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(child: _PrizeThumb(prize: _prizeAt(i, n), size: size * 0.62)),
                // Лёгкий глянцевый блик сверху — создаёт ощущение объёма.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: size * 0.4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          CupertinoColors.white.withValues(alpha: 0.55),
                          CupertinoColors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.prize, required this.pending});

  final RoulettePrize? prize;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final won = prize != null;
    return DefaultTextStyle(
      style: const TextStyle(
        color: CupertinoColors.label,
        decoration: TextDecoration.none,
      ),
      child: SizedBox(
      width: 300,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          if (won)
            const Positioned(
              top: -60,
              child: SizedBox(width: 320, height: 320, child: ConfettiOverlay()),
            ),
          Container(
            margin: const EdgeInsets.only(top: 28),
            padding: const EdgeInsets.fromLTRB(24, 44, 24, 24),
            decoration: BoxDecoration(
              color: CupertinoColors.systemBackground.resolveFrom(context),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  won ? '🎉 Поздравляем!' : 'Почти получилось',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  won
                      ? 'Вы выиграли:\n«${prize!.name}»'
                      : 'В этот раз без приза — попробуйте ещё раз в следующем месяце!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: CupertinoColors.secondaryLabel,
                  ),
                ),
                if (won && pending) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Заявка на выдачу отправлена на согласование',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.systemOrange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    borderRadius: BorderRadius.circular(14),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Отлично!'),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            child: Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: won
                      ? const [Color(0xFFFFD966), Color(0xFFE0A200)]
                      : const [CupertinoColors.systemGrey4, CupertinoColors.systemGrey3],
                ),
                border: Border.all(color: CupertinoColors.white, width: 4),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: won && prize!.photoUrl != null
                  ? CachedNetworkImage(
                      imageUrl: prize!.photoUrl!,
                      fit: BoxFit.cover,
                      width: 68,
                      height: 68,
                      errorWidget: (context, url, error) => const Icon(
                        CupertinoIcons.gift_fill,
                        color: CupertinoColors.white,
                        size: 32,
                      ),
                    )
                  : Icon(
                      won ? CupertinoIcons.gift_fill : CupertinoIcons.sparkles,
                      color: CupertinoColors.white,
                      size: 32,
                    ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

