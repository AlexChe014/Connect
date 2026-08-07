/// Имя и фамилия без отчества — для отображения в чатах.
String userDisplayNameFromJson(Map<String, dynamic> user) {
  return userDisplayName(
    surname: user['surname'] as String?,
    name: user['name'] as String?,
    email: user['email'] as String?,
  );
}

String userDisplayName({
  String? surname,
  String? name,
  String? email,
}) {
  final parts = <String>[
    (surname ?? '').trim(),
    (name ?? '').trim(),
  ].where((p) => p.isNotEmpty);
  final joined = parts.join(' ');
  if (joined.isNotEmpty) return joined;

  final emailValue = email?.trim();
  if (emailValue != null && emailValue.isNotEmpty) return emailValue;
  return 'Пользователь';
}

String userInitials(String displayName) {
  final parts = displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length >= 2) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  return parts[0].length >= 2
      ? parts[0].substring(0, 2).toUpperCase()
      : parts[0].toUpperCase();
}
