/// Конфигурация подключения к REST API.
///
/// Для production замените значения на реальные параметры сервера.
class ApiConfig {
  ApiConfig._();

  /// Базовый URL API (без завершающего слеша)
  static const String baseUrl = 'https://api.example.com/v1';

  /// Использовать mock-данные вместо реального API (для разработки без backend)
  static const bool useMockApi = true;

  /// Endpoint для авторизации
  static const String authLoginPath = '/auth/login';

  /// Endpoint для получения новостей
  static const String newsPath = '/news';

  /// Endpoint для получения переговорных комнат
  static const String roomsPath = '/rooms';

  /// Endpoint для получения бронирований
  static const String bookingsPath = '/bookings';

  /// Endpoint для получения профиля пользователя
  static const String profilePath = '/profile';

  /// База URL для API чатов (создание, сообщения) — при `useMockApi` не используется
  static const String chatsPath = '/chats';

  /// Таймаут запросов в секундах
  static const int timeoutSeconds = 30;

  static String get authLoginUrl => '$baseUrl$authLoginPath';
  static String get newsUrl => '$baseUrl$newsPath';
  static String get roomsUrl => '$baseUrl$roomsPath';
  static String get bookingsUrl => '$baseUrl$bookingsPath';
  static String get profileUrl => '$baseUrl$profilePath';
  static String get chatsBaseUrl => '$baseUrl$chatsPath';
}
