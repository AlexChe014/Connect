import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show RefreshIndicator;

import '../config/app_icons.dart';
import '../models/bonus_program/point_balance.dart';
import '../models/bonus_program/roulette_config.dart';
import '../repositories/bonus_program_repository.dart';
import '../services/api_client.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
import 'bonus_achievements_form_screen.dart';
import 'bonus_history_screen.dart';
import 'bonus_roulette_screen.dart';
import 'bonus_shop_screen.dart';
import 'bonus_transfer_screen.dart';

/// Раздел «Бонусная программа»: баланс баллов и переходы в магазин,
/// рулетку, перевод баллов коллеге и форму достижений.
class BonusProgramScreen extends StatefulWidget {
  const BonusProgramScreen({super.key});

  @override
  State<BonusProgramScreen> createState() => _BonusProgramScreenState();
}

class _BonusProgramScreenState extends State<BonusProgramScreen> {
  PointBalance? _balance;
  RouletteConfig? _rouletteConfig;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final balance = await BonusProgramRepository.instance.getBalance();
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is ApiException
            ? e.message
            : 'Не удалось загрузить баланс баллов';
      });
      return;
    }
    // Промо-карточка рулетки необязательна для экрана — не блокируем
    // основной баланс, если её настройки недоступны.
    BonusProgramRepository.instance
        .getRouletteConfig()
        .then((config) {
          if (mounted) setState(() => _rouletteConfig = config);
        })
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Бонусная программа'),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: CupertinoColors.label.resolveFrom(context),
          decoration: TextDecoration.none,
        ),
        child: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const AppPageLoader();

    if (_errorMessage != null) {
      return AppEmptyState(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: _errorMessage!,
        onRetry: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          if (_balance != null) _BalanceCard(balance: _balance!),
          if (_rouletteConfig != null && _rouletteConfig!.enabled) ...[
            const SizedBox(height: 12),
            _RoulettePromoCard(
              config: _rouletteConfig!,
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute(builder: (_) => const BonusRouletteScreen()),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _BonusFeatureCard(
                  icon: AppIcons.bonusHistory,
                  title: 'История баллов',
                  subtitle: 'Начисления и списания',
                  colors: const [Color(0xFF36D1DC), Color(0xFF5B86E5)],
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (_) => const BonusHistoryScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BonusFeatureCard(
                  icon: AppIcons.bonusTransfer,
                  title: 'Перевести баллы',
                  subtitle: 'Поделитесь с коллегой',
                  colors: const [Color(0xFF8E54E9), Color(0xFF4776E6)],
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (_) => const BonusTransferScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _BonusFeatureCard(
                  icon: AppIcons.bonusShop,
                  title: 'Магазин',
                  subtitle: 'Обменяйте баллы на призы',
                  colors: const [Color(0xFFFF5F6D), Color(0xFFFFC371)],
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (_) => const BonusShopScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BonusFeatureCard(
                  icon: AppIcons.bonusWheel,
                  title: 'Колесо фортуны',
                  subtitle: 'Испытайте удачу',
                  colors: const [Color(0xFFF6D365), Color(0xFFFDA085)],
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (_) => const BonusRouletteScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _BonusWideCard(
            icon: AppIcons.bonusTrophy,
            title: 'Форма достижений',
            subtitle: 'Заявка на бонусные баллы',
            colors: const [Color(0xFF11998E), Color(0xFF38EF7D)],
            onTap: () => Navigator.of(context).push(
              CupertinoPageRoute(
                builder: (_) => const BonusAchievementsFormScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final PointBalance balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7F53E9), Color(0xFFC969E9)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7F53E9).withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -22,
            top: -26,
            child: Icon(
              AppIcons.bonusSparkles,
              size: 120,
              color: CupertinoColors.white.withValues(alpha: 0.12),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ваш баланс',
                      style: TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${balance.points} баллов',
                      style: const TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Потрачено всего: ${balance.pointsSpentTotal}',
                      style: const TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CupertinoColors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  AppIcons.bonusWallet,
                  color: CupertinoColors.white,
                  size: 24,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Яркая карточка-приглашение крутить рулетку прямо с главного экрана
/// бонусов — привлекает внимание к геймификации, ведёт на [BonusRouletteScreen].
class _RoulettePromoCard extends StatefulWidget {
  const _RoulettePromoCard({required this.config, required this.onTap});

  final RouletteConfig config;
  final VoidCallback onTap;

  @override
  State<_RoulettePromoCard> createState() => _RoulettePromoCardState();
}

class _RoulettePromoCardState extends State<_RoulettePromoCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.config.spinsRemainingThisMonth;
    final subtitle = remaining != null
        ? (remaining > 0
              ? 'Осталось вращений: $remaining'
              : 'Лимит на этот месяц исчерпан')
        : 'Испытайте удачу и выиграйте приз';

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF8A3D), Color(0xFFFF5F6D)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF5F6D).withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _controller.value * 2 * pi,
                  child: child,
                );
              },
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CupertinoColors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.sparkles,
                  color: CupertinoColors.white,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Крутите колесо фортуны!',
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: CupertinoColors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.arrow_right_circle_fill,
              color: CupertinoColors.white,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}

/// Квадратная цветная карточка раздела бонусной программы: крупная
/// декоративная иконка на градиентном фоне, заголовок и подпись.
class _BonusFeatureCard extends StatelessWidget {
  const _BonusFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 148,
        padding: const EdgeInsets.all(14),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -18,
              bottom: -18,
              child: Icon(
                icon,
                size: 92,
                color: CupertinoColors.white.withValues(alpha: 0.16),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CupertinoColors.white.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 21, color: CupertinoColors.white),
                ),
                const Spacer(),
                Text(
                  title,
                  style: const TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CupertinoColors.white.withValues(alpha: 0.85),
                    fontSize: 11.5,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Широкая цветная карточка на всю ширину — для менее «игровых» действий
/// раздела бонусов, например заявки на достижение.
class _BonusWideCard extends StatelessWidget {
  const _BonusWideCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: 0.3),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -14,
              top: -20,
              child: Icon(
                icon,
                size: 90,
                color: CupertinoColors.white.withValues(alpha: 0.14),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CupertinoColors.white.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, size: 23, color: CupertinoColors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: CupertinoColors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  CupertinoIcons.chevron_forward,
                  color: CupertinoColors.white,
                  size: 18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
