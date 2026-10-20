import 'package:connect/config/api_config.dart';

/// Набор стикеров портала: картинки `{host}/stickers/01.png` … `32.png`.
///
/// Любое сообщение `type == "STICKER"` — стикер, его содержимое — код.
/// Картинка показывается только для кода из набора и при
/// [imagesAvailable]; иначе в ленте заглушка, в превью — «Стикер».
class ChatStickers {
  ChatStickers._();

  static const String messageType = 'STICKER';

  /// Картинок стикеров на сервере пока нет: в ленте рисуется заглушка,
  /// а выбор стикеров в поле ввода скрыт. Включить, когда картинки появятся.
  static const bool imagesAvailable = false;

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
