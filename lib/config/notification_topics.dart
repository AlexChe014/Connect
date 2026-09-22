import 'package:flutter/cupertino.dart';

/// Каталог push-категорий приложения, на которые пользователь может
/// подписаться/отписаться в разделе «Уведомления».
///
/// Подписка/отписка реализована через топики Firebase Cloud Messaging
/// (`FirebaseMessaging.subscribeToTopic` / `unsubscribeFromTopic`) —
/// бэкенду не нужно хранить настройки пользователя отдельно, достаточно
/// в момент события отправить push в соответствующий топик [id] через
/// Firebase Admin SDK (`admin.messaging().send({topic: id, ...})`).
///
/// `data.type` — значение поля `type` в `data`-payload push-уведомления,
/// по которому клиент решает, куда перейти при тапе (см.
/// `PushNotificationService._navigateFromData`). Совпадает с тем, как тип
/// уведомления хранится в БД бэкенда (`news_created`, `new_documents`, ...) —
/// бэкенд его не переименовывает. Ожидаемые дополнительные поля `data`
/// перечислены в [NotificationTopic.dataFields]; часть из них бэкенд не
/// дублирует на верхний уровень, поэтому клиент умеет доставать их и из
/// вложенного объекта `data.data` (см. `AppNavigationService.resolveDataField`).
class NotificationTopic {
  const NotificationTopic({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.dataFields,
    required this.icon,
    required this.color,
  });

  /// Имя топика FCM, на который подписывается клиент.
  final String id;

  /// Значение `data.type` в push-payload для этой категории.
  final String type;

  final String title;
  final String description;

  /// Дополнительные поля `data`, которые бэкенд должен положить в push
  /// помимо `type`, чтобы клиент открыл нужный экран по тапу.
  final List<String> dataFields;

  final IconData icon;
  final Color color;
}

abstract final class NotificationTopics {
  NotificationTopics._();

  static const feedPost = NotificationTopic(
    id: 'feed_post',
    type: 'news_created',
    title: 'Новая запись в ленте',
    description: 'Публикации и объявления компании',
    dataFields: ['news_id (push, верхний уровень) / id (лента, во вложенном data)'],
    icon: CupertinoIcons.square_grid_2x2_fill,
    color: CupertinoColors.systemBlue,
  );

  static const documentApproval = NotificationTopic(
    id: 'document_approval',
    type: 'new_documents',
    title: 'Новый документ на согласование',
    description: 'Документы 1С, ожидающие вашего решения',
    dataFields: ['service_id (во вложенном data для push)'],
    icon: CupertinoIcons.doc_text_fill,
    color: CupertinoColors.systemIndigo,
  );

  static const mailNew = NotificationTopic(
    id: 'mail_new',
    type: 'mail',
    title: 'Новое письмо',
    description: 'Входящие в подключённых почтовых ящиках',
    dataFields: ['connection_id', 'message_id (необязательно)'],
    icon: CupertinoIcons.mail_solid,
    color: CupertinoColors.systemGreen,
  );

  static const meetingInvite = NotificationTopic(
    id: 'meeting_invite',
    type: 'booking_created',
    title: 'Приглашение на встречу',
    description: 'Вас добавили участником брони',
    dataFields: ['booking_id (во вложенном data; дублируется как id брони)'],
    icon: CupertinoIcons.calendar_badge_plus,
    color: CupertinoColors.systemOrange,
  );

  static const meetingReminder = NotificationTopic(
    id: 'meeting_reminder',
    type: 'meeting_reminder',
    title: 'Напоминание о встрече',
    description: 'Скоро начнётся забронированная встреча',
    dataFields: ['booking_id'],
    icon: CupertinoIcons.bell_fill,
    color: CupertinoColors.systemPink,
  );

  static const all = <NotificationTopic>[
    feedPost,
    documentApproval,
    mailNew,
    meetingInvite,
    meetingReminder,
  ];

  /// Типы, по тапу на которые открывается карточка брони.
  /// `booking_created` — фактический тип из БД бэкенда;
  /// `meeting_invite` / `meeting_reminder` оставлены как прежние имена клиента.
  static const bookingOpenTypes = <String>{
    'booking_created',
    'meeting_invite',
    'meeting_reminder',
  };

  static bool isBookingType(String? type) =>
      type != null && bookingOpenTypes.contains(type);

  /// Категория по значению `data.type` push/ленты уведомлений — `null`,
  /// если тип не входит в каталог (например `chat_message`).
  static NotificationTopic? byType(String type) {
    if (type == 'meeting_invite' || type == 'booking_created') {
      return meetingInvite;
    }
    for (final topic in all) {
      if (topic.type == type) return topic;
    }
    return null;
  }
}
