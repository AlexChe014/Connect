# Бэкенд: личные 1:1 звонки (обновление требований)

Клиент обновлён: личный звонок **без сообщения в чат**, без плашки «Войти»,
как обычный телефонный/Telegram-звонок (CallKit / full-screen).

## Что уже ожидает клиент

| Endpoint | Назначение |
|----------|------------|
| `POST /devices/voip` | PushKit-токен iOS |
| `POST /chat/{chatId}/call/ring` | Создать `call_id`, VoIP/FCM push callee |
| `POST /chat/call/{callId}/accept` | Callee принял → push `chat_call_accepted` caller |
| `POST /chat/call/{callId}/decline` | Отклонил / timeout → push `chat_call_ended` |
| `POST /chat/call/{callId}/end` | Любая сторона завершила → push `chat_call_ended` обеим |

### Push payloads (все `data`-поля — строки)

**Входящий звонок** `type=chat_call` — iOS VoIP / Android FCM data-only high priority:
`call_id`, `chat_id`, `room`, `caller_name`, `caller_avatar?`, `topic?`, `is_video`

**Принят** `type=chat_call_accepted`: `call_id`, `chat_id?`, `room?`

**Завершён** `type=chat_call_ended`: `call_id`, `status` = `declined` | `missed` | `ended` | `cancelled`

---

## Что нужно доработать на бэкенде

### 1. Приватная комната только для двоих (обязательно)

Клиент при ring шлёт в `POST /connector/instant`:
```json
{
  "topic": "Звонок с …",
  "users": [<peerUserId>],
  "is_private": true,
  "chat_id": 123
}
```

Нужно:
- Создавать комнату **только для участников личного чата** (`caller` + `callee`).
- `GET /connector/join/{room}` — **403**, если Bearer-пользователь не в списке участников звонка.
- Публичная ссылка `/connector/{room}` **не должна** пускать посторонних (даже зная UUID). Либо не отдавать `public_url` для 1:1, либо `can_join=false` для чужих.
- JWT: `moderator` только участникам; без guest-доступа.

### 2. Не слать сообщение в чат при ring

Клиент **больше не** пишет invite-текст в личный чат. Ring = только системный push.  
Не дублировать на сервере авто-сообщение «Вас пригласили…» при `call/ring`.

### 3. Немедленное завершение при decline / miss / leave

При `decline` / timeout ring / `end`:
- Статус звонка → финальный.
- Push `chat_call_ended` **обеим** сторонам (или оставшейся).
- Комната: закрыть / `can_join=false` / отозвать JWT, чтобы нельзя было «дозайти» по старому room.
- **Не** оставлять звонок «активным» для UI плашки (клиент плашку для 1:1 не показывает).

### 4. Синхронный hang-up

Когда один участник выходит из Jitsi, клиент вызывает `POST .../end`.  
Сервер должен:
- Пометить звонок `ended`
- Отправить `chat_call_ended` второму участнику (чтобы тот тоже закрыл Jitsi / CallKit)
- Запретить повторный join в эту комнату

Опционально (надёжнее): webhook Jitsi `occupant-left` / `room-destroyed` → тот же `end`.

### 5. Заблокированный экран

Уже в контракте, критично соблюдать:
- **iOS**: только APNs **VoIP** (PushKit), не alert FCM
- **Android**: FCM **data-only**, `priority: high`, без блока `notification`

Без этого CallKit/full-screen на lock screen не заработают.

### 6. Accept push caller'у

После `POST .../accept` обязательно push caller'у `chat_call_accepted`, иначе исходящий экран ждёт 25 с и отменяет звонок.

---

## Чеклист

- [ ] `is_private` + ACL на `join` по участникам чата/звонка
- [ ] Нет авто-сообщения в чат на ring
- [ ] `accept` → `chat_call_accepted` caller
- [ ] `decline` / `end` / miss → `chat_call_ended` + закрытие комнаты
- [ ] VoIP iOS + FCM data-only Android
- [ ] (Опц.) Jitsi webhook на leave → end
