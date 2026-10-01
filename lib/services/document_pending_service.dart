import 'package:flutter/foundation.dart';

import '../models/documents/document_service.dart';
import '../repositories/documents_repository.dart';

/// The 1C list is the user's work queue; older responses omit status.
bool documentNeedsAction(Map<String, dynamic> document) {
  final status = (document['status'] ?? document['Status'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  return !const {
    'approved',
    'accepted',
    'signed',
    'rejected',
    'completed',
    'cancelled',
    'canceled',
    'согласован',
    'согласовано',
    'подписан',
    'подписано',
    'отклонен',
    'отклонён',
    'отклонено',
    'завершен',
    'завершён',
    'отменен',
    'отменён',
  }.contains(status);
}

class DocumentPendingService extends ChangeNotifier {
  DocumentPendingService({
    Future<List<Map<String, dynamic>>> Function(int)? load,
    DateTime Function()? now,
  }) : _load = load ?? DocumentsRepository.instance.getAllDocuments,
       _now = now ?? DateTime.now;
  static final instance = DocumentPendingService();
  final Future<List<Map<String, dynamic>>> Function(int) _load;
  final DateTime Function() _now;

  /// Backend keeps signing access for 20 minutes after the e-mail code is
  /// verified; without it, listing a signing service e-mails a new code, so
  /// background badge refreshes must not touch it.
  static const _signingAccessTtl = Duration(minutes: 19);
  DateTime? _signingAccessUntil;

  void markSigningAccessGranted() {
    _signingAccessUntil = _now().add(_signingAccessTtl);
  }

  bool _canLoad(DocumentService service) {
    if (!service.isSigningService) return true;
    final until = _signingAccessUntil;
    return until != null && _now().isBefore(until);
  }

  final Map<int, int> counts = {};
  final Set<int> errors = {};
  final Set<int> loading = {};
  int _generation = 0;
  List<DocumentService> _services = [];

  Future<void> refreshKnownServices() => refresh(_services);

  Future<void> refresh(List<DocumentService> services) async {
    _services = List.of(services);
    final generation = ++_generation;
    final ids = services.where(_canLoad).map((s) => s.id).toSet();
    counts.removeWhere((id, _) => !ids.contains(id));
    errors.removeWhere((id) => !ids.contains(id));
    loading
      ..clear()
      ..addAll(ids);
    notifyListeners();
    // Sequential requests avoid flooding independent 1C services.
    for (final id in ids) {
      try {
        final documents = await _load(id);
        if (generation != _generation) return;
        counts[id] = documents.where(documentNeedsAction).length;
        errors.remove(id);
      } catch (_) {
        if (generation != _generation) return;
        errors.add(id);
      }
      loading.remove(id);
      notifyListeners();
    }
  }

  void reset() {
    _services = [];
    _signingAccessUntil = null;
    _generation++;
    counts.clear();
    errors.clear();
    loading.clear();
    notifyListeners();
  }
}
