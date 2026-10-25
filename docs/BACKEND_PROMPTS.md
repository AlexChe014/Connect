# Промты для бэкенда (`laravel-core-dev`)

Готовые задания для ИИ-агента или разработчика бэкенда. Каждый блок
самодостаточен: его можно вставить целиком в новую сессию в репозитории
`laravel-core-dev`. Подробности и история находок — в
[BACKEND_MAIL_FIXES.md](BACKEND_MAIL_FIXES.md).

Порядок по важности: 1 → 6 (безопасность) → 2 → 3 → 4 → 5.

Сверено с кодом `laravel-core-dev` от 2026-10-23 (архив `laravel-core-dev (4).zip`).

---

## 1. ВКС: «Конференция завершена» для встречи из календаря

```text
Репозиторий laravel-core-dev: app/Services/ConnectorService.php,
app/Modules/Chats/Services/ChatCallService.php.

Проблема: мобильное приложение входит во встречу из календаря через
GET /api/connector/join/{room}. ConnectorService::join() сразу проверяет
callIsOpen($call) (status === active && ended_at === null) и при закрытой комнате
отвечает 403 «Конференция завершена». У пользователя встреча по календарю ещё
впереди, комната в Jitsi живая, портал (Node, createJWT) пускает, приложение — нет.
Значит, строка в connector__calls для этой брони стоит в ended/cancelled.

Важно: в текущем коде Laravel комнаты броней сам не закрывает —
ChatCallService::closeRoom() трогает только приватные звонки (isPrivateCall:
chat_id или max_participants). Таблицу connector__calls по README ведёт ещё и
Next.js. Значит, статус ставит либо Node, либо старая версия Laravel на проде.

Сделай:
1. Диагностика (результат напиши в ответе): найди все места, которые пишут
   status/ended_at в connector__calls — в этом репозитории и, если доступен,
   в frontend-dev (Node). Сверь, совпадает ли код на проде с этим репозиторием
   (closeRoom только для isPrivateCall).
2. ConnectorService::join(): если звонок закрыт, но к нему привязана бронь и
   now() <= booking.datetime_end + запас, не отказывай, а переоткрой звонок:
   status = ConnectorCall::STATUS_ACTIVE, ended_at = null, duration = null, save().
   Запас вынеси в конфиг: connector.booking_grace_minutes, по умолчанию 120.
   Брони нет (звонок 1:1 из чата, мгновенная комната) или запас истёк — оставь 403.
   Ранний вход до начала брони не ограничивай.
3. ConnectorService::show(): can_join считать по тому же правилу (общий метод,
   например callIsJoinable($call)), иначе метаданные отдают can_join: false.
4. bookingFor() ищет бронь по точному совпадению Booking.link с publicUrl(room).
   Если ссылка в брони отличается (http/https, слэш в конце, регистр UUID,
   другой домен) — бронь не находится, и правка 2 не сработает. Сравнивай по
   room: extractRoomFromLink(Booking.link) === room_id (например, where link
   like '%/connector/{room}%' + проверка extractRoomFromLink).
5. Feature-тесты: бронь в будущем + статус ended → join отдаёт JWT, статус
   становится active; бронь закончилась больше запаса назад → 403; звонок с
   chat_id и ended → 403; ссылка в брони с другим регистром/слэшем → бронь
   находится.

Контракт ответов join/show не меняй — приложение их уже разбирает. Приложение
при 403 сейчас предлагает открыть встречу через портал в браузере — это обход,
войти внутри приложения можно только после этой правки.
```

---

## 2. Почта: несколько получателей в `to`

```text
Репозиторий laravel-core-dev, app/Modules/MailServices:
Http/Requests/EmailConnection/{SendEmailRequest,ReplyEmailRequest,ForwardEmailRequest}.php,
Services/SmtpService.php.

Сейчас SendEmailRequest и ForwardEmailRequest валидируют 'to' => 'required|email|max:255',
то есть ровно один адрес. Мобильное приложение собирает в «Кому» несколько
человек и до этой правки шлёт каждому отдельное письмо (получатели не видят друг
друга, в «Отправленных» N копий). SmtpService::normalizeAddresses() массив уже
понимает — мешает только валидация.

Сделай во всех трёх запросах:
1. 'to' принимает строку со списком адресов RFC 5322 ("a@x.ru, Иван <b@y.ru>")
   ИЛИ массив. В prepareForValidation (там уже есть merge attachments_files —
   не сломай его) разбери строку в массив голых адресов, учитывая формат
   «Имя <email>» и запятые внутри кавычек. Правила: 'to' => 'required|array|min:1',
   'to.*' => 'email|max:255'. Одиночная строка "a@x.ru" должна работать как раньше.
2. В SmtpService всех адресатов передавать в один Mail::to() — одно письмо.
3. Feature-тесты на POST /api/mail/smtp/send (по образцу SmtpSendConnectionTest):
   строка с двумя адресами, «Имя <a@x>», массив, один адрес; невалидный адрес
   в списке → 422 с понятным сообщением.
4. SmtpService::sendEmail() объявлен ': bool', но в catch ничего не возвращает —
   при ошибке SMTP это TypeError (не Exception), контроллер его не ловит и
   отдаёт голый 500. Верни false в catch, а в контроллере при false отдавай
   sendError с getLastError()['message'] (сейчас sendResponse(false) = success:true).
   В контроллерах SMTP ловить \Throwable.
5. Проверь тестом multipart: файлы приходят под ключом attachments[], а правила
   'attachments.*.filename|mime|content' рассчитаны на base64-массивы. Убедись,
   что POST smtp/send с UploadedFile::fake() в attachments[] проходит валидацию
   и файл прикладывается; если нет — разведи ключи (base64 → attachments_base64).

Ответ при успехе не меняй: {success: true, data: true}. После выкладки скажи —
уберём в приложении рассылку по одному.
```

---

## 3. Почта: ответ (`/mail/smtp/reply/{email}`)

```text
Репозиторий laravel-core-dev, SmtpController::replyToEmail, ReplyEmailRequest.

Сейчас ответ всегда уходит на $email->from['email'] с темой 'Re: ' . subject,
игнорируя то, что прислал клиент. Из-за этого:
  - «Ответить всем» уходит только отправителю;
  - ответ на своё письмо из «Отправленных» уходит самому себе;
  - правка получателей и темы в приложении ни на что не влияет.

В ReplyEmailRequest вообще нет правил для to/subject — validated() их выкидывает,
а replyToEmail() жёстко ставит 'to' => $email->from['email'].
Уже работает и трогать не надо: ящик исходного письма, cc/bcc, In-Reply-To/References,
приём attachments[] (attachments_files), sendError при неудаче.

Сделай:
1. В ReplyEmailRequest добавить 'to' (список, как в задаче про получателей) и
   'subject' => 'sometimes|string|max:255'. В replyToEmail брать их из запроса
   с фолбэком на $email->from['email'] и 'Re: ' . $email->subject.
2. Ответ на своё письмо: если фолбэк-адрес совпадает с ящиком
   ($email->connection->email), брать получателей из $email->to.
3. Проверить тестом, что multipart attachments[] проходит валидацию (см. задачу 2,
   п. 5) и файлы прикладываются к ответу.
4. Текст ответа — поле body_text; цитату исходного письма клиент кладёт сам.
5. Ловить \Throwable вместо \Exception.

После выкладки скажи — в приложении включим вложения в ответе
(MailRepository.replyAttachmentsSupported = true).
```

---

## 4. Почта: пересылка (`/mail/smtp/forward/{email}`) падает с 500

```text
Репозиторий laravel-core-dev, SmtpController::forwardEmail, SmtpService::buildForwardBody,
buildForwardTextBody, ImapService::getMessage, ForwardEmailRequest.

POST /mail/smtp/forward/{email} отдаёт голый 500 на любом письме:
  1) ImapService::getMessage() возвращает 'date' => $message->getDate()->toString()
     (строка), а контроллер вызывает $originalEmail['date']->format(...);
  2) formatAddress() возвращает массив ['name','email'], а buildForward*Body
     вызывает $from->getName() / $from->getAddress();
  3) это PHP Error, а catch (\Exception) его не ловит.
Плюс IMAP читает через getDefaultConnection() вместо ящика письма, а SMTP-ящик
для пересылки не выставляется — письмо из второго ящика уходит не с того адреса.

Сделай:
1. Дату парсить через Carbon::parse($originalEmail['date']), from читать как
   массив ($from['name'] ?? '', $from['email'] ?? '').
2. Ящик: connection_id из запроса (если передан и принадлежит пользователю),
   иначе $email->connection; выставить его и для IMAP, и для SMTP.
3. to — список адресатов (см. задачу про получателей), cc/bcc — массивы,
   одно письмо всем.
4. Прикладывать вложения исходного письма + новые файлы attachments[] из
   multipart (конфликт с правилом base64 — как в задаче про ответ).
5. Текст пользователя — поле message; цитату исходного письма с HTML добавляет
   сервер.
6. При неудаче — sendError, не sendResponse(false); catch (\Throwable).
7. Feature-тест: пересылка письма с вложением двум адресатам из неосновного ящика.

Пока это не выложено, приложение пересылает через /mail/smtp/send цитатой без
HTML и без вложений исходного. После выкладки переключим клиент обратно на forward.
```

---

## 5. Почта: данные письма и вложений

```text
Репозиторий laravel-core-dev, ImapService::getMessage, EmailResource,
маршрут GET /mail/attachments/{connection}/{email}/{filename}.

Сделай:
1. getMessage(): 'id' => $email->id (сейчас отдаётся IMAP UID — ломает reply,
   forward, вложения), UID отдельным полем 'uid'.
2. getMessage() и EmailResource: отдавать всех получателей to и cc
   (formatAddresses($message->getTo()), а не getTo()[0]).
3. У каждого вложения отдавать id, content_id (Content-ID без <>) и disposition
   (inline/attachment). Без id второе вложение с тем же именем скачать нельзя;
   без content_id встроенные картинки Gmail/Apple Mail не показываются.
4. Добавить маршрут скачивания по id вложения (или ?index=), старый по filename
   оставить для совместимости.
5. /mail/search принимает connection_id.
```

---

## 6. Почта: `connection_id` в отправке и проверка владельца

```text
Репозиторий laravel-core-dev, app/Modules/MailServices:
Http/Controllers/Api/SmtpController.php, Http/Controllers/Api/EmailController.php,
Services/ImapService.php.

1. SmtpController::sendEmail передаёт в SmtpService::sendEmail
   $data['connection_id'] ?? null, но $data в методе не объявлена — значение
   всегда null, письмо уходит с ящика по умолчанию. Объявить
   $data = $request->validated() и передавать $data['connection_id'] ?? null.
   Feature-тест: у пользователя два ящика, отправка с connection_id второго
   (не по умолчанию) уходит с адреса второго.

2. Безопасность. EmailController::massDelete и massMarkAsRead выбирают письма
   по Email::whereIn('id', $request->input('emails')) без проверки владельца и
   без проверки, что {connection} принадлежит пользователю. Сделай:
   - валидация: 'emails' => 'required|array', 'emails.*' => 'integer';
   - ->where('user_id', Auth::id())->where('connection_id', $connection->id);
   - во всех методах EmailController с {connection}: Auth::id() === $connection->user_id,
     иначе 403; в методах с {email} ещё и $email->connection_id === $connection->id.
   Feature-тесты: чужие id писем и чужой connection → 403, IMAP не вызывается.

3. ImapService::deleteMessage/moveMessage/markAsRead/markAsUnread при ошибке
   возвращают false, и контроллер отдаёт {"success": true, "data": false}.
   При false (или исключении) отдавать sendError с причиной. downloadAttachment
   при ошибке — sendError с кодом 404/502, а не 200.

Контракт успешных ответов не меняй — приложение их уже разбирает.
```

