# Спецификация бэкенда: входящие звонки из чатов (CallKit / ConnectionService)

Клиентская ветка: `feature/chat-callkit`

## Обзор

Для **личных чатов** при старте звонка клиент:

1. `POST /connector/instant` — создаёт комнату Jitsi
2. `POST /chat/{chatId}/messages` — отправляет приглашение со ссылкой (как сейчас)
3. `POST /chat/{chatId}/call/ring` — **новый** endpoint: просит сервер разбудить собеседника

Сервер должен отправить push, который на устройстве callee показывает **системный экран входящего звонка** (CallKit на iOS, full-screen intent на Android).

Для **групповых чатов** CallKit не используется — только сообщение в чат + in-app плашка «Войти».

---

## 1. Регистрация VoIP-токена (только iOS)

### `POST /mobile/api/devices/voip`

**Auth:** Bearer

**Body:**
```json
{
  "token": "hex_pushkit_voip_token",
  "platform": "ios"
}
```

**Назначение:** хранить PushKit VoIP-токен отдельно от FCM. Один пользователь может иметь несколько устройств; у каждого iOS-устройства свой VoIP-токен.

**Клиент:** отправляет после логина и при обновлении токена (`IncomingCallService`).

**Apple Developer:** в кабинете нужен **VoIP Services Certificate** или **APNs Auth Key** с поддержкой push type `voip` для bundle id приложения.

---

## 2. Инициация звонка (ring)

### `POST /mobile/api/chat/{chatId}/call/ring`

**Auth:** Bearer (инициатор звонка)

**Body:**
```json
{
  "room": "ffdc584e-b2f5-4e5d-a0ee-ee6eba4a24f1",
  "topic": "Звонок с Иван Иванов"
}
```

**Логика сервера:**

1. Проверить, что `{chatId}` — **личный** чат между инициатором и одним собеседником.
2. Сгенерировать `call_id` (UUID v4) — **уникален для каждого звонка**.
3. Сохранить активный звонок (TTL 60–90 с), например:
   ```json
   {
     "call_id": "...",
     "chat_id": 123,
     "room": "...",
     "caller_user_id": 1,
     "callee_user_id": 2,
     "status": "ringing",
     "started_at": "2026-09-02T12:00:00Z"
   }
   ```
4. Отправить push **callee** (см. раздел 3).
5. Ответ `200`:
   ```json
   {
     "success": true,
     "data": {
       "call_id": "uuid",
       "room": "...",
       "chat_id": "123"
     }
   }
   ```

**Ошибки:**
- `403` — не участник чата / не личный чат
- `409` — у callee уже идёт другой звонок (опционально)

---

## 3. Push payload `chat_call`

### Обязательные поля `data`

| Поле | Тип | Описание |
|------|-----|----------|
| `type` | string | `"chat_call"` |
| `call_id` | string | UUID звонка (id CallKit) |
| `chat_id` | string | id чата |
| `room` | string | UUID комнаты Jitsi |
| `caller_name` | string | Имя инициатора для UI |
| `caller_avatar` | string? | URL аватара |
| `topic` | string? | Тема звонка |
| `is_video` | string | `"1"` видео, `"0"` аудио |

### iOS — APNs VoIP (PushKit)

- **Обязательно** для звонка при **убитом** приложении и на **локскрине**.
- Push type: `voip` (не обычный `alert`).
- **Без** поля `notification` — только `data` / custom payload.
- Payload должен содержать все поля из таблицы (Apple передаёт их в `PKPushPayload.dictionaryPayload`).
- Отправка: APNs HTTP/2 на VoIP-токен устройства callee.

> ⚠️ Apple: после получения VoIP push приложение **обязано** сразу показать CallKit. Клиент делает это в `AppDelegate.pushRegistry(didReceiveIncomingPushWith:)`.

### Android — FCM data message

- **Только `data`**, без блока `notification` (иначе код приложения не выполнится в фоне).
- `"priority": "high"` на уровне FCM.
- Android 14+: пользователь должен разрешить full-screen intent (клиент запрашивает при старте).

Пример (Firebase Admin SDK):
```js
await admin.messaging().send({
  token: calleeFcmToken,
  data: {
    type: 'chat_call',
    call_id: '...',
    chat_id: '123',
    room: '...',
    caller_name: 'Иван Иванов',
    caller_avatar: 'https://...',
    topic: 'Звонок',
    is_video: '1',
  },
  android: {
    priority: 'high',
  },
});
```

---

## 4. Отклонение звонка

### `POST /mobile/api/chat/call/{callId}/decline`

**Auth:** Bearer (callee)

**Body:** пустой или `{}`

**Логика:**
- Пометить звонок `status: declined`
- (Опционально) отправить инициатору push `chat_call_ended` или WebSocket-событие
- Остановить повторные ring-push для этого `call_id`

**Клиент:** вызывает при `Decline` / timeout в CallKit.

---

## 5. Завершение / отмена (рекомендуется)

### `POST /mobile/api/chat/call/{callId}/end`

Вызывает любая сторона, когда:
- инициатор повесил трубку до ответа;
- все вышли из Jitsi;
- истёк TTL ring (45 с на клиенте).

Обновляет статус → `ended` | `missed` | `cancelled`.

---

## 6. Активный звонок в группе (будущее, опционально)

Для плашки «пока кто-то на линии»:

```
GET  /mobile/api/chat/{chatId}/call/active
POST /mobile/api/chat/{chatId}/call/start   (группа)
POST /mobile/api/chat/{chatId}/call/end
```

Ответ `active`:
```json
{
  "room": "...",
  "participants_count": 2,
  "topic": "Видеозвонок в «Команда»"
}
```

Сейчас клиент определяет активность по сообщению + `GET /connector/{room}` (`can_join`).

---

## 7. Чеклист для бэкенда

- [ ] Таблица/Redis: активные звонки по `call_id`
- [ ] `POST /devices/voip` — хранение PushKit-токенов
- [ ] `POST /chat/{id}/call/ring` — ring для личных чатов
- [ ] `POST /chat/call/{callId}/decline`
- [ ] APNs VoIP push (отдельный канал от FCM alert)
- [ ] FCM high-priority **data-only** для Android
- [ ] VoIP certificate / APNs key в Apple Developer + Firebase для Android
- [ ] (Опционально) webhook от Jitsi / polling участников для `participants_count`

---

## 8. Тестирование без полного бэкенда

1. **Foreground:** отправить FCM data `type=chat_call` на Android-эмулятор / iOS-симулятор — CallKit на симуляторе **ограничен**, нужно **реальное iOS-устройство** для VoIP.
2. **iOS VoIP:** только real device + валидный VoIP push с сервера.
3. **Accept:** клиент вызывает `GET /connector/join/{room}` и открывает Jitsi SDK.

---

## 9. Связанные файлы клиента

| Файл | Роль |
|------|------|
| `lib/services/incoming_call_service.dart` | CallKit UI, accept → Jitsi |
| `lib/models/incoming_call_payload.dart` | парсинг push |
| `lib/repositories/chat_call_repository.dart` | `POST .../call/ring` |
| `lib/repositories/device_token_repository.dart` | `POST /devices/voip`, decline |
| `ios/Runner/AppDelegate.swift` | PushKit + native CallKit при VoIP push |
| `lib/services/push_background_handler.dart` | Android background FCM |
