import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connect/models/bookings/user_booking.dart';
import 'package:connect/repositories/bookings_repository.dart';
import 'package:connect/services/auth_service.dart';
import 'package:connect/services/chat_service.dart';
import 'package:connect/services/document_pending_service.dart';
import 'package:connect/services/mail_unread_service.dart';
import 'package:connect/utils/app_logger.dart';
import 'package:flutter/services.dart';

/// Данные виджета «Сегодня» на домашнем экране и экране блокировки (iOS):
/// ближайшие встречи и счётчики чатов, почты и документов на подпись.
///
/// Счётчики берутся из уже живущих сервисов, встречи — тем же запросом
/// броней, что в профиле. В нативную часть (App Group, см.
/// ios/Runner/WidgetBridge.swift) пишем только изменения, не чаще раза
/// в секунду.
class HomeWidgetService {
  HomeWidgetService._();
  static final HomeWidgetService instance = HomeWidgetService._();

  static const _channel = MethodChannel('connect/home_widget');
  static const _bookingsTtl = Duration(minutes: 5);
  static const _maxMeetings = 10;

  bool _initialized = false;
  Timer? _debounce;
  String? _lastJson;
  List<UserBooking> _meetings = const [];
  DateTime? _meetingsLoadedAt;

  bool get _supported => Platform.isIOS;

  void init() {
    if (!_supported || _initialized) return;
    _initialized = true;
    ChatService.instance.addListener(_scheduleSync);
    MailUnreadService.instance.addListener(_scheduleSync);
    DocumentPendingService.instance.addListener(_scheduleSync);
    if (AuthService.instance.isAuthenticated) unawaited(refresh());
  }

  /// После входа и при возврате в приложение: перечитать встречи (не чаще
  /// [_bookingsTtl], если не [force]) и обновить виджет.
  Future<void> refresh({bool force = false}) async {
    if (!_supported || !AuthService.instance.isAuthenticated) return;
    final loadedAt = _meetingsLoadedAt;
    if (force ||
        loadedAt == null ||
        DateTime.now().difference(loadedAt) > _bookingsTtl) {
      await _loadMeetings();
    }
    _scheduleSync();
  }

  /// Выход из аккаунта: виджет показывает «Войдите», чужие встречи не
  /// остаются на экране.
  Future<void> clear() async {
    if (!_supported) return;
    _debounce?.cancel();
    _meetings = const [];
    _meetingsLoadedAt = null;
    await _write(jsonEncode({'loggedIn': false, ..._zeroCounters}));
  }

  static const _zeroCounters = {
    'chatsUnread': 0,
    'mailUnread': 0,
    'documentsPending': 0,
    'meetings': <Object>[],
  };

  Future<void> _loadMeetings() async {
    try {
      final user = await AuthService.instance.getStoredUser();
      final userId = int.tryParse(user?['id']?.toString() ?? '');
      if (userId == null) return;
      final now = DateTime.now();
      final items = await BookingsRepository.instance.getBookingsByUserForRange(
        userId: userId,
        datetimeStartSeconds: now.millisecondsSinceEpoch ~/ 1000,
        datetimeEndSeconds:
            now.add(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000,
      );
      _meetings =
          (items.where((b) => b.datetimeEnd.isAfter(now)).toList()
                ..sort((a, b) => a.datetimeStart.compareTo(b.datetimeStart)))
              .take(_maxMeetings)
              .toList(growable: false);
      _meetingsLoadedAt = now;
    } catch (e) {
      // Нет сети — оставляем прошлые встречи, виджет сам уберёт прошедшие.
      AppLogger.d('Widget meetings load failed: $e', name: 'widget');
    }
  }

  void _scheduleSync() {
    if (!AuthService.instance.isAuthenticated) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), () {
      if (!AuthService.instance.isAuthenticated) return;
      unawaited(_write(jsonEncode(_snapshot())));
    });
  }

  Map<String, Object?> _snapshot() {
    final chatsUnread = ChatService.instance.chats.fold<int>(
      0,
      (sum, c) => sum + c.unreadCount,
    );
    return {
      'loggedIn': true,
      'chatsUnread': chatsUnread,
      'mailUnread': MailUnreadService.instance.unreadCount,
      'documentsPending': DocumentPendingService.instance.totalCount,
      'meetings': [
        for (final b in _meetings)
          {
            'title': b.theme.trim().isEmpty ? 'Встреча' : b.theme.trim(),
            'start': b.datetimeStart.millisecondsSinceEpoch,
            'end': b.datetimeEnd.millisecondsSinceEpoch,
            'place': b.objectName,
          },
      ],
    };
  }

  Future<void> _write(String json) async {
    if (json == _lastJson) return;
    _lastJson = json;
    try {
      await _channel.invokeMethod<void>('setToday', json);
    } catch (e) {
      AppLogger.d('Widget update failed: $e', name: 'widget');
    }
  }
}
