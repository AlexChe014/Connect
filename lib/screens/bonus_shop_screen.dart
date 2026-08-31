import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show RefreshIndicator;

import '../models/bonus_program/shop_item.dart';
import '../repositories/bonus_program_repository.dart';
import '../services/api_client.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_loading.dart';
import '../widgets/confetti_overlay.dart';

const List<List<Color>> _kShopGradients = [
  [Color(0xFFFF6B6B), Color(0xFFFF9472)],
  [Color(0xFFF783AC), Color(0xFFCC5DE8)],
  [Color(0xFF4DABF7), Color(0xFF3BC9DB)],
  [Color(0xFF69DB7C), Color(0xFF20C997)],
  [Color(0xFFFFD43B), Color(0xFFFF922B)],
  [Color(0xFF9775FA), Color(0xFF5C7CFA)],
  [Color(0xFFFF8787), Color(0xFFE64980)],
  [Color(0xFF63E6BE), Color(0xFF15AABF)],
];

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
        content: Text('«${item.name}» за ${item.price} баллов.'),
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
      await _showPurchaseSuccess(item, request.isApproved);
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

  Future<void> _showPurchaseSuccess(ShopItem item, bool approved) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'purchase-result',
      barrierColor: const Color(0x99000000),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return Opacity(
          opacity: anim.value.clamp(0, 1),
          child: Transform.scale(
            scale: 0.7 + 0.3 * curved.value.clamp(0, 1.2),
            child: Center(child: _PurchaseResultCard(item: item, approved: approved)),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Магазин'),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
        trailing: _isBusy ? const CupertinoActivityIndicator() : null,
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
    if (_isLoading) return const AppSkeletonList(count: 6);

    if (_errorMessage != null) {
      return AppEmptyState(
        icon: CupertinoIcons.exclamationmark_triangle,
        message: _errorMessage!,
        onRetry: _load,
      );
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: const AppEmptyState(
          icon: CupertinoIcons.gift,
          message: 'В магазине пока нет товаров',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.76,
        ),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return _ShopItemCard(
            item: item,
            gradient: _kShopGradients[index % _kShopGradients.length],
            onBuy: (item.isActive && !item.isOutOfStock && !_isBusy)
                ? () => _requestItem(item)
                : null,
          );
        },
      ),
    );
  }
}

/// Карточка товара: фото, название, цена и кнопка покупки одной штуки.
/// Количество не выбирается — за один тап уходит заявка ровно на 1 товар.
/// Оформление в стиле карточек призов колеса фортуны — яркий градиент,
/// фото на всю карточку и подпись поверх затемнения снизу.
class _ShopItemCard extends StatelessWidget {
  const _ShopItemCard({
    required this.item,
    required this.gradient,
    required this.onBuy,
  });

  final ShopItem item;
  final List<Color> gradient;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context) {
    final disabled = onBuy == null;

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          boxShadow: [
            BoxShadow(
              color: gradient.last.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (item.photoUrl != null)
              CachedNetworkImage(
                imageUrl: item.photoUrl!,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) =>
                    const _ShopItemIconFallback(),
              )
            else
              const _ShopItemIconFallback(),
            Positioned(
              top: -30,
              left: -40,
              child: Transform.rotate(
                angle: -0.5,
                child: Container(
                  width: 90,
                  height: 170,
                  color: CupertinoColors.white.withValues(alpha: 0.16),
                ),
              ),
            ),
            if (item.isOutOfStock)
              Positioned(
                top: 8,
                left: 8,
                child: _Badge(
                  text: 'Нет в наличии',
                  color: CupertinoColors.systemRed,
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 22, 10, 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC000000)],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item.price} баллов',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CupertinoColors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _BuyButton(onTap: onBuy),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кнопка «купить одну штуку» — без степпера количества.
class _BuyButton extends StatelessWidget {
  const _BuyButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: disabled
              ? CupertinoColors.white.withValues(alpha: 0.3)
              : CupertinoColors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(
          CupertinoIcons.cart_badge_plus,
          size: 14,
          color: disabled ? CupertinoColors.white : CupertinoColors.black,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: CupertinoColors.white,
        ),
      ),
    );
  }
}

class _ShopItemIconFallback extends StatelessWidget {
  const _ShopItemIconFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0x00000000),
      child: Center(
        child: Icon(CupertinoIcons.gift_fill, color: CupertinoColors.white, size: 44),
      ),
    );
  }
}

/// Карточка результата покупки — в том же приподнятом праздничном стиле,
/// что и карточка выигрыша в колесе фортуны: конфетти, фото товара в
/// кружке сверху и статус заявки.
class _PurchaseResultCard extends StatelessWidget {
  const _PurchaseResultCard({required this.item, required this.approved});

  final ShopItem item;
  final bool approved;

  @override
  Widget build(BuildContext context) {
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
                  const Text(
                    '🎉 Ура!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Спасибо за покупку!\n«${item.name}»',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      color: CupertinoColors.secondaryLabel,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    approved
                        ? 'Товар уже выдан'
                        : 'Заявка на выдачу отправлена на согласование',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: approved
                          ? CupertinoColors.systemGreen
                          : CupertinoColors.systemOrange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFFFD966), Color(0xFFE0A200)],
                  ),
                  border: Border.fromBorderSide(
                    BorderSide(color: CupertinoColors.white, width: 4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: item.photoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: item.photoUrl!,
                        fit: BoxFit.cover,
                        width: 68,
                        height: 68,
                        errorWidget: (context, url, error) => const Icon(
                          CupertinoIcons.gift_fill,
                          color: CupertinoColors.white,
                          size: 32,
                        ),
                      )
                    : const Icon(
                        CupertinoIcons.gift_fill,
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
