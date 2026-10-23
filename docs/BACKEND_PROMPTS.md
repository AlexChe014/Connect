# Промты для бэкенда (`laravel-core-dev`)

Готовые задания для ИИ-агента или разработчика бэкенда. Каждый блок
самодостаточен: его можно вставить целиком в новую сессию в репозитории
`laravel-core-dev`. Подробности и история находок — в
[BACKEND_MAIL_FIXES.md](BACKEND_MAIL_FIXES.md).

Порядок по важности: 1 → 2 → 3 → 4 → 5.

---

## 1. ВКС: «Конференция завершена» для встречи из календаря

```text
Репозиторий laravel-core-dev, модуль Коннектора (ConnectorService, ChatCallService).

Проблема: мобильное приложение входит во встречу через GET /connector/join/{room}.
ConnectorService::join() проверяет connector__calls.status и при 'ended' отвечает
403 «Конференция завершена». Для запланированных встреч (есть бронь Booking)
статус ставит в 'ended' вебхук Jitsi occupant-left через ChatCallService::endByRoom(),
когда кто-то зашёл раньше и вышел. Встреча по календарю ещё впереди, комната в
Jitsi живая, портал (Node, /api/backend/conversation/createJWT) пускает, а
приложение — нет.

Сделай:
1. ConnectorService::join(): если звонок закрыт, но к нему привязана бронь и
   now() <= booking.datetime_end + 2 часа (вынеси запас в конфиг,
   connector.booking_grace_minutes = 120), не отказывай, а переоткрой звонок:
   status = ConnectorCall::STATUS_ACTIVE, ended_at = null, duration = null, save().
   Если брони нет (звонок 1:1 из чата) или запас истёк — оставь 403 как сейчас.
   Ранний вход до начала брони не ограничивай.
2. ConnectorService::show() (GET /connector/{room}): поле can_join считать по
   тому же правилу, иначе метаданные отдают can_join: false.
3. ChatCallService::endByRoom(): не закрывать вебхуком звонки, к которым
   привязана бронь (сделай bookingFor() публичным или добавь hasBooking()).
   Встреча с бронью завершается по времени, а не по выходу участника.
4. Тесты (Feature): бронь в будущем + статус ended → join отдаёт JWT и статус
   становится active; бронь закончилась > 2 ч назад → 403; звонок без брони и
   ended → 403; occupant-left для комнаты с бронью не меняет статус.

Контракт ответа join/show не меняй — приложение уже его разбирает. Приложение с
версии после 1.0.9 при 403 предлагает открыть встречу через портал, но это обход:
войти в Jitsi внутри приложения можно только после этой правки.
```

---

## 2. Почта: несколько получателей в `to` и копия

```text
Репозиторий laravel-core-dev, модуль MailServices (SmtpController, SmtpService,
SendEmailRequest, ReplyEmailRequest, ForwardEmailRequest).

Мобильное приложение шлёт в POST /mail/smtp/send (multipart/form-data):
  to          — строка, список адресов RFC 5322 через запятую:
                "a@x.ru, Иван Иванов <b@y.ru>"
  subject, body_text
  cc[0], cc[1]…, bcc[0]…  — массивы голых адресов
  attachments[]           — файлы

Сначала проверь и напиши в ответе, какое сейчас правило валидации у `to` в
SendEmailRequest. У ForwardEmailRequest это 'required|email' — то есть один
адрес; если у send так же, письмо нескольким людям сейчас отклоняется с 422.

Сделай во всех трёх запросах (send, reply, forward):
1. `to` принимает строку со списком адресов ИЛИ массив строк. В prepareForValidation
   разбери строку на адреса (учти формат «Имя <email>» и запятые внутри кавычек),
   нормализуй в массив и валидируй каждый: 'to' => 'required|array|min:1',
   'to.*' => 'email'.
2. `cc` и `bcc` — 'nullable|array', 'cc.*'/'bcc.*' => 'email'.
3. В SmtpService передавай всех адресатов в Mail::to(), cc в ->cc(), bcc в ->bcc()
   одним письмом (не N отдельных).
4. POST /mail/smtp/send принимает необязательный connection_id и шлёт именно с
   этого ящика (проверка, что ящик принадлежит пользователю и can_send).
   Сейчас приложение перед отправкой переключает ящик по умолчанию через
   /mail/smtp/set и потом возвращает обратно — это гонка между устройствами.
5. Feature-тесты: два адресата в строке, массив адресатов, «Имя <a@x>», cc/bcc,
   невалидный адрес в списке → 422 с понятным сообщением.

Ответ при успехе оставь как сейчас: {success: true, data: true}.
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

Сделай:
1. Брать to/subject из запроса (to — список, см. задачу про получателей), с
   фолбэком на from/'Re: subject' исходного письма, если поле пустое.
2. Принимать cc/bcc массивами.
3. Отправлять с ящика исходного письма ($email->connection), а не с ящика по
   умолчанию. Ставить In-Reply-To и References из message_id исходного.
4. Принимать multipart/form-data с файлами attachments[] (как smtp/send), JSON
   без файлов тоже должен работать. Сейчас правило 'attachments.*.filename'
   (для base64-вложений) ломает multipart-файлы под тем же ключом — разведи
   ключи (например, base64 → 'inline_attachments') или проверяй тип элемента.
5. Текст ответа — поле body_text; цитату исходного письма клиент кладёт в текст
   сам, сервер её не добавляет.
6. При ошибке отправки отдавать sendError (success: false) с текстом, а не
   sendResponse(false). В контроллерах SMTP ловить \Throwable, а не \Exception.

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
