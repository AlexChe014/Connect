/// Конфигурация для прохождения проверки App Store.
///
/// Укажите здесь email тестового аккаунта модератора Apple Review
/// (тот же, что в App Store Connect → App Review Information).
class AppStoreReviewConfig {
  AppStoreReviewConfig._();

  /// Email-адреса аккаунтов, для которых отключены/всегда успешны
  /// проверки геопозиции и другие ограничения для модерации.
  static const Set<String> reviewAccountEmails = {
    'apple@review.connect',
    'moderator@xondev.ru',
    'review@xondev.ru',
  };

  static bool isReviewAccount(String? email) {
    if (email == null) return false;
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return reviewAccountEmails.contains(normalized);
  }
}
