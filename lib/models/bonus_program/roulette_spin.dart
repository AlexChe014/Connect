import '../../services/paginated.dart';
import 'reward_request.dart';
import 'roulette_prize.dart';

/// Результат вращения рулетки (`RouletteSpinResource`).
class RouletteSpin {
  final int id;
  final int spinCost;
  final RoulettePrize? prize;
  final RewardRequest? prizeRequest;

  const RouletteSpin({
    required this.id,
    required this.spinCost,
    this.prize,
    this.prizeRequest,
  });

  factory RouletteSpin.fromJson(Map<String, dynamic> json) {
    final rawPrize = json['prize'];
    final rawPrizeRequest = json['prize_request'];
    return RouletteSpin(
      id: ApiPaginatedEnvelope.parseInt(json['id']) ?? 0,
      spinCost: ApiPaginatedEnvelope.parseInt(json['spin_cost']) ?? 0,
      prize: rawPrize is Map
          ? RoulettePrize.fromJson(Map<String, dynamic>.from(rawPrize))
          : null,
      prizeRequest: rawPrizeRequest is Map
          ? RewardRequest.fromJson(Map<String, dynamic>.from(rawPrizeRequest))
          : null,
    );
  }
}
