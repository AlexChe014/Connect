/// Размер файла для подписи: «840 Б», «12,4 КБ», «3,1 МБ», «1,2 ГБ» —
/// с десятичной запятой, одинаково в почте, на «Диске» и в поиске.
String formatFileSize(int bytes) {
  String fixed(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes < kb) return '$bytes Б';
  if (bytes < mb) return '${fixed(bytes / kb)} КБ';
  if (bytes < gb) return '${fixed(bytes / mb)} МБ';
  return '${fixed(bytes / gb)} ГБ';
}
