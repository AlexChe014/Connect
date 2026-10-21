import 'package:connect/models/disk/disk_entry.dart';
import 'package:connect/repositories/disk_repository.dart';
import 'package:connect/utils/file_size_format.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _folder(String path, String name) => {
  'path': path,
  'name': name,
};

void main() {
  group('DiskListing.fromJson', () {
    DiskListing parse(List<Map<String, dynamic>> folders, String folder) =>
        DiskListing.fromJson(
          {'folders': folders, 'files': <Object>[]},
          folder: DiskRepository.toApiPath(folder),
          normalize: DiskRepository.toApiPath,
        );

    test('убирает саму запрошенную папку по пути, где бы она ни стояла', () {
      final listing = parse([
        _folder('/remote.php/dav/files/user_1/Docs/A/', 'A'),
        _folder('/remote.php/dav/files/user_1/Docs/', 'Docs'),
        _folder('/remote.php/dav/files/user_1/Docs/B/', 'B'),
      ], 'Docs');
      expect(listing.folders.map((f) => f.name), ['A', 'B']);
    });

    test('корень: папка пользователя с пустым путём не попадает в список', () {
      final listing = parse([
        _folder('/remote.php/dav/files/user_1/', 'user_1'),
        _folder('/remote.php/dav/files/user_1/Docs/', 'Docs'),
      ], '');
      expect(listing.folders.map((f) => f.name), ['Docs']);
    });

    test('пути не совпали — по-старому пропускает первую папку', () {
      final listing = parse([
        _folder('weird-self', 'self'),
        _folder('weird-child', 'child'),
      ], 'Docs');
      expect(listing.folders.map((f) => f.name), ['child']);
    });
  });

  test('formatFileSize — десятичная запятая и ГБ', () {
    expect(formatFileSize(840), '840 Б');
    expect(formatFileSize(1536), '1,5 КБ');
    expect(formatFileSize(3 * 1024 * 1024), '3,0 МБ');
    expect(formatFileSize(1288490189), '1,2 ГБ');
  });
}
