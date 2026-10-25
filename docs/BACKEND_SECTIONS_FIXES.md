# Бэкенд: профиль, брони, уведомления, согласование, бонусы

Готовые задания для ИИ-агента или разработчика бэкенда (`laravel-core-dev`).
Каждый блок самодостаточен: его можно целиком вставить в новую сессию в
репозитории бэкенда. Почта и чаты — в [BACKEND_PROMPTS.md](BACKEND_PROMPTS.md)
и [BACKEND_CHAT_FIXES.md](BACKEND_CHAT_FIXES.md).

Сверено с копией `laravel-core-dev` от сентября 2026 (папка
`~/Documents/laravel-core-dev`). Перед правкой проверьте, что код на проде
совпадает.

Порядок: 1 → 2 → 3 → 4 → 5 (безопасность и потеря данных), дальше по
желанию.

---

## 1. Любой сотрудник может изменить чужой профиль

```text
Репозиторий laravel-core-dev: app/Http/Controllers/Api/User/UserController.php
(update), app/Http/Requests/User/UpdateRequest.php, app/Services/UserService.php
(update).

Проблема: POST /api/user/update/{user} не проверяет, кто меняет профиль.
UpdateRequest::authorize() возвращает true, UserService::update() проверяет
права только для birthday, work_start_date и roles. Любой авторизованный
пользователь может отправить запрос с чужим id и поменять e-mail, телефон,
аватар, work_status, theme и is_active (то есть отключить коллегу). У
пользователей из LDAP закрыты только ФИО/должность/отдел/компания, is_active и
email — нет.

Сделай:
1. В UserService::update() (или в UpdateRequest::authorize()) разреши запрос,
   только если Auth::id() === $user->id или у текущего пользователя есть право
   на управление пользователями (isAdmin() / роль Manager — как в delete() и
   updateUserRoles()). Иначе — 403 через sendError(..., [], 403).
2. Поле is_active меняет только администратор, даже в собственном профиле.
3. POST /api/user/activity/{user} проверь так же.
4. Feature-тесты: свой профиль — 200; чужой профиль обычным пользователем —
   403 и данные не изменились; администратор — 200.
```

## 2. Чужую бронь можно изменить; при переносе не проверяется занятость

```text
Репозиторий laravel-core-dev: app/Services/BookingService.php (update,
applyBookingDataToModel, updateRecurringBooking),
app/Http/Requests/Booking/UpdateRequest.php.

Проблема А (безопасность): у POST /api/booking/update/{booking} нет проверки
прав. delete() пускает только user_id/owner_id, а update() — любого: участник
или посторонний может перенести встречу, сменить тему или выкинуть участников.

Проблема Б: при смене datetime_start/datetime_end не вызывается
checkObjectAvailability(), который есть в create(). Перенос брони переговорной
или рабочего места даёт двойное бронирование.

Сделай:
1. В update() в самом начале — та же проверка, что в delete():
   Auth::id() === $booking->user_id || Auth::id() === $booking->owner_id,
   иначе Exception('Недостаточно прав для изменения записи') → 403.
2. Если меняется время и объект не CustomObject, проверь доступность объекта
   на новый интервал, исключив из проверки саму бронь (и при update_all — все
   будущие брони её серии). Занято — 422 «Объект уже забронирован на выбранное
   время».
3. Feature-тесты: участник не может изменить бронь (403); перенос переговорной
   на занятое время — 422; перенос в пределах своего же старого интервала — ок.

Мобильное приложение уже прячет «Изменить» и «Удалить» от не-организаторов и
разрешает перенос времени только встречам без объекта (model_type 6). После
правки 2 перенос можно открыть и для переговорных — сообщите разработчику
приложения.
```

## 3. Чужие уведомления можно прочитать-отметить и удалить

```text
Репозиторий laravel-core-dev: app/Http/Controllers/Api/User/UserNotificationController.php.

Проблема: POST /api/user/notifications/read/{notification} и
POST /api/user/notifications/delete/{notification} получают модель через
route-model binding и не сверяют $notification->user_id с Auth::id(). Перебором
id можно удалить или пометить прочитанными уведомления других сотрудников.

Сделай:
1. В read() и delete(): если $notification->user_id !== Auth::id() — 404
   (лучше 404, а не 403, чтобы не подтверждать существование id).
2. Заодно unread(): сейчас он выгружает все непрочитанные целиком только ради
   count. Мобильное приложение дёргает его на каждый пуш и при возврате в
   приложение. Отдавай count через ->count() отдельным запросом, а список —
   только если он реально нужен порталу (например, ?with_items=1) и с limit.
3. Feature-тесты на чужое уведомление: read и delete отвечают 404, запись не
   изменилась.
```

## 4. Публичные маршруты без авторизации

```text
Репозиторий laravel-core-dev: app/Modules/DocumentsSigning/Routes/api.php,
routes/api.php.

Проблемы:
1. POST /api/documents/notifications (вебхук от 1С) не требует ни токена, ни
   подписи. Кто угодно может разослать сотрудникам пуши «документ на
   согласование» с произвольным номером. Ответ 404 «не обнаружено ни одного
   пользователя с такими guid» к тому же позволяет перебирать guid.
2. GET /api/test/mail открыт всем и при каждом вызове отправляет письмо
   пользователю с id 8.
3. POST /api/auth/user/{id} ведёт на AuthController::authenticate, которого в
   контроллере нет (500 на любой вызов).

Сделай:
1. Вебхук 1С защити так же, как Jitsi-вебхук (VerifyJitsiWebhookToken): общий
   секрет в заголовке, значение — в конфиге/ENV на каждый documents_service.
   Если 1С не умеет заголовки — ограничь по IP на nginx и опиши это в README.
   Ответ на неизвестные guid сделай одинаковым с успехом (200, data: false).
2. Маршрут test/mail удали или оставь только при APP_ENV=local.
3. Маршрут auth/user/{id} удали, если он не используется.
```

## 5. «Удалить всю серию» удаляет и прошедшие встречи

```text
Репозиторий laravel-core-dev: app/Services/BookingService.php, метод delete().

Проблема: запрос
  Booking::where('parent_booking_id', X)->orWhere('id', Y)
         ->whereDate('datetime_start', '>', now)->delete()
даёт SQL parent_booking_id = X OR (id = Y AND date > now). Фильтр «только
будущие» применяется лишь ко второму условию, поэтому удаляются все дочерние
брони серии, включая прошедшие, — пропадает история встреч. Кроме того,
whereDate('>', now) пропускает сегодняшние встречи, а если удаляют дочернюю
бронь, родитель (id = parent_booking_id) в выборку не попадает.

Сделай:
1. Сгруппируй условия:
   ->where(fn ($q) => $q->where('parent_booking_id', $parentId)->orWhere('id', $parentId))
   ->where('datetime_start', '>=', $booking->datetime_start)
   где $parentId = $booking->parent_booking_id ?: $booking->id. Удаляем
   текущую и все последующие, прошедшие не трогаем (так же устроен
   futureSeriesBookings() для update_all).
2. Уведомление BookingCanceled сейчас получает только организатор (то есть
   сам удаляющий). Отправляй его участникам.
3. Feature-тест: серия из 5 встреч, 2 в прошлом; удаление 3-й с delete_all=1
   оставляет 2 прошедшие.
```

## 6. Время броней без часового пояса

```text
Репозиторий laravel-core-dev: app/Models/Booking.php, app/Http/Resources/BookingResource.php.

Проблема: у Booking нет casts для datetime_start/datetime_end, и BookingResource
отдаёт строку из БД вида "2026-10-23 10:00:00" без пояса (это московское время,
APP_TIMEZONE=Europe/Moscow). Клиенты в другом часовом поясе показывают встречу
со сдвигом.

Мобильное приложение с 2026-10-24 считает такие строки московскими, так что
срочности нет. Но правильно отдавать время с поясом.

Сделай: добавь в Booking
  protected $casts = ['datetime_start' => 'datetime', 'datetime_end' => 'datetime'];
и в BookingResource отдавай ->toIso8601String() (например
"2026-10-23T10:00:00+03:00"). Проверь портал (frontend-dev): он должен понимать
ISO-строку. Приложение принимает оба формата.
```

## 7. Массовое согласование обрывается на первой ошибке

```text
Репозиторий laravel-core-dev: app/Modules/DocumentsSigning/Services/DocumentsBaseService.php
(massAcceptDecision, acceptDecision, checkResponse).

Проблема: massAcceptDecision() вызывает acceptDecision() в цикле, а
checkResponse() бросает исключение на первой ошибке 1С (опция throw => false
влияет только на лог). Документы до ошибочного уже подписаны, но клиент
получает общую ошибку и не знает, какие прошли.

Сделай: в massAcceptDecision() оборачивай каждый документ в try/catch и
возвращай массив [{guid, success: true|false, error?: string}], а
success:false на верхнем уровне — только если не прошёл ни один. Сейчас
приложение после ошибки просто перечитывает список; с новым ответом сможет
показать «подписано 3 из 5».

Номера документов приложение теперь шлёт как numbers[<guid>]=<номер>: код уже
ищет $documentNumbers[$guid] первым, менять ничего не нужно.
```

## 8. Сотрудник не видит статус своих заявок в бонусной программе

```text
Репозиторий laravel-core-dev: app/Modules/BonusProgram (RewardRequestController,
RewardRequestService, Routes/api.php).

Проблема: GET /api/bonus-program/reward-requests доступен только модераторам
(authorizeModerate). Сотрудник отправил заявку на товар из магазина или приз
рулетки и дальше не видит, одобрена она, отклонена или ждёт.

Сделай: GET /api/bonus-program/reward-requests/my — заявки текущего
пользователя с пагинацией (тот же RewardRequestResource: товар/приз, статус,
комментарий модератора, даты). Без проверки прав модератора, строго
where user_id = Auth::id().
```

## 9. Поиск по новостям

```text
Репозиторий laravel-core-dev: app/Http/Controllers/Api/Dashboard/NewsController.php
(getAll), сервис новостей.

Проблема: GET /api/dashboard/news/all не принимает строку поиска. Глобальный
поиск в приложении ищет по людям, чатам, встречам, почте и диску, а по
новостям не может.

Сделай: необязательный параметр q — поиск like по заголовку и тексту (без
HTML-тегов, если текст хранится в HTML), с учётом тех же прав видимости и
publish_at, что и в обычной ленте. Пагинация как сейчас (per_page).
```

## 10. Передумать после ответа на приглашение нельзя

```text
Репозиторий laravel-core-dev: app/Services/BookingService.php (changeInvitationStatus).

Проблема: статус участника меняется только из pending. Принявший приглашение
не может потом отказаться (и наоборот): POST /booking/decline отвечает
data:false.

Сделай (по согласованию с продуктом): разрешить смену accepted ↔ rejected до
начала встречи. После этого приложение покажет «Не пойду» и для уже принятых
приглашений — сообщите разработчику приложения.
```

## 11. Повторные «Новые документы на согласование» и проверка решения в 1С

```text
Репозиторий laravel-core-dev: app/Modules/DocumentsSigning
(Console/Commands/SaveDocumentsNotifications.php, Services/DocumentsBaseService.php).

Жалоба: директор согласовал документы, через какое-то время ему снова
приходит, что документы пришли на согласование.

1) Баг в SaveDocumentsNotifications::processNotificationInfo(): переменная
$result объявляется внутри if и не сбрасывается между итерациями. В PHP она
живёт до конца метода, поэтому после первого совпадения каждый следующий
пользователь/тип без совпадений снова добавляет в $notifiableUsers ПРЕДЫДУЩИЙ
результат — тот же человек получает «Есть новые документы на согласование»
по несколько раз за один запуск команды.
Сделай: в начале тела внутреннего foreach ($objectNumbers as $type => $numbers)
поставь $result = null; (или добавляй в $notifiableUsers прямо внутри if).
Заодно убери дубли: один пользователь + сервис + тип = одно уведомление.

2) Проверь, что 1С действительно принимает решение. checkResponse() считает
ошибкой только ответ с status + errorText; любой другой ответ approve/sign
(например {"result": false} или текст) уходит клиенту как успех — документ
пропадает из списка, а позже 1С возвращает задачу. В acceptDecision() залогируй
сырой ответ 1С ($response->body()) вместе с guidtask/guidlist и номером
документа. По логу канала DocumentsSigning для директора сверь:
- пришёл ли запрос «Согласование документа» с этим номером;
- что ответила 1С;
- приходил ли потом /documents/notifications (processNotifications) с тем же
  номером и guid директора — то есть 1С сама вернула документ (повторный
  круг маршрута, изменение документа после согласования и т. п.). Это уже
  вопрос к настройке процесса в 1С, не к бэкенду.

3) getDecisionBody(): для сервисов id 2 и 3 уходит guidlist/guid, для
остальных guidtask/guiduser — убедись, что у сервиса директора ключи совпадают
с тем, что ждёт его база 1С (иначе 1С может отвечать «ок», ничего не делая).
```
