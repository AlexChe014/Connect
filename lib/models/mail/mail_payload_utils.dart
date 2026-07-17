/// Различает объекты подключения и письма в ответах API.
class MailPayloadUtils {
  MailPayloadUtils._();

  static bool isConnection(Map<String, dynamic> json) {
    if (json.containsKey('imap_host') || json.containsKey('smtp_host')) {
      return true;
    }
    final hasMailboxIdentity =
        json.containsKey('service') &&
        json.containsKey('email') &&
        json.containsKey('username');
    final hasMessageIdentity =
        json.containsKey('subject') ||
        json.containsKey('from') ||
        json.containsKey('sender') ||
        json.containsKey('text_body') ||
        json.containsKey('html_body') ||
        json.containsKey('body_html') ||
        json.containsKey('html') ||
        json.containsKey('text') ||
        json.containsKey('uid') && json.containsKey('subject');
    return hasMailboxIdentity && !hasMessageIdentity;
  }

  static bool isMessage(Map<String, dynamic> json) {
    if (isConnection(json)) return false;
    return json.containsKey('subject') ||
        json.containsKey('from') ||
        json.containsKey('sender') ||
        json.containsKey('text_body') ||
        json.containsKey('html_body') ||
        json.containsKey('body_html') ||
        json.containsKey('html') ||
        json.containsKey('text') ||
        json.containsKey('uid') ||
        json.containsKey('message_id') ||
        json.containsKey('msgno');
  }
}
