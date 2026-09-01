import 'package:dio/dio.dart';
import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/core/api/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://nas:8000'));
    adapter = DioAdapter(dio: dio);
  });

  test('login returns token', () async {
    adapter.onPost(
      '/api/auth/token/',
      (s) => s.reply(200, {'token': 'abc'}),
      data: Matchers.any,
    );
    final client = ApiClient(baseUrl: 'http://nas:8000', dio: dio);
    expect(await client.login('jan', 'x'), 'abc');
  });

  test('fetchGames sends token and parses page', () async {
    adapter.onGet(
      '/api/games/',
      (s) => s.reply(200, {
        'count': 1,
        'next': null,
        'results': [
          {
            'id': 1,
            'title': 'Mario',
            'system_code': 'snes',
            'has_cover': true,
            'total_size': 5,
          },
        ],
      }),
      queryParameters: {'page': 1, 'system': 'snes'},
      headers: {'Authorization': 'Token abc'},
    );
    final client = ApiClient(baseUrl: 'http://nas:8000', token: 'abc', dio: dio);
    final page = await client.fetchGames(system: 'snes');
    expect(page.results.single.title, 'Mario');
  });

  test('401 throws UnauthorizedException', () async {
    adapter.onGet('/api/systems/', (s) => s.reply(401, {'detail': 'no'}));
    final client = ApiClient(baseUrl: 'http://nas:8000', token: 'zly', dio: dio);
    expect(client.fetchSystems(), throwsA(isA<UnauthorizedException>()));
  });

  test('coverUrl builds absolute url', () {
    final client = ApiClient(baseUrl: 'http://nas:8000', token: 'abc');
    expect(client.coverUrl(7), 'http://nas:8000/api/games/7/cover?size=thumb');
  });

  test('fetchSystems parses the list', () async {
    adapter.onGet(
      '/api/systems/',
      (s) => s.reply(200, [
        {'id': 1, 'code': 'snes', 'name': 'SNES', 'game_count': 2},
      ]),
    );
    final client = ApiClient(baseUrl: 'http://nas:8000', token: 'abc', dio: dio);
    final systems = await client.fetchSystems();
    expect(systems.single.code, 'snes');
  });

  test('fetchGame parses the manifest', () async {
    adapter.onGet(
      '/api/games/7/',
      (s) => s.reply(200, {
        'id': 7,
        'title': 'Hollow Knight',
        'system_code': 'switch',
        'system_name': 'Switch',
        'has_cover': false,
        'total_size': 3,
        'files': [
          {
            'id': 1,
            'name': 'hk.nsp',
            'relative_path': 'switch/hk.nsp',
            'role': 'base',
            'disc_number': null,
            'version': '',
            'size': 3,
          },
        ],
      }),
    );
    final client = ApiClient(baseUrl: 'http://nas:8000', token: 'abc', dio: dio);
    final game = await client.fetchGame(7);
    expect(game.systemName, 'Switch');
    expect(game.files.single.role, FileRole.base);
  });

  test('401 on games and detail throws UnauthorizedException', () async {
    adapter
      ..onGet('/api/games/', (s) => s.reply(401, {'detail': 'no'}),
          queryParameters: {'page': 1})
      ..onGet('/api/games/7/', (s) => s.reply(401, {'detail': 'no'}));
    final client = ApiClient(baseUrl: 'http://nas:8000', token: 'zly', dio: dio);
    expect(client.fetchGames(), throwsA(isA<UnauthorizedException>()));
    expect(client.fetchGame(7), throwsA(isA<UnauthorizedException>()));
  });

  test('server errors other than 401 are rethrown', () async {
    adapter.onGet('/api/systems/', (s) => s.reply(500, {'detail': 'boom'}));
    final client = ApiClient(baseUrl: 'http://nas:8000', token: 'abc', dio: dio);
    expect(client.fetchSystems(), throwsA(isA<DioException>()));
  });

  test('authHeaders reflect the token', () {
    expect(
      ApiClient(baseUrl: 'http://nas:8000', token: 'abc').authHeaders,
      {'Authorization': 'Token abc'},
    );
    expect(ApiClient(baseUrl: 'http://nas:8000').authHeaders, isEmpty);
  });

  test('fetchGames forwards the search phrase', () async {
    adapter.onGet(
      '/api/games/',
      (s) => s.reply(200, {'count': 0, 'next': null, 'results': []}),
      queryParameters: {'page': 1, 'search': 'mario'},
    );
    final client = ApiClient(baseUrl: 'http://nas:8000', token: 'abc', dio: dio);
    expect((await client.fetchGames(search: 'mario')).count, 0);
  });

  test('an empty search phrase is not sent', () async {
    adapter.onGet(
      '/api/games/',
      (s) => s.reply(200, {'count': 0, 'next': null, 'results': []}),
      queryParameters: {'page': 1},
    );
    final client = ApiClient(baseUrl: 'http://nas:8000', token: 'abc', dio: dio);
    expect((await client.fetchGames(search: '')).count, 0);
  });

  test('triggerScan posts to the scan endpoint', () async {
    adapter.onPost('/api/scan/', (s) => s.reply(202, {'enqueued': true}));
    final client = ApiClient(baseUrl: 'http://nas:8000', token: 'abc', dio: dio);
    await expectLater(client.triggerScan(), completes);
  });

  test('triggerScan maps 401 to UnauthorizedException', () async {
    adapter.onPost('/api/scan/', (s) => s.reply(401, {'detail': 'no'}));
    final client = ApiClient(baseUrl: 'http://nas:8000', token: 'zly', dio: dio);
    expect(client.triggerScan(), throwsA(isA<UnauthorizedException>()));
  });
}
