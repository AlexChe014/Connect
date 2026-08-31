/// Запись шаринга из `shares/get` / результата `shares/public` и `shares/user`.
class DiskShare {
  final int id;
  final int shareType;
  final String path;
  final String? url;
  final String? displaynameOwner;
  final int? permissions;
  final String? expiration;
  final String? note;

  const DiskShare({
    required this.id,
    required this.shareType,
    required this.path,
    this.url,
    this.displaynameOwner,
    this.permissions,
    this.expiration,
    this.note,
  });

  /// `share_type == 3` — публичная ссылка, `0` — конкретный сотрудник.
  bool get isPublicLink => shareType == 3;

  factory DiskShare.fromJson(Map<String, dynamic> json) {
    return DiskShare(
      id: _parseInt(json['id']) ?? 0,
      shareType: _parseInt(json['share_type']) ?? 0,
      path: (json['path'] ?? '').toString(),
      url: json['url']?.toString(),
      displaynameOwner: json['displayname_owner']?.toString(),
      permissions: _parseInt(json['permissions']),
      expiration: json['expiration']?.toString(),
      note: json['note']?.toString(),
    );
  }
}

int? _parseInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
