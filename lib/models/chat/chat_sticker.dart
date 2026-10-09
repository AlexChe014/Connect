import 'package:connect/config/api_config.dart';

/// Набор стикеров портала: картинки `{host}/stickers/01.png` … `32.png`.
///
/// Сообщение считается стикером, только если одновременно
/// `type == "STICKER"` и его содержимое — один из идентификаторов набора
/// (так же решает портал).
class ChatStickers {
  ChatStickers._();

  static const String messageType = 'STICKER';

  static const int count = 32;

  /// `"01"` … `"32"`.
  static final List<String> ids = List<String>.unmodifiable(
    List<String>.generate(count, (i) => (i + 1).toString().padLeft(2, '0')),
  );

  static final Set<String> _idSet = ids.toSet();

  static bool isValidId(String? id) => id != null && _idSet.contains(id);

  static String url(String id) =>
      '${ApiConfig.backendHost.replaceAll(RegExp(r'/+$'), '')}/stickers/$id.png';
}
