import 'package:flutter/cupertino.dart';

import '../models/bonus_program/roulette_prize.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/bonus_glass.dart';

/// Полный список призов колеса фортуны — вынесен на отдельный экран
/// (открывается по кнопке «?» на экране колеса), чтобы сам экран колеса
/// оставался лёгким и не превращался в витрину.
class BonusRoulettePrizesScreen extends StatelessWidget {
  const BonusRoulettePrizesScreen({super.key, required this.prizes});

  final List<RoulettePrize> prizes;

  @override
  Widget build(BuildContext context) {
    return BonusGlassScaffold(
      title: 'Что можно выиграть',
      slivers: [
        if (prizes.isEmpty)
          const SliverAppEmptyState(
            icon: CupertinoIcons.gift,
            message: 'Список призов пуст',
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // Карточка приза — без указания шанса выпадения.
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemCount: prizes.length,
              itemBuilder: (context, i) => BonusPhotoCard(
                photoUrl: prizes[i].photoUrl,
                title: prizes[i].name,
              ),
            ),
          ),
      ],
    );
  }
}
