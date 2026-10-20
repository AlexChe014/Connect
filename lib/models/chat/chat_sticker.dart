import 'package:connect/config/api_config.dart';

/// Набор стикеров портала: картинки `{host}/stickers/01.png` … `32.png`.
///
/// Любое сообщение `type == "STICKER"` — стикер, его содержимое — код.
/// Картинка показывается только для кода из набора и при
/// [imagesAvailable]; иначе в ленте заглушка, в превью — «Стикер».
class ChatStickers {
  ChatStickers._();

  static const String messageType = 'STICKER';

  /// Картинки лежат на портале. Без User-Agent сайт отвечает 403 (защита
  /// от ботов), поэтому `curl` без `-A` их «не видит»; приложение ходит
  /// с UA `Dart/…` и получает 200. При `false` в ленте рисуется заглушка,
  /// а выбор стикеров в поле ввода скрыт.
  static const bool imagesAvailable = true;

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
