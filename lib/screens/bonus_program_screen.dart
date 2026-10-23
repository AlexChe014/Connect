import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../config/app_theme.dart';
import '../models/bonus_program/point_balance.dart';
import '../models/bonus_program/point_operation.dart';
import '../models/bonus_program/roulette_config.dart';
import '../models/bonus_program/shop_item.dart';
import '../repositories/bonus_program_repository.dart';
import '../services/api_client.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/bonus_glass.dart';
import 'bonus_achievements_form_screen.dart';
import 'bonus_history_screen.dart';
import 'bonus_roulette_screen.dart';
import 'bonus_shop_screen.dart';
import 'bonus_transfer_screen.dart';

/// Раздел «Бонусная программа» по образцу Apple Cash в «Кошельке»:
/// карта баланса, ряд действий, лента товаров, на которые можно
/// потратить баллы, и последние операции.
class BonusProgramScreen extends StatefulWidget {
  const BonusProgramScreen({super.key});

  @override
  State<BonusProgramScreen> createState() => _BonusProgramScreenState();
}

class _BonusProgramScreenState extends State<BonusProgramScreen> {
  static const _recentCount = 5;

  PointBalance? _balance;
  RouletteConfig? _rouletteConfig;
  List<ShopItem> _shopItems = [];
  List<PointOperation> _recent = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = _balance == null;
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
    // Колесо, витрина и история необязательны для экрана — не блокируем
    // баланс, если что-то из них недоступно: блок просто не показывается.
    final repo = BonusProgramRepository.instance;
    repo
        .getRouletteConfig()
        .then((config) {
          if (mounted) setState(() => _rouletteConfig = config);
        })
        .catchError((_) {});
    repo
        .getShopItems()
        .then((items) {
          if (!mounted) return;
          final available =
              items.where((i) => i.isActive && !i.isOutOfStock).toList()
                ..sort((a, b) => a.price.compareTo(b.price));
          setState(() => _shopItems = available);
        })
        .catchError((_) {});
    repo
        .getHistory()
        .then((page) {
          if (!mounted) return;
          setState(() => _recent = page.data.take(_recentCount).toList());
        })
        .catchError((_) {});
  }

  /// После перевода, покупки или вращения баланс на главном экране
  /// должен быть свежим.
  Future<void> _open(Widget screen) async {
    await Navigator.of(
      context,
    ).push(CupertinoPageRoute(builder: (_) => screen));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return BonusGlassScaffold(
      title: 'Бонусная программа',
      largeTitle: true,
      onRefresh: _load,
      slivers: [_buildBody()],
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const BonusSliverLoader();

    final balance = _balance;
    if (balance == null) {
      return SliverAppEmptyState(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: _errorMessage ?? 'Не удалось загрузить баланс баллов',
        onRetry: _load,
      );
    }

    final roulette = _rouletteConfig;
    // Плашка колеса — только когда крутить действительно можно.
    final showRoulette = roulette != null && roulette.canSpin;
    return SliverList.list(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: _BalanceCard(balance: balance),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: AppGlassActionButton(
                  icon: CupertinoIcons.arrow_right_arrow_left,
                  label: 'Перевести',
                  onTap: () => _open(const BonusTransferScreen()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppGlassActionButton(
                  icon: CupertinoIcons.bag,
                  label: 'Магазин',
                  onTap: () => _open(const BonusShopScreen()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppGlassActionButton(
                  icon: CupertinoIcons.dial,
                  label: 'Колесо',
                  onTap: () => _open(const BonusRouletteScreen()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppGlassActionButton(
                  icon: CupertinoIcons.rosette,
                  label: 'Достижения',
                  onTap: () => _open(const BonusAchievementsFormScreen()),
                ),
              ),
            ],
          ),
        ),
        if (showRoulette)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _RoulettePromoCard(
              config: roulette,
              onTap: () => _open(const BonusRouletteScreen()),
            ),
          ),
        if (_shopItems.isNotEmpty) ...[
          _SectionHeader(
            title: 'Можно получить',
            onAll: () => _open(const BonusShopScreen()),
          ),
          SizedBox(
            height: 214,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              // Снизу запас под тень карточек.
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              itemCount: _shopItems.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) => SizedBox(
                width: 150,
                child: _ShopPreviewCard(
                  item: _shopItems[index],
                  balance: balance.points,
                  onTap: () => _open(const BonusShopScreen()),
                ),
              ),
            ),
          ),
        ],
        _SectionHeader(
          title: 'Последние операции',
          onAll: _recent.isEmpty
              ? null
              : () => _open(const BonusHistoryScreen()),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppFlatGlassCard(
            child: _recent.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'Операций пока нет',
                        style: TextStyle(
                          fontSize: 15,
                          color: CupertinoColors.secondaryLabel.resolveFrom(
                            context,
                          ),
                        ),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < _recent.length; i++) ...[
                        if (i > 0)
                          Container(
                            height: 0.5,
                            margin: const EdgeInsets.only(left: 64),
                            color: CupertinoColors.separator.resolveFrom(
                              context,
                            ),
                          ),
                        BonusOperationRow(operation: _recent[i]),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// Заголовок блока главного экрана с переходом «Все».
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onAll});

  final String title;
  final VoidCallback? onAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (onAll != null)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              onPressed: onAll,
              child: const Text(
                'Все',
                style: TextStyle(fontSize: 16, color: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Товар в ленте «Можно получить»: на что баллов уже хватает — цена
/// фирменным синим с галочкой, на остальное — сколько ещё накопить.
class _ShopPreviewCard extends StatelessWidget {
  const _ShopPreviewCard({
    required this.item,
    required this.balance,
    required this.onTap,
  });

  final ShopItem item;
  final int balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final affordable = balance >= item.price;
    final missing = item.price - balance;
    return BonusPhotoCard(
      photoUrl: item.photoUrl,
      title: item.name,
      onTap: onTap,
      footer: affordable
          ? Row(
              children: [
                const Icon(
                  CupertinoIcons.checkmark_seal_fill,
                  size: 14,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    formatPoints(item.price),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            )
          : Text(
              'Ещё ${formatPoints(missing)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
    );
  }
}

/// Баланс крупной цифрой на фирменном градиенте — как карта в «Кошельке».
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final PointBalance balance;

  @override
  Widget build(BuildContext context) {
    final number = NumberFormat.decimalPattern('ru_RU');
    const soft = AppColors.onPrimaryMuted;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppFestiveColors.balanceGradient,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Крупная полупрозрачная звезда — фактура, как на карте в «Кошельке».
          Positioned(
            right: -24,
            bottom: -34,
            child: Icon(
              CupertinoIcons.star_fill,
              size: 150,
              color: CupertinoColors.white.withValues(alpha: 0.12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ВАШ БАЛАНС',
                        style: TextStyle(
                          fontSize: 13,
                          letterSpacing: 0.2,
                          color: soft,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: number.format(balance.points),
                              style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.8,
                                color: CupertinoColors.white,
                              ),
                            ),
                            TextSpan(
                              text: '  ${pointsWord(balance.points)}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                                color: soft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (balance.pointsSpentTotal > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Потрачено всего: '
                          '${number.format(balance.pointsSpentTotal)} '
                          '${pointsWord(balance.pointsSpentTotal)}',
                          style: const TextStyle(fontSize: 13, color: soft),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CupertinoColors.white.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    CupertinoIcons.star_fill,
                    size: 22,
                    color: CupertinoColors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Приглашение крутить рулетку прямо с главного экрана бонусов —
/// медленно вращающаяся иконка привлекает внимание к геймификации,
/// ведёт на [BonusRouletteScreen].
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

    // Тёплые тона экрана колеса — приглашение выделяется среди
    // спокойных стеклянных плиток.
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: widget.onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppFestiveColors.buttonGradient,
          ),
          boxShadow: [
            BoxShadow(
              color: AppFestiveColors.pink.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            RotationTransition(
              turns: _controller,
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CupertinoColors.white.withValues(alpha: 0.24),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.sparkles,
                  size: 22,
                  color: CupertinoColors.white,
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
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: CupertinoColors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_forward,
              size: 17,
              color: CupertinoColors.white,
            ),
          ],
        ),
      ),
    );
  }
}
