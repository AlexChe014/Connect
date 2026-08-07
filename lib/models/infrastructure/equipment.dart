class Equipment {
  final int id;
  final String name;
  final bool isActive;

  const Equipment({
    required this.id,
    required this.name,
    required this.isActive,
  });

  factory Equipment.fromJson(Map<String, dynamic> json) {
    final isActiveRaw = json['is_active'];
    return Equipment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Оборудование #${(json['id'] as num?)?.toInt() ?? 0}',
      isActive: isActiveRaw == true || isActiveRaw == 1 || isActiveRaw == '1',
    );
  }
}

