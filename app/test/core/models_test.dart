import 'package:droplet/core/api/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GameDetail parses manifest', () {
    final json = {
      'id': 7,
      'title': 'Hollow Knight',
      'system_code': 'switch',
      'system_name': 'Switch',
      'has_cover': true,
      'total_size': 6,
      'files': [
        {
          'id': 1,
          'name': 'hk.nsp',
          'relative_path': 'switch/hk.nsp',
          'role': 'base',
          'disc_number': null,
          'version': '',
          'size': 1,
        },
        {
          'id': 2,
          'name': 'upd.nsp',
          'relative_path': 'switch/upd.nsp',
          'role': 'update',
          'disc_number': null,
          'version': 'v196608',
          'size': 2,
        },
      ],
    };
    final game = GameDetail.fromJson(json);
    expect(game.files[1].role, FileRole.update);
    expect(game.files[1].version, 'v196608');
  });

  test('unknown role maps to other', () {
    final f = GameFileModel.fromJson({
      'id': 1,
      'name': 'x',
      'relative_path': 'x',
      'role': 'weird',
      'disc_number': null,
      'version': '',
      'size': 0,
    });
    expect(f.role, FileRole.other);
  });

  test('GamePage reads pagination', () {
    final page = GamePage.fromJson({'count': 1, 'next': null, 'results': []});
    expect(page.hasNext, false);
  });

  test('SystemModel parses the systems endpoint', () {
    final s = SystemModel.fromJson({
      'id': 3,
      'code': 'psx',
      'name': 'PlayStation',
      'game_count': 12,
      'sort_order': 1,
    });
    expect(s.code, 'psx');
    expect(s.gameCount, 12);
  });

  test('GamePage parses summaries and next page', () {
    final page = GamePage.fromJson({
      'count': 1,
      'next': 'http://nas:8000/api/games/?page=2',
      'results': [
        {
          'id': 4,
          'title': 'Tekken',
          'system_code': 'psx',
          'has_cover': false,
          'total_size': 1000,
        },
      ],
    });
    expect(page.hasNext, true);
    expect(page.results.single.title, 'Tekken');
    expect(page.results.single.hasCover, false);
  });
}
