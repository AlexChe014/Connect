import 'package:connect/repositories/users_repository.dart';
import 'package:flutter/foundation.dart';

/// Общий кэш дней рождения сотрудников по id пользователя.
///
/// Чаты знают только `peerUserId`, без даты рождения — грузим справочник
/// сотрудников постранично один раз и переиспользуем его для бейджа 🎂
/// в списке чатов и шапке диалога, не трогая бэкенд чатов.
class BirthdayDirectory extends ChangeNotifier {
  BirthdayDirectory._();
  static final BirthdayDirectory instance = BirthdayDirectory._();

  final Map<int, DateTime?> _birthdayByUserId = {};
  bool _loading = false;
  bool _loaded = false;

  bool isBirthdayToday(int? userId) {
    if (userId == null) return false;
    final birthday = _birthdayByUserId[userId];
    if (birthday == null) return false;
    final now = DateTime.now();
    return birthday.month == now.month && birthday.day == now.day;
  }

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      String? nextUrl;
      var page = 1;
      do {
        final result = await UsersRepository.instance.getPage(
          url: nextUrl,
          page: page,
        );
        for (final user in result.data) {
          final id = user.idAsInt;
          if (id != null) _birthdayByUserId[id] = user.birthday;
        }
        nextUrl = result.nextPageUrl;
        page++;
      } while (nextUrl != null);
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // Бейдж ДР — не критичная функциональность, тихо игнорируем сбой.
    } finally {
      _loading = false;
    }
  }
}
