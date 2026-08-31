import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';

import '../models/bonus_program/roulette_prize.dart';

const List<List<Color>> _kPrizeGradients = [
  [Color(0xFFFF6B6B), Color(0xFFFF9472)],
  [Color(0xFFF783AC), Color(0xFFCC5DE8)],
  [Color(0xFF4DABF7), Color(0xFF3BC9DB)],
  [Color(0xFF69DB7C), Color(0xFF20C997)],
  [Color(0xFFFFD43B), Color(0xFFFF922B)],
  [Color(0xFF9775FA), Color(0xFF5C7CFA)],
  [Color(0xFFFF8787), Color(0xFFE64980)],
  [Color(0xFF63E6BE), Color(0xFF15AABF)],
];

/// Полный список призов колеса фортуны — вынесен на отдельный экран
/// (открывается по кнопке «?» на экране колеса), чтобы сам экран колеса
/// оставался лёгким и не превращался в витрину.
class BonusRoulettePrizesScreen extends StatelessWidget {
  const BonusRoulettePrizesScreen({super.key, required this.prizes});

  final List<RoulettePrize> prizes;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Что можно выиграть'),
        backgroundColor: CupertinoColors.systemGroupedBackground,
        border: null,
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: CupertinoColors.label.resolveFrom(context),
          decoration: TextDecoration.none,
        ),
        child: SafeArea(
          child: prizes.isEmpty
              ? const Center(
                  child: Text(
                    'Список призов пуст',
                    style: TextStyle(color: CupertinoColors.secondaryLabel),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.76,
                  ),
                  itemCount: prizes.length,
                  itemBuilder: (context, i) => _PrizeCard(
                    prize: prizes[i],
                    gradient: _kPrizeGradients[i % _kPrizeGradients.length],
                  ),
                ),
        ),
      ),
    );
  }
}

/// Яркая карточка приза с фото — без указания шанса выпадения.
class _PrizeCard extends StatelessWidget {
  const _PrizeCard({required this.prize, required this.gradient});

  final RoulettePrize prize;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          if (prize.photoUrl != null)
            CachedNetworkImage(
              imageUrl: prize.photoUrl!,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => const _PrizeIconFallback(),
            )
          else
            const _PrizeIconFallback(),
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
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 22, 8, 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xCC000000)],
                ),
              ),
              child: Text(
                prize.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrizeIconFallback extends StatelessWidget {
  const _PrizeIconFallback();

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
