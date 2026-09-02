import 'dart:collection';

import '../models/disk/disk_entry.dart';
import '../repositories/disk_repository.dart';

class DiskSearchHit {
  const DiskSearchHit({
    required this.name,
    required this.path,
    required this.isFolder,
    this.size,
    this.mime,
  });

  final String name;
  final String path;
  final bool isFolder;
  final int? size;
  final String? mime;

  /// Путь родительской папки — туда открывается [DiskScreen] по тапу на файл.
  String get parentPath {
    final idx = path.lastIndexOf('/');
    return idx <= 0 ? '' : path.substring(0, idx);
  }
}

class DiskSearchOutcome {
  const DiskSearchOutcome({required this.hits, required this.truncated});

  final List<DiskSearchHit> hits;

  /// true, если обход остановлен по лимиту папок/времени, а не потому что
  /// дерево кончилось — то есть по запросу могут быть ещё совпадения.
  final bool truncated;
}

/// Поиск по «Диску» (`/nextcloud/*`) — обходит дерево папок в ширину и
/// сравнивает имена файлов/папок с запросом.
///
/// У бэкенда нет собственного поискового эндпоинта для Nextcloud-хранилища
/// (в отличие от почты и сотрудников), поэтому это best-effort обход с
/// ограничением на число посещённых папок и время — чтобы не «утопить»
/// большое хранилище лавиной последовательных запросов и не морозить экран.
class DiskSearchService {
  DiskSearchService._();
  static final DiskSearchService instance = DiskSearchService._();

  Future<DiskSearchOutcome> search(
    String query, {
    required bool Function() isCancelled,
    int maxFolders = 40,
    int maxResults = 25,
    Duration timeBudget = const Duration(seconds: 8),
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const DiskSearchOutcome(hits: [], truncated: false);

    final stopwatch = Stopwatch()..start();
    final hits = <DiskSearchHit>[];
    final queue = Queue<String>()..add('');
    var visitedFolders = 0;

    while (queue.isNotEmpty && hits.length < maxResults) {
      if (isCancelled()) {
        return DiskSearchOutcome(hits: hits, truncated: true);
      }
      if (visitedFolders >= maxFolders || stopwatch.elapsed >= timeBudget) {
        return DiskSearchOutcome(hits: hits, truncated: true);
      }

      final folder = queue.removeFirst();
      visitedFolders++;

      DiskListing listing;
      try {
        listing = await DiskRepository.instance.listFolder(folder);
      } catch (_) {
        continue;
      }
      if (isCancelled()) {
        return DiskSearchOutcome(hits: hits, truncated: true);
      }

      for (final f in listing.folders) {
        if (f.name.toLowerCase().contains(q)) {
          hits.add(DiskSearchHit(name: f.name, path: f.path, isFolder: true));
          if (hits.length >= maxResults) break;
        }
        queue.add(f.path);
      }

      if (hits.length >= maxResults) break;

      for (final file in listing.files) {
        if (file.name.toLowerCase().contains(q)) {
          hits.add(
            DiskSearchHit(
              name: file.name,
              path: file.path,
              isFolder: false,
              size: file.size,
              mime: file.mime,
            ),
          );
          if (hits.length >= maxResults) break;
        }
      }
    }

    final truncated = queue.isNotEmpty && hits.length >= maxResults;
    return DiskSearchOutcome(hits: hits, truncated: truncated);
  }
}
