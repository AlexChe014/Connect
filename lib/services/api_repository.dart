import 'package:connect/config/api_config.dart';
import 'package:connect/models/booking.dart';
import 'package:connect/models/meeting_room.dart';
import 'package:connect/models/news_item.dart';
import 'package:connect/services/api_client.dart';

class ApiRepository {
  ApiRepository._();
  static final ApiRepository instance = ApiRepository._();

  Future<List<NewsItem>> getNews() async {
    if (ApiConfig.useMockApi) return _mockNews;
    try {
      final data = await ApiClient.instance.get(ApiConfig.newsUrl);
      final list =
          data['data'] as List? ??
          data['items'] as List? ??
          data as List? ??
          [];
      return list
          .map((e) => NewsItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _mockNews;
    }
  }

  Future<List<MeetingRoom>> getRooms() async {
    if (ApiConfig.useMockApi) return _mockRooms;
    try {
      final data = await ApiClient.instance.get(ApiConfig.roomsUrl);
      final list =
          data['data'] as List? ??
          data['items'] as List? ??
          data as List? ??
          [];
      return list
          .map((e) => MeetingRoom.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _mockRooms;
    }
  }

  Future<List<Booking>> getBookings() async {
    if (ApiConfig.useMockApi) return _mockBookings();
    try {
      final data = await ApiClient.instance.get(ApiConfig.bookingsUrl);
      final list =
          data['data'] as List? ??
          data['items'] as List? ??
          data as List? ??
          [];
      return list
          .map((e) => Booking.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _mockBookings();
    }
  }

  Future<Map<String, dynamic>?> getProfile() async {
    if (ApiConfig.useMockApi) return _mockProfile;
    try {
      return await ApiClient.instance.get(ApiConfig.profileUrl);
    } catch (_) {
      return _mockProfile;
    }
  }

  static List<NewsItem> get _mockNews => [
    NewsItem(
      id: '1',
      title: 'Новый офис открыт в центре города',
      content:
          'Рады сообщить, что наш новый офисный центр открыл двери для арендаторов. '
          'Современные переговорные комнаты, зоны коворкинга и удобная инфраструктура ждут вас.',
      date: DateTime.now().subtract(const Duration(days: 1)),
    ),
    NewsItem(
      id: '2',
      title: 'Обновление системы бронирования',
      content:
          'Мы обновили систему бронирования переговорных комнат. '
          'Теперь вы можете видеть доступность в реальном времени и бронировать на месяц вперёд.',
      date: DateTime.now().subtract(const Duration(days: 3)),
    ),
    NewsItem(
      id: '3',
      title: 'Бесплатный кофе в зоне отдыха',
      content:
          'С понедельника в зоне отдыха доступен бесплатный кофе и чай для всех арендаторов. '
          'Приятного рабочего дня!',
      date: DateTime.now().subtract(const Duration(days: 5)),
    ),
  ];

  static List<MeetingRoom> get _mockRooms => [
    const MeetingRoom(
      id: 'room1',
      name: 'Конференц-зал А',
      capacity: 12,
      description: 'Большой зал для совещаний с проектором',
      amenities: ['Проектор', 'Доска', 'Видеоконференция'],
    ),
    const MeetingRoom(
      id: 'room2',
      name: 'Переговорная Б',
      capacity: 6,
      description: 'Компактная комната для небольших встреч',
      amenities: ['Доска', 'TV'],
    ),
    const MeetingRoom(
      id: 'room3',
      name: 'Креатив-студия',
      capacity: 8,
      description: 'Пространство для мозговых штурмов',
      amenities: ['Интерактивная доска', 'Маркеры', 'Стикеры'],
    ),
    const MeetingRoom(
      id: 'room4',
      name: 'Мини-зал В',
      capacity: 4,
      description: 'Идеально для 1-on-1 встреч',
      amenities: ['TV'],
    ),
  ];

  static List<Booking> _mockBookings() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return [
      Booking(
        id: 'b1',
        roomId: 'room1',
        roomName: 'Конференц-зал А',
        title: 'Планирование спринта',
        startTime: today.add(const Duration(hours: 10)),
        endTime: today.add(const Duration(hours: 12)),
        organizer: 'Иван Петров',
      ),
      Booking(
        id: 'b2',
        roomId: 'room2',
        roomName: 'Переговорная Б',
        title: 'Встреча с клиентом',
        startTime: today.add(const Duration(hours: 14)),
        endTime: today.add(const Duration(hours: 15, minutes: 30)),
        organizer: 'Мария Сидорова',
      ),
      Booking(
        id: 'b3',
        roomId: 'room3',
        roomName: 'Креатив-студия',
        title: 'Брейншторм',
        startTime: today.add(const Duration(hours: 16)),
        endTime: today.add(const Duration(hours: 17, minutes: 30)),
        organizer: 'Алексей Козлов',
      ),
      Booking(
        id: 'b4',
        roomId: 'room1',
        roomName: 'Конференц-зал А',
        title: 'Презентация проекта',
        startTime: tomorrow.add(const Duration(hours: 9)),
        endTime: tomorrow.add(const Duration(hours: 11)),
        organizer: 'Ольга Новикова',
      ),
    ];
  }

  static Map<String, dynamic> get _mockProfile => {
    'id': '1',
    'email': 'user@example.com',
    'surname': 'Тестовый',
    'name': 'Пользователь',
    'position': 'веб-разработчик',
    'status': 'Выгорел',
    'avatar': null,
  };
}
