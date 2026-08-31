import 'package:http/http.dart' as http;

import '../config/routes/bonus_program_routes.dart';
import '../models/bonus_program/achievement_type.dart';
import '../models/bonus_program/form_config.dart';
import '../models/bonus_program/form_submission.dart';
import '../models/bonus_program/point_balance.dart';
import '../models/bonus_program/point_operation.dart';
import '../models/bonus_program/point_transfer.dart';
import '../models/bonus_program/point_transfer_config.dart';
import '../models/bonus_program/roulette_config.dart';
import '../models/bonus_program/roulette_prize.dart';
import '../models/bonus_program/roulette_spin.dart';
import '../models/bonus_program/shop_item.dart';
import '../models/bonus_program/shop_request.dart';
import '../services/api_client.dart';
import '../services/api_envelope.dart';
import '../services/paginated.dart';

/// Файл-вложение к достижению (фото/документ, подтверждающий заслугу).
class FormAchievementFile {
  final String filename;
  final List<int> bytes;

  const FormAchievementFile({required this.filename, required this.bytes});
}

/// Черновик достижения для подачи ежемесячной формы.
class FormAchievementDraft {
  final int achievementTypeId;
  final String? description;
  final List<FormAchievementFile> files;

  const FormAchievementDraft({
    required this.achievementTypeId,
    this.description,
    this.files = const [],
  });
}

/// `/api/bonus-program/*` — баллы, магазин, рулетка и форма достижений.
class BonusProgramRepository {
  BonusProgramRepository._();
  static final BonusProgramRepository instance = BonusProgramRepository._();

  Future<PointBalance> getBalance() async {
    final decoded = await ApiClient.instance.get(BonusProgramRoutes.balanceUrl);
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось получить баланс баллов',
    );
    return PointBalance.fromJson(data);
  }

  Future<Paginated<PointOperation>> getHistory({String? url, int page = 1}) async {
    final decoded = url != null
        ? await ApiClient.instance.get(url)
        : await ApiClient.instance.get(
            BonusProgramRoutes.historyUrl,
            queryParameters: {'page': page.toString()},
          );
    return ApiPaginatedEnvelope.unwrapPaginated<PointOperation>(
      decoded,
      defaultErrorMessage: 'Не удалось получить историю операций',
      mapItem: PointOperation.fromJson,
    );
  }

  Future<PointTransferConfig> getTransferConfig() async {
    final decoded = await ApiClient.instance.get(BonusProgramRoutes.transferConfigUrl);
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось получить настройки перевода баллов',
    );
    return PointTransferConfig.fromJson(data);
  }

  Future<PointTransfer> transferPoints({
    required int recipientUserId,
    required int points,
    String? comment,
  }) async {
    final decoded = await ApiClient.instance.post(
      BonusProgramRoutes.transferUrl,
      body: {
        'recipient_user_id': recipientUserId,
        'points': points,
        if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
      },
    );
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось перевести баллы',
    );
    return PointTransfer.fromJson(data);
  }

  Future<List<ShopItem>> getShopItems() async {
    final decoded = await ApiClient.instance.get(BonusProgramRoutes.shopUrl);
    final list = ApiEnvelope.unwrapDataList(
      decoded,
      defaultErrorMessage: 'Не удалось получить товары магазина',
    );
    return list
        .whereType<Map>()
        .map((e) => ShopItem.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<ShopRequest> requestShopItem(int shopItemId) async {
    final decoded = await ApiClient.instance.post(
      BonusProgramRoutes.shopRequestUrl,
      body: {'shop_item_id': shopItemId},
    );
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось отправить заявку на товар',
    );
    return ShopRequest.fromJson(data);
  }

  Future<RouletteConfig> getRouletteConfig() async {
    final decoded = await ApiClient.instance.get(BonusProgramRoutes.rouletteConfigUrl);
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось получить настройки рулетки',
    );
    return RouletteConfig.fromJson(data);
  }

  Future<List<RoulettePrize>> getRoulettePrizes() async {
    final decoded = await ApiClient.instance.get(BonusProgramRoutes.roulettePrizesUrl);
    final list = ApiEnvelope.unwrapDataList(
      decoded,
      defaultErrorMessage: 'Не удалось получить список призов',
    );
    return list
        .whereType<Map>()
        .map((e) => RoulettePrize.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<RouletteSpin> spinRoulette() async {
    final decoded = await ApiClient.instance.post(BonusProgramRoutes.rouletteSpinUrl);
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось крутить рулетку',
    );
    return RouletteSpin.fromJson(data);
  }

  Future<List<AchievementType>> getAchievementTypes() async {
    final decoded = await ApiClient.instance.get(BonusProgramRoutes.achievementTypesUrl);
    final list = ApiEnvelope.unwrapDataList(
      decoded,
      defaultErrorMessage: 'Не удалось получить типы достижений',
    );
    return list
        .whereType<Map>()
        .map((e) => AchievementType.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<FormConfig> getFormConfig() async {
    final decoded = await ApiClient.instance.get(BonusProgramRoutes.formConfigUrl);
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось получить конфигурацию формы',
    );
    return FormConfig.fromJson(data);
  }

  /// Отправляет ежемесячную форму достижений: каждое достижение и его файлы
  /// уходят как `achievements[i][...]` в `multipart/form-data`.
  Future<FormSubmission> submitForm({
    required List<FormAchievementDraft> achievements,
    String? feedback,
  }) async {
    final fields = <String, String>{};
    final files = <http.MultipartFile>[];

    for (var i = 0; i < achievements.length; i++) {
      final achievement = achievements[i];
      fields['achievements[$i][achievement_type_id]'] =
          achievement.achievementTypeId.toString();
      final description = achievement.description?.trim();
      if (description != null && description.isNotEmpty) {
        fields['achievements[$i][description]'] = description;
      }
      for (final file in achievement.files) {
        files.add(
          http.MultipartFile.fromBytes(
            'achievements[$i][files][]',
            file.bytes,
            filename: file.filename,
          ),
        );
      }
    }

    if (feedback != null && feedback.trim().isNotEmpty) {
      fields['feedback'] = feedback.trim();
    }

    final decoded = await ApiClient.instance.postMultipart(
      BonusProgramRoutes.formSubmissionsUrl,
      fields: fields,
      files: files,
    );
    final data = ApiEnvelope.unwrapDataMap(
      decoded,
      defaultErrorMessage: 'Не удалось отправить форму',
    );
    return FormSubmission.fromJson(data);
  }
}
