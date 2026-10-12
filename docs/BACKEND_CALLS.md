# Бэкенд: статусы и завершение 1:1 звонков (мобильное приложение + веб)

Правки к текущей реализации (состояние кода на 2026-10-12, см.
`CALLS_CURRENT_IMPLEMENTATION.md`). Мобильное приложение и веб (через Node)
работают с одним бэкендом, поэтому **источник правды о состоянии звонка —
только Laravel**. Клиенты сообщают о действиях, сервер атомарно меняет статус
и рассылает событие всем участникам на всех устройствах.

Групповые звонки (ссылка на встречу в чате + плашка) не затрагиваются.

Файлы, о которых идёт речь:

| Что | Где |
|---|---|
| Логика звонков | `app/Modules/Chats/Services/ChatCallService.php` |
| Контроллеры | `ChatCallController`, `InternalCallController`, `ConnectorWebhookController` |
| Роуты | `app/Modules/Chats/Routes/api.php`, `routes/api.php` (вебхук Jitsi) |
| Таймаут дозвона | `ExpireRingingChatCallJob` |
| Рассылка | `app/Modules/Devices/Services/PushNotificationService.php`, `NodeCallNotifier.php`, `FcmHttpV1Client::buildMessage` |
| Комната | `app/Models/Connector/ConnectorCall.php`, `app/Services/ConnectorService.php` |
| Устройства | `device_tokens`, `voip_device_tokens`, `DeviceSessionService` |

---

## 1. Проблемы текущей реализации

| # | Как сейчас | Чем плохо |
|---|---|---|
| 1 | Состояние только в кэше, при финализации запись **удаляется** | Нельзя отличить «звонок завершён» от «звонка не было»; `GET` статуса нечем отвечать; при сбросе кэша идущие звонки теряются |
| 2 | Переходы `Cache::get → проверка → Cache::put` без блокировок | Одновременные `accept` с телефона и из веба оба проходят, `decline`, пришедший «вдогонку», может завершить звонок |
| 3 | `decline` завершает звонок в **любом** нефинальном статусе, в т.ч. `accepted` | Отказ, отправленный телефоном после ответа в вебе, сбрасывает уже идущий разговор (клиент от этого теперь защищён, но правило должно быть на сервере) |
| 4 | `accept/decline/end` всегда отвечают `200` с пустым `data` | Клиент не узнаёт, что принять звонок уже нельзя, и идёт в закрытую комнату |
| 5 | `accepted` уходит только звонящему, `ended` — только FCM | Остальные устройства и веб собеседника звонят до таймаута; убитое iOS-приложение FCM не будит — CallKit звонит до 35 с |
| 6 | Таймаут дозвона 90 с, и job не ставится при `queue.default = sync` | Клиенты ждут 32–35 с — у принимающего звонит после того, как звонящий сдался; на sync-очереди дозвон не истекает вовсе |
| 7 | Нет «занято», нет обработки встречного вызова | Второй вызов во время разговора показывается поверх видео; два встречных вызова — оба «висят» |
| 8 | `endByRoom` завершает звонок на **первый** `occupant-left` | Кратковременный реконнект Jitsi (смена сети Wi-Fi → LTE) убивает звонок и закрывает комнату |
| 9 | Node-вебхук вызывается **синхронно** в запросе (таймаут 5 с) | При медленном Node `accept` отвечает до 5 с — пользователь ждёт после нажатия «Принять» |
| 10 | Логаут удаляет токены, но не завершает активный звонок | Собеседник остаётся в комнате один (клиент теперь сам завершает звонок перед логаутом, но если сессию отозвали на сервере — нет) |

---

## 2. Хранение: таблица `chat__calls`

Сделать источником правды таблицу БД в модуле Chats, кэш оставить
необязательным. `connector__calls` не трогать: она общая для всех встреч и
отвечает за доступ в комнату.

```
chat__calls
  id                 uuid  PK            -- call_id (тот же, что сейчас Str::uuid())
  chat_id            fk
  room               string index        -- = connector__calls.room_id
  caller_id          fk users
  callee_id          fk users
  is_video           bool
  status             enum(ringing, accepted, declined, cancelled, missed, busy, ended, failed)
  end_reason         string null         -- reason из запроса или системная причина
  source             enum(app, web)      -- откуда позвонили
  caller_session_id  string null         -- см. раздел 6
  answered_session_id string null
  ringing_ack_at, accepted_at, ended_at  timestamp null
  ended_by           fk users null
  created_at, updated_at
  index (callee_id, status), index (caller_id, status)
```

- Статус `calling` из прошлой версии документа не нужен: звонок создаётся сразу
  в `ringing`, как и сейчас. Факт «вызов показан на устройстве» — поле
  `ringing_ack_at` (раздел 3.3).
- Финальные статусы **остаются в таблице**: по ним отвечают `GET`,
  повторные действия и история звонков.
- Ключ кэша `chat_call_room:{room}` заменяется индексом по `room`.

### Атомарность

Каждый переход — в транзакции с блокировкой строки:

```php
DB::transaction(function () use ($callId, $from, $to) {
    $call = ChatCall::whereKey($callId)->lockForUpdate()->first();
    if (! $call) throw new CallNotFound();            // → 410
    if (! in_array($call->status, $from)) {
        throw new CallStateConflict($call);           // → 409 + CallResource
    }
    $call->update([...]);
});
// рассылка — ПОСЛЕ коммита (DB::afterCommit / событие)
```

### Связь статуса с комнатой (`closeCall`)

| Статус `chat__calls` | `closeCall(room, …)` |
|---|---|
| `ended`, `failed` после `accepted` | `ended` |
| `declined`, `cancelled`, `missed`, `busy`, `failed` до ответа | `cancelled` |

`closeCall` вызывать в `finalize()` и только для приватной комнаты
(`isPrivateCall()`), как сейчас.

---

## 3. API

Все ответы — в принятом формате `{ success, data }`. Объект звонка
(`CallResource`):

```json
{
  "call_id": "6f1c…", "chat_id": "42", "room": "abc-def",
  "status": "ringing", "end_reason": null,
  "caller_id": 1, "callee_id": 2, "is_video": true,
  "ring_timeout": 30, "server_time": "2026-10-12T10:00:00Z"
}
```

Коды ошибок для действий над звонком:

| Код | Когда | Что делает клиент |
|---|---|---|
| `409` + `CallResource` | Звонок есть, но в другом статусе (уже принят, завершён) | Не входит в комнату, гасит звонок, показывает причину |
| `410` | `call_id` не найден | Считает звонок завершённым |
| `403` | Пользователь не caller/callee или действие не его роли | — |
| `404` | **Только** «маршрута нет» | Клиент перестаёт вызывать этот эндпоинт до перезапуска (совместимость со старыми бэками) |

Важно: **не отвечать 404 на несуществующий звонок** — клиент примет это за
отсутствие эндпоинта и отключит опрос статуса.

Мобильный клиент во всех запросах шлёт JSON-тело
`{ device_id, platform, reason? }`. `device_id` можно использовать для логов;
устройство на сервере определяется по Sanctum-токену (раздел 6).

### 3.1. `POST /chat/{chat}/call/ring` и `POST /internal/chat/call/ring` — доработать

Порядок в `ring()` / `ringFromSite()` после `resolvePersonalCallee`:

1. **Встречный вызов (glare).** Если есть звонок `ringing`, где
   `caller = callee текущего` и `callee = текущий пользователь`, то:
   - новую комнату закрыть (`closeCall(newRoom, cancelled)` — она уже
     создана приложением через connector API или Node);
   - существующий звонок перевести в `accepted` (как `accept` от текущего
     пользователя);
   - вернуть его `CallResource` со `status: "accepted"` и **его** `room`.

   Клиент сразу войдёт в комнату существующего звонка.
2. **Занят.** Если у callee есть звонок в `ringing|accepted` (с кем угодно),
   то: создать запись со `status = busy`, `closeCall(room, cancelled)`,
   пушей не слать, вернуть `CallResource` со `status: "busy"` (код `200` или
   `409` — клиент понимает оба).
3. Если у **звонящего** уже есть звонок в `accepted` — `409`.
4. Иначе — как сейчас: `restrictToChatParticipants`, запись `ringing`,
   job таймаута, рассылка вызова. Ответ — `CallResource`
   (поля `call_id, room, chat_id` сохраняются, добавляется `status`).

`is_video` брать из тела (приложение шлёт `true`, Node — свой `is_video`),
а не хардкодить `'1'`.

### 3.2. `GET /chat/call/{callId}` — новый (+ `GET /internal/chat/call/{callId}?user_id=`)

Вернуть `CallResource`. Доступ — только caller/callee. Приложение опрашивает
раз в 3 с на экране «Звоним…» и при возврате приложения из фона (если
CallKit ещё звонит) — страховка на случай потерянного пуша.

### 3.3. `POST /chat/call/{callId}/ringing` — новый

Устройство собеседника показало входящий звонок.

- Если `ringing` и `ringing_ack_at is null` — проставить и разослать
  звонящему `status=ringing` (у него «Вызов…» сменится на «Идут гудки…»).
- **Всегда** возвращать актуальный `CallResource` с кодом `200`, в том числе
  финальный: так телефон, получивший запоздавший VoIP-пуш, сразу узнаёт об
  отмене и гасит CallKit.
- Для веба: Node вызывает `/internal/chat/call/{id}/ringing` `{user_id}`, когда
  вкладка показала вызов. Это необязательно: для «Идут гудки…» достаточно
  одного устройства.

### 3.4. `accept` (оба роута) — доработать

Только callee.

| Текущий статус | Результат |
|---|---|
| `ringing` | `accepted`, `answered_session_id` = текущий Sanctum-токен (или `web:{device_id}` из тела Node), `200` + `CallResource` |
| `accepted` тем же устройством | `200` (идемпотентно), **без повторной рассылки** |
| `accepted` другим устройством | `409` + `CallResource` |
| финальный | `409` + `CallResource` |
| нет записи | `410` |

Рассылка — раздел 4. Job таймаута после ответа больше ничего не делает,
так как статус уже не `ringing`.

### 3.5. `decline` (оба роута) — доработать

Тело: `reason` ∈ `declined` (по умолчанию) | `busy` | `timeout` | `failed`.
Только callee, **только из `ringing`**, иначе `409` без побочных эффектов.

| `reason` | Статус |
|---|---|
| `busy` | `busy` |
| `timeout` | `missed` |
| остальное | `declined` |

### 3.6. `end` (оба роута) — доработать

Тело: `reason` ∈ `cancelled` | `timeout` | `hangup` | `failed`.

| Статус | Кто | Новый статус |
|---|---|---|
| `ringing` | caller, `reason=timeout` | `missed` |
| `ringing` | caller | `cancelled` |
| `ringing` | callee | как `decline` (как сейчас) |
| `accepted` | любой, `reason=failed` | `failed` |
| `accepted` | любой | `ended` |
| финальный | — | `409`, без эффектов |

### 3.7. `POST /chat/call/{callId}/heartbeat` — по желанию

Разговор и так завершает вебхук Prosody (раздел 5.2), поэтому heartbeat
необязателен. Самый дешёвый вариант — алиас `GET`: вернуть `CallResource`.
Приложение шлёт heartbeat каждые 15 с во время разговора и выходит из комнаты,
если статус финальный. Если маршрута нет (404), приложение перестаёт его
вызывать.

---

## 4. Рассылка

Каналов три: **VoIP APNs** (iOS), **FCM** (Android, а также iOS в foreground) и
**Node-вебхук** (веб). Reverb для звонков вводить не нужно: веб получает события
через Node. Приложение понимает и Reverb-события `call.*` на канале
`user.{id}`, если они когда-нибудь появятся, но это необязательно.

Всю рассылку (пуши и Node-вебхук) вынести **из запроса в очередь**
(`dispatch(...)->afterCommit()`), чтобы `accept`/`end` отвечали сразу. При
`queue.default = sync` использовать хотя бы `dispatchAfterResponse`.

### 4.1. Кому что

«Устройство-инициатор» — то, с которого пришёл запрос (Sanctum-токен или
веб-вкладка), раздел 6.

| Событие | Звонящий: все устройства + веб | Принимающий: инициатор | Принимающий: остальные устройства + веб |
|---|---|---|---|
| вызов (`ring`) | — | — | VoIP (iOS), FCM `chat_call` (Android), Node `ring` |
| `ringing` | FCM `chat_call_status`, Node `status` | — | — |
| `accepted` | FCM `chat_call_accepted`, Node `accepted` | ничего | **новое:** `answered_elsewhere` — VoIP на iOS, FCM на Android, Node `status` |
| `declined` / `busy` | FCM `chat_call_ended`, Node `ended` | ничего | **новое:** `declined_elsewhere` — VoIP на iOS, FCM на Android, Node `status` |
| `cancelled` / `missed` | FCM `chat_call_ended`, кроме устройства-инициатора | — | `chat_call_ended`: **VoIP на iOS** + FCM на Android + Node `ended` |
| `ended` / `failed` | FCM `chat_call_ended`, Node `ended` | FCM `chat_call_ended`, Node `ended` | FCM `chat_call_ended`, Node `ended` |

Клиент идемпотентен: дубли и событие на устройство-инициатор безопасны.
Исключать инициатора нужно в первую очередь из-за VoIP (лимиты iOS) и
`answered_elsewhere` (иначе принявшее устройство само себя «погасит» — клиент
от этого защищён, но лучше не слать).

### 4.2. FCM

`FcmHttpV1Client::buildMessage`: добавить `android.ttl` — `30s` для вызова
(протухший вызов не должен звонить), `60s` для статусов. Только data, все
значения — строки.

```json
{ "type": "chat_call",          "call_id": "…", "chat_id": "42", "room": "…", "caller_name": "…", "is_video": "1" }
{ "type": "chat_call_ended",    "call_id": "…", "chat_id": "42", "status": "missed", "by_user_id": "1" }
{ "type": "chat_call_accepted", "call_id": "…", "chat_id": "42", "room": "…" }
{ "type": "chat_call_status",   "call_id": "…", "chat_id": "42", "status": "ringing" }
{ "type": "chat_call_status",   "call_id": "…", "chat_id": "42", "status": "answered_elsewhere" }
{ "type": "chat_call_status",   "call_id": "…", "chat_id": "42", "status": "declined_elsewhere" }
```

Существующие `chat_call_ended` и `chat_call_accepted` не менять — клиент
понимает старый и новый формат. В `chat_call_ended` добавить `chat_id` и
`by_user_id`.

Отдельно: `notifyChatCallAccepted` сейчас шлёт FCM на **все** токены
звонящего. Это не мешает (клиент на чужом устройстве ничего не гасит), но
iOS-токены звонящего можно не включать, если устройство не в foreground.

### 4.3. VoIP APNs (iOS)

- Вызов — без изменений (`apns-expiration` +30 с, priority 10).
- **Новое:** `cancelled`, `missed`, `answered_elsewhere`, `declined_elsewhere`
  слать VoIP-пушем на iOS-устройства callee, **которым ушёл вызов**, кроме
  инициатора:

  ```json
  { "type": "chat_call_ended",  "call_id": "…", "status": "cancelled" }
  { "type": "chat_call_status", "call_id": "…", "status": "answered_elsewhere" }
  ```

  Приложение (уже доработано) на такой пуш гасит звонящий CallKit, а
  требование iOS 13+ «на каждый VoIP-пуш сообщить о звонке» выполняет
  «пустым» звонком, который сразу завершается.
- Не слать VoIP-статусы после того, как звонок принят **на этом** устройстве,
  и не слать для `ended`/`failed` — разговор завершается FCM, вебхуком Prosody
  и Jitsi. Лишние VoIP-пуши расходуют лимит iOS: при частых нарушениях система
  перестаёт доставлять VoIP приложению.

### 4.4. Node-вебхук (`NodeCallNotifier`)

Оставить `ring | accepted | ended`, расширить payload и добавить событие
`status`:

```
POST {node}/api/v1/calls/webhook/ring      { call_id, chat_id, room, caller_user_id, callee_user_id, is_video, ring_timeout }
POST {node}/api/v1/calls/webhook/accepted  { call_id, chat_id, room, caller_user_id, callee_user_id, answered_by: "app" | "web", answered_device_id? }
POST {node}/api/v1/calls/webhook/ended     { call_id, chat_id, user_ids, status, end_reason, by_user_id, by: "app" | "web", device_id? }
POST {node}/api/v1/calls/webhook/status    { call_id, chat_id, user_ids, status: "ringing" | "answered_elsewhere" | "declined_elsewhere", by: "app" | "web", device_id? }
```

Что должен сделать Node:

- На `accepted` с `answered_by=app` — закрыть вызов во **всех** вкладках
  callee. На `answered_by=web` — во всех, кроме `answered_device_id`.
- На `ended` — закрыть вызов, экран «Звоним…» и комнату во всех вкладках обоих
  пользователей, показать причину по `status`.
- В `/internal/chat/call/*` передавать `device_id` вкладки (UUID в
  `localStorage`) и `reason` — по ним сервер определит инициатора и статус.

---

## 5. Таймеры и завершение разговора

### 5.1. Таймаут дозвона

- `ring_timeout` уменьшить с 90 до **30 с**. Таймеры приложения (32 с у
  звонящего, 35 с у CallKit) нарочно длиннее — они только страховка.
- `ExpireRingingChatCallJob`: `ringing → missed` через `finalize`.
- Так как job не ставится при `queue.default = sync`, добавить
  `SweepStaleChatCalls` в планировщик (каждую минуту, или `everyThirtySeconds`):
  `ringing` старше `ring_timeout + 10 с` → `missed`. Плюс «ленивая» проверка:
  любой `GET`/действие над звонком в `ringing` старше таймаута сначала
  переводит его в `missed`.

### 5.2. Вебхук Prosody (`endByRoom`) — оставить основным механизмом

Это надёжнее heartbeat: сервер узнаёт о выходе сам. Нужно исправить:

1. **Задержка на реконнект.** На `occupant-left` не завершать сразу, а
   поставить `CheckRoomOccupantsJob` через 15 с. Если участник вернулся
   (нужен ещё `muc-occupant-joined` — добавить в модуль Prosody) или в комнате
   по-прежнему двое — ничего не делать.
2. **Действовать только в `accepted`.** В `ringing` комната пустая (приложение
   входит только после ответа). Если веб-клиент звонящего входит в комнату
   сразу, то его `occupant-left` в `ringing` — это `cancelled`.
3. Игнорировать служебных участников (`focus`, `jibri`, `jigasi`,
   `recorder`).
4. `room-destroyed` — завершать сразу (`ended`).
5. Если после `accepted` за 60 с в комнату вошло меньше двух участников —
   `failed` (принял, но приложение упало / нет сети). Без
   `muc-occupant-joined` это делает приложение: watchdog на 40 с, затем `end`
   с `reason=failed`.

### 5.3. Логаут и отзыв сессии

В `DeviceSessionService` при удалении Sanctum-токена: если у пользователя
есть звонок `accepted` с `answered_session_id`/`caller_session_id` этой сессии
— `finalize(ended)`. Если звонок `ringing` и пользователь его callee — ничего
(звонок продолжит звонить на других устройствах).

---

## 6. Устройства: Sanctum-сессия вместо `device_id`

Новая колонка `device_id` не нужна. «Устройство» на бэке уже есть —
`personal_access_token_id`: к нему привязаны и FCM-, и VoIP-токены, и через
него работает логаут.

- Инициатор запроса из приложения:
  `$request->user()->currentAccessToken()->id`.
- «Все устройства пользователя, кроме X»: добавить в репозитории токенов
  выборки `tokensForUserExceptSession($userId, $sessionId)` (FCM, с
  разбивкой по `platform`) и `voipTokensForUserExceptSession(...)`.
- «Устройства, которым ушёл вызов»: при `ring` запомнить список
  `personal_access_token_id` получателей VoIP (поле `json` в `chat__calls` или
  отдельная таблица) — по нему слать VoIP-статусы из 4.3.
- Веб-вкладки — на стороне Node: в `chat__calls.answered_session_id` писать
  `web:{device_id}`.
- `device_id`, который приложение шлёт в `/devices/fcm`, `/devices/voip` и
  действиях со звонками, можно сохранять в логах или игнорировать — правила
  валидации не должны его отклонять.

---

## 7. Прочее

1. **История звонков в чате.** При финализации создавать системное сообщение
   (`type: call`, `call_id`, `status`, `duration` из `connector__calls`) — его
   увидят оба участника везде, включая веб. Сейчас «Начат звонок / Звонок
   завершён · мм:сс» — локальные сообщения только на одном телефоне; после
   внедрения их можно убрать из приложения.
2. **Пропущенный звонок.** При `missed`/`cancelled` слать callee обычный
   (не VoIP) пуш «Пропущенный звонок от …».
3. **Логи.** Каждое изменение статуса — с `user_id`, сессией/`device_id`,
   `platform`, `end_reason`, источником (`app`/`web`/`prosody`/`timeout`).

---

## 8. Совместимость и порядок выката

Приложение уже собрано под этот контракт и работает со старым бэком:

| Сейчас на бэке | Как ведёт себя приложение |
|---|---|
| Нет `GET`/`ringing`/`heartbeat` (404) | После первого 404 больше их не вызывает; вместо «Идут гудки…» остаётся «Вызов…» |
| `accept/decline/end` — `200` с пустым `data` | `accept` считается успешным; если комната уже закрыта — вход не удаётся, звонок завершается с `reason=failed` |
| `ring` без `status` | Обычный дозвон |
| `chat_call_ended` без `chat_id`/`by_user_id` | Работает |
| Лишние поля в теле (`device_id`, `platform`, `reason`) | Игнорируются бэком |

Рекомендуемый порядок:

1. Таблица `chat__calls`, атомарные переходы, `409/410`, `decline` только из
   `ringing` — закрывает самый опасный сценарий (сброс принятого звонка).
2. Рассылка `answered_elsewhere` / `declined_elsewhere` с исключением
   инициатора (FCM + Node), рассылка из очереди.
3. `ring_timeout = 30`, sweeper, `reason` в `end`/`decline`.
4. VoIP-статусы для iOS.
5. `busy` и встречный вызов (с закрытием лишней комнаты).
6. `GET` и `ringing` (+ internal), задержка в `endByRoom`.
7. Node: новые поля и событие `status`.
8. История звонков, пропущенные.

---

## 9. Сценарии для проверки

A звонит, у B: телефон iOS (B1), телефон Android (B2), веб (Bw).

| # | Сценарий | Ожидается |
|---|---|---|
| 1 | A звонит, B1 принимает | B2 и Bw перестают звонить; A входит в комнату |
| 2 | A звонит, Bw принимает | B1/B2 перестают звонить, `decline` не уходит; A входит |
| 3 | A звонит, B2 отклоняет | B1/Bw перестают звонить; A видит «Звонок отклонён» |
| 4 | A отменяет до ответа | у B1 (приложение убито) CallKit гаснет сразу; у Bw пропадает вызов |
| 5 | Никто не отвечает | через 30 с `missed`; у A «Нет ответа», у всех B звонок гаснет; работает и при `queue=sync` |
| 6 | B разговаривает с C, A звонит B | A видит «Абонент занят», у B ничего не звонит, комната A закрыта |
| 7 | A и B одновременно звонят друг другу | оба попадают в одну комнату, лишняя комната закрыта |
| 8 | Разговор, у A пропала сеть на 5 с | звонок продолжается (задержка в `endByRoom`) |
| 9 | Разговор, приложение A убито | через ≤15–20 с B выходит из комнаты |
| 10 | B1 принял, но не вошёл в комнату | через ≤40–60 с `failed` у обоих |
| 11 | Разговор, A завершает в вебе | телефон B выходит из комнаты |
| 12 | B1 и Bw нажали «Принять» одновременно | одно устройство входит, второе получает 409 и гасит вызов |
| 13 | VoIP-вызов пришёл после отмены | B1 не показывает звонок (`ringing` вернул финальный статус) |
| 14 | A вышел из аккаунта во время разговора | звонок завершается у B |
| 15 | `accept` на завершённый звонок | `409`, приложение не входит в комнату |
