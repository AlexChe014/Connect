import 'package:flutter/cupertino.dart';

import '../config/app_theme.dart';
import '../models/bonus_program/shop_item.dart';
import '../repositories/bonus_program_repository.dart';
import '../services/api_client.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/bonus_glass.dart';

/// Магазин: витрина товаров за баллы и заявка на получение.
/// За один раз можно купить только один товар — без корзины и количества.
class BonusShopScreen extends StatefulWidget {
  const BonusShopScreen({super.key});

  @override
  State<BonusShopScreen> createState() => _BonusShopScreenState();
}

class _BonusShopScreenState extends State<BonusShopScreen> {
  List<ShopItem> _items = [];
  bool _isLoading = true;
  bool _isBusy = false;
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
      final items = await BonusProgramRepository.instance.getShopItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is ApiException
            ? e.message
            : 'Не удалось получить товары магазина';
      });
    }
  }

  Future<void> _requestItem(ShopItem item) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Запросить товар?'),
        content: Text('«${item.name}» за ${formatPoints(item.price)}.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Запросить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isBusy = true);
    try {
      final request = await BonusProgramRepository.instance.requestShopItem(
        item.id,
      );
      if (!mounted) return;
      await showBonusCelebration(
        context,
        title: '🎉 Ура!',
        message: 'Спасибо за покупку!\n«${item.name}»',
        status: request.isApproved
            ? 'Товар уже выдан'
            : 'Заявка на выдачу отправлена на согласование',
        statusColor: request.isApproved
            ? CupertinoColors.systemGreen
            : CupertinoColors.systemOrange,
        photoUrl: item.photoUrl,
      );
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : 'Не удалось отправить заявку';
      showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Ок'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BonusGlassScaffold(
      title: 'Магазин',
      onRefresh: _load,
      trailing: _isBusy ? const CupertinoActivityIndicator() : null,
      slivers: [_buildBody()],
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const BonusSliverLoader();

    if (_errorMessage != null) {
      return SliverAppEmptyState(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: _errorMessage!,
        onRetry: _load,
      );
    }

    if (_items.isEmpty) {
      return const SliverAppEmptyState(
        icon: CupertinoIcons.gift,
        message: 'В магазине пока нет товаров',
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.7,
        ),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          final onBuy = (item.isActive && !item.isOutOfStock && !_isBusy)
              ? () => _requestItem(item)
              : null;
          return BonusPhotoCard(
            photoUrl: item.photoUrl,
            title: item.name,
            dimmed: !item.isActive || item.isOutOfStock,
            onTap: onBuy,
            badge: item.isOutOfStock ? const _OutOfStockBadge() : null,
            footer: Row(
              children: [
                Expanded(
                  child: Text(
                    formatPoints(item.price),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _BuyButton(onTap: onBuy),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Кнопка «купить одну штуку» — без степпера количества: за один тап
/// уходит заявка ровно на 1 товар.
class _BuyButton extends StatelessWidget {
  const _BuyButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.primary
              : CupertinoColors.systemGrey4.resolveFrom(context),
          shape: BoxShape.circle,
        ),
        child: Icon(
          CupertinoIcons.cart_badge_plus,
          size: 16,
          color: enabled
              ? CupertinoColors.white
              : CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}

class _OutOfStockBadge extends StatelessWidget {
  const _OutOfStockBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: CupertinoColors.systemRed.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'Нет в наличии',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: CupertinoColors.white,
        ),
      ),
    );
  }
}
