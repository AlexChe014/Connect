class DocumentPayloadUtils {
  DocumentPayloadUtils._();

  static String? datalist(Map<String, dynamic> json) {
    for (final key in const ['datalist', 'Datalist', 'dataList', 'DataList']) {
      final value = _stringValue(json[key]);
      if (value != null) return value;
    }
    return null;
  }

  static String? guid(Map<String, dynamic> json) {
    for (final key in const [
      'guidlist',
      'Guidlist',
      'guid',
      'Guid',
      'GUID',
      'document_guid',
      'DocumentGuid',
      'guiddoc',
    ]) {
      final value = _stringValue(json[key]);
      if (value != null) return value;
    }
    return null;
  }

  static String title(Map<String, dynamic> json) {
    final fromList = datalist(json);
    if (fromList != null) return fromList;

    for (final key in const [
      'task',
      'title',
      'Title',
      'name',
      'Name',
      'subject',
      'Subject',
      'description',
      'Description',
      'Наименование',
      'number',
      'Number',
      'Номер',
    ]) {
      final value = _stringValue(json[key]);
      if (value != null) return value;
    }
    final g = guid(json);
    if (g != null) return 'Документ $g';
    return 'Документ';
  }

  static String? subtitle(Map<String, dynamic> json) {
    final parts = <String>[];

    for (final key in const [
      'number',
      'Number',
      'time',
      'date',
      'Date',
      'Дата',
      'created_at',
    ]) {
      final value = _stringValue(json[key]);
      if (value != null) {
        parts.add(value);
        break;
      }
    }

    for (final key in const [
      'author',
      'Author',
      'sum',
      'status',
      'Status',
    ]) {
      final value = _stringValue(json[key]);
      if (value != null) {
        parts.add(value);
        break;
      }
    }

    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  static String? number(Map<String, dynamic> json) {
    for (final key in const ['number', 'Number', 'Номер', 'doc_number']) {
      final value = _stringValue(json[key]);
      if (value != null) return value;
    }
    return null;
  }

  static String labelForAcceptor(Map<String, dynamic> json) {
    for (final key in const [
      'name',
      'Name',
      'title',
      'Title',
      'full_name',
      'FullName',
      'user',
      'User',
      'ФИО',
    ]) {
      final value = _stringValue(json[key]);
      if (value != null) return value;
    }
    return 'Согласующий';
  }

  static String? acceptorStatus(Map<String, dynamic> json) {
    for (final key in const [
      'status',
      'Status',
      'state',
      'State',
      'decision',
      'Decision',
      'Статус',
    ]) {
      final value = _stringValue(json[key]);
      if (value != null) return value;
    }
    return null;
  }

  static String? _stringValue(Object? value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is num || value is bool) return value.toString();
    if (value is Map) {
      for (final key in const ['name', 'title', 'value', 'text', 'datalist']) {
        final nested = _stringValue(value[key]);
        if (nested != null) return nested;
      }
    }
    return null;
  }
}
