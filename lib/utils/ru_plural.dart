/// Русское склонение по числу: 1 участник, 2 участника, 5 участников
/// (и 11–14 — «участников»).
String ruPlural(int n, String one, String few, String many) {
  final mod10 = n.abs() % 10;
  final mod100 = n.abs() % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}
