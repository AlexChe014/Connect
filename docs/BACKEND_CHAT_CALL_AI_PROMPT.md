# Промпт для ИИ (бэкенд): входящие звонки из чатов

Скопируй блок ниже целиком в чат с ИИ, который реализует API Connect.

---

## PROMPT (начало)

Ты реализуешь бэкенд для **входящих видеозвонков из личных чатов** мобильного приложения Connect (Flutter). Клиент уже готов на ветке `feature/chat-callkit`: CallKit (iOS) + ConnectionService/full-screen (Android). JWT для Jitsi и создание комнаты уже работают через `/mobile/api/connector/*`.

### Контекст

- REST API префикс: **`/mobile/api`**
- Авторизация: **Bearer token** (как у остальных mobile routes)
- FCM-токены уже регистрируются: `POST /mobile/api/devices/fcm` с `{ token, platform }`
- Connector (Jitsi) уже есть:
  - `POST /connector/instant` — мгновенная комната
  - `GET /connector/join/{room}` — JWT для входа
  - `GET /connector/{room}` — метаданные (`can_join`)

### Поведение клиента (уже реализовано)

При звонке из **личного чата** Flutter-клиент делает:

1. `POST /connector/instant` с `topic` и `users: [peerUserId]`
2. `POST /chat/{chatId}/messages` — текст-приглашение со ссылкой `/connector/{room}`
3. **`POST /chat/{chatId}/call/ring`** — просит сервер разбудить собеседника системным «входящим звонком»

Для **групповых чатов** ring не вызывается — только сообщение в чат + in-app плашка.

При **Accept** на CallKit клиент сам вызывает `GET /connector/join/{room}` и открывает Jitsi SDK.
При **Decline / timeout** клиент вызывает `POST /chat/call/{callId}/decline`.

---

### Задача: реализовать API и push-доставку

#### 1. `POST /mobile/api/devices/voip`

Регистрация **PushKit VoIP-токена** (только iOS, отдельно от FCM).

**Request body:**
```json
{
  "token": "hex_pushkit_voip_token",
  "platform": "ios"
}
```

**Auth:** Bearer (текущий пользователь = владелец токена).

Храни несколько токенов на пользователя (несколько устройств). При логине/refresh клиент может перерегистрировать токен.

---

#### 2. `POST /mobile/api/chat/{chatId}/call/ring`

Инициация входящего звонка для **личного** чата.

**Request body:**
```json
{
  "room": "ffdc584e-b2f5-4e5d-a0ee-ee6eba4a24f1",
  "topic": "Звонок с Иван Иванов"
}
```

**Логика:**
1. Проверить, что пользователь — участник чата `{chatId}`.
2. Проверить, что чат **не групповой** (ровно 2 участника).
3. Определить **callee** (второй участник, не инициатор).
4. Сгенерировать **`call_id`** = UUID v4 (уникален на каждый звонок).
5. Сохранить состояние звонка (DB или Redis, TTL **60–90 секунд**):
   - `call_id`, `chat_id`, `room`, `caller_user_id`, `callee_user_id`, `status: ringing`, `started_at`, `topic`
6. Отправить push callee (см. payload ниже).
7. **Response 200:**
```json
{
  "success": true,
  "data": {
    "call_id": "550e8400-e29b-41d4-a716-446655440000",
    "room": "ffdc584e-b2f5-4e5d-a0ee-ee6eba4a24f1",
    "chat_id": "123"
  }
}
```

**Ошибки:**
- `403` — не участник / групповой чат
- `409` — у callee уже активный звонок (опционально)
- `404` — чат не найден

Клиент **игнорирует ошибку ring** (звонок всё равно создаётся через чат), но без push CallKit не сработает.

---

#### 3. Push payload `type: chat_call`

Все значения в `data` — **строки** (требование FCM/APNs).

| Поле | Обязательно | Пример |
|------|-------------|--------|
| `type` | да | `"chat_call"` |
| `call_id` | да | UUID (тот же, что в CallKit) |
| `chat_id` | да | `"123"` |
| `room` | да | UUID комнаты Jitsi |
| `caller_name` | да | `"Иван Иванов"` |
| `caller_avatar` | нет | URL аватара инициатора |
| `topic` | нет | `"Звонок с ..."` |
| `is_video` | да | `"1"` или `"0"` |

##### iOS — APNs VoIP (PushKit) — **обязательно для lock screen / killed app**

- Отправляй на **VoIP-токен** из `POST /devices/voip`, не на обычный APNs alert.
- Push type: **`voip`**
- Custom payload с полями из таблицы (клиент читает их в `PKPushPayload.dictionaryPayload`).
- **Не** используй обычный FCM notification для iOS, если нужен CallKit из фона.
- Нужен **VoIP Services Certificate** или **APNs Auth Key** с push type voip для bundle id приложения.

##### Android — FCM **data-only** (без блока `notification`)

```javascript
await admin.messaging().send({
  token: calleeFcmToken,
  data: {
    type: 'chat_call',
    call_id: '550e8400-e29b-41d4-a716-446655440000',
    chat_id: '123',
    room: 'ffdc584e-b2f5-4e5d-a0ee-ee6eba4a24f1',
    caller_name: 'Иван Иванов',
    caller_avatar: 'https://example.com/avatar.jpg',
    topic: 'Звонок',
    is_video: '1',
  },
  android: { priority: 'high' },
});
```

---

#### 4. `POST /mobile/api/chat/call/{callId}/decline`

**Auth:** Bearer (callee).

**Body:** `{}` или пустой.

**Логика:**
- Найти звонок по `call_id`
- Проверить, что текущий пользователь — callee (или участник)
- Установить `status: declined`
- Не слать повторные ring для этого `call_id`
- Опционально: push инициатору `type: chat_call_ended` с `{ call_id, reason: declined }`

---

#### 5. `POST /mobile/api/chat/call/{callId}/end` (рекомендуется)

Вызывается при завершении / отмене / timeout (45 с на клиенте).

**Статусы:** `ended`, `missed`, `cancelled`.

---

#### 6. Групповые чаты (опционально, фаза 2)

Клиент показывает in-app плашку «Войти», определяя активность по сообщению + `GET /connector/{room}`. Для точного UX позже:

```
GET  /mobile/api/chat/{chatId}/call/active
POST /mobile/api/chat/{chatId}/call/start
POST /mobile/api/chat/{chatId}/call/end
```

Ответ `active`: `{ room, participants_count, topic }`.

---

### Формат ответов

Следуй существующему envelope приложения:
```json
{ "success": true, "data": { ... } }
```
Ошибки — как в остальных `/mobile/api/*` routes.

---

### Чеклист готовности

- [ ] Миграция/таблица `device_voip_tokens` (user_id, token, platform, updated_at)
- [ ] Миграция/Redis для активных звонков по `call_id`
- [ ] `POST /devices/voip`
- [ ] `POST /chat/{id}/call/ring` (только direct chat)
- [ ] `POST /chat/call/{callId}/decline`
- [ ] `POST /chat/call/{callId}/end`
- [ ] APNs VoIP sender (отдельно от FCM alert)
- [ ] FCM high-priority data-only для Android
- [ ] Интеграционный тест: ring → push → decline

### Ограничения Apple

После VoIP push приложение **обязано** немедленно показать CallKit UI. Клиент делает это нативно в `AppDelegate.swift`. Если push приходит без валидных полей — звонок не отобразится.

### Не делать

- Не генерировать JWT Jitsi на ring — клиент получает JWT через `GET /connector/join/{room}` после Accept.
- Не слать `chat_call` через FCM **notification** payload на Android — только `data`.
- Не использовать ring для групповых чатов.

Реализуй endpoints, миграции, сервис отправки push и краткую документацию в OpenAPI/swagger проекта.

## PROMPT (конец)
