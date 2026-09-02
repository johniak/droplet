import 'dart:async';

import 'package:dio/dio.dart';
import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/core/format.dart';
import 'package:droplet/core/platform/downloader_port.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/features/game/game_detail_screen.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/library/widgets/cover_image.dart';
import 'package:droplet/app/widgets/pulse_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../fakes/fake_downloader_port.dart';

const _detail = GameDetail(
  id: 7,
  title: 'Hollow Knight',
  systemCode: 'switch',
  systemName: 'Switch',
  hasCover: false,
  totalSize: 3,
  folder: 'Hollow Knight',
  files: [
    GameFileModel(
      id: 1,
      name: 'hk.nsp',
      relativePath: 'switch/hk.nsp',
      role: FileRole.base,
      discNumber: null,
      version: '',
      size: 1,
    ),
    GameFileModel(
      id: 2,
      name: 'upd.nsp',
      relativePath: 'switch/upd.nsp',
      role: FileRole.update,
      discNumber: null,
      version: 'v196608',
      size: 2,
    ),
  ],
);

const _notInstalled = LocalGameState(
  status: InstallStatus.none,
  updateAvailable: false,
  missing: [],
  presentPaths: [],
);

GoRouter _router() => GoRouter(
      initialLocation: '/game/7',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Home')),
          routes: [
            GoRoute(
              path: 'game/:id',
              builder: (_, s) =>
                  GameDetailScreen(gameId: int.parse(s.pathParameters['id']!)),
            ),
          ],
        ),
      ],
    );

Widget _screen(
  GameDetail detail, {
  LocalGameState local = _notInstalled,
  List<Override> overrides = const [],
  FakeDownloaderPort? port,
  Override? detailOverride,
  Override? localOverride,
}) =>
    ProviderScope(
      overrides: [
        detailOverride ?? gameDetailProvider(7).overrideWith((ref) async => detail),
        localOverride ?? localStateProvider(7).overrideWith((ref) async => local),
        downloaderPortProvider.overrideWithValue(port ?? FakeDownloaderPort()),
        storageSettingsProvider.overrideWith(
          (ref) async => StorageSettings('/roms', const {}),
        ),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: _router()),
    );

/// A phone-shaped viewport: the default 800×600 test surface is too short
/// for the hero + file list to fit without scrolling.
Future<void> _phoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  test('formatBytes', () {
    expect(formatBytes(500), '500 B');
    expect(formatBytes(2048), '2.0 KB');
    expect(formatBytes(1500000000), '1.4 GB');
    expect(formatBytes(1023), '1023 B');
    expect(formatBytes(1024), '1.0 KB');
  });

  test('gameDetailProvider reads the detail through the API client', () async {
    // Jedyny test dotykający prawdziwego ciała providera — ekrany i odznaki
    // zawsze go nadpisują.
    final dio = Dio(BaseOptions(baseUrl: 'http://nas:8000'));
    DioAdapter(dio: dio).onGet(
      '/api/games/7/',
      (s) => s.reply(200, {
        'id': 7,
        'title': 'Hollow Knight',
        'system_code': 'switch',
        'system_name': 'Switch',
        'has_cover': false,
        'total_size': 1,
        'folder': 'Hollow Knight',
        'files': <Map<String, dynamic>>[],
      }),
    );
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://nas:8000', token: 't', dio: dio),
        ),
      ],
    );
    addTearDown(container.dispose);
    final detail = await container.read(gameDetailProvider(7).future);
    expect(detail.systemName, 'Switch');
  });

  test('bytesToFetch skips files already on disk', () {
    const local = LocalGameState(
      status: InstallStatus.partial,
      updateAvailable: true,
      missing: [],
      presentPaths: ['/roms/switch/hk.nsp'],
    );
    expect(bytesToFetch(_detail, {1, 2}, local), 2);
    expect(bytesToFetch(_detail, {1}, local), 0);
  });

  testWidgets('hero, pills, sections, back button', (tester) async {
    await _phoneSurface(tester);
    final port = FakeDownloaderPort()..free = 5 * 1024 * 1024 * 1024;
    await tester.pumpWidget(_screen(_detail, port: port));
    await tester.pumpAndSettle();
    expect(find.text('Hollow Knight'), findsWidgets);
    expect(find.text('Switch'), findsOneWidget);
    expect(find.text('Aktualizacja'), findsOneWidget);
    expect(find.text('najnowsza domyślnie'), findsOneWidget);
    expect(find.text('Pobierz · 3 B'), findsOneWidget);
    expect(find.text('Wolne 5.0 GB · zapis: /roms/switch'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.textContaining('v196608'), findsOneWidget);
    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('unchecking a file lowers the button size', (tester) async {
    await _phoneSurface(tester);
    await tester.pumpWidget(_screen(_detail));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    expect(find.text('Pobierz · 1 B'), findsOneWidget);
  });

  testWidgets('tapping the row itself also toggles the file', (tester) async {
    await _phoneSurface(tester);
    await tester.pumpWidget(_screen(_detail));
    await tester.pumpAndSettle();
    await tester.tap(find.text('upd.nsp'));
    await tester.pumpAndSettle();
    expect(find.text('Pobierz · 1 B'), findsOneWidget);
  });

  testWidgets('unknown free space shows only the directory', (tester) async {
    await _phoneSurface(tester);
    await tester.pumpWidget(_screen(_detail));
    await tester.pumpAndSettle();
    expect(find.text('zapis: /roms/switch'), findsOneWidget);
  });

  testWidgets('discs and support files get their own labels', (tester) async {
    await _phoneSurface(tester);
    const multiDisc = GameDetail(
      id: 7,
      title: 'Final Fantasy VII',
      systemCode: 'psx',
      systemName: 'PlayStation',
      hasCover: false,
      totalSize: 30,
      folder: 'Final Fantasy VII',
      files: [
        GameFileModel(
          id: 1,
          name: 'ff7-d1.cue',
          relativePath: 'psx/ff7-d1.cue',
          role: FileRole.disc,
          discNumber: 1,
          version: '',
          size: 10,
        ),
        GameFileModel(
          id: 2,
          name: 'ff7-d1.bin',
          relativePath: 'psx/ff7-d1.bin',
          role: FileRole.support,
          discNumber: null,
          version: '',
          size: 20,
        ),
      ],
    );
    await tester.pumpWidget(_screen(multiDisc));
    await tester.pumpAndSettle();
    expect(find.text('Płyta 1'), findsOneWidget);
    expect(find.text('Pozostałe'), findsOneWidget);
  });

  testWidgets('installed: pill and ghost delete only', (tester) async {
    await _phoneSurface(tester);
    await tester.pumpWidget(
      _screen(
        _detail,
        local: const LocalGameState(
          status: InstallStatus.installed,
          updateAvailable: false,
          missing: [],
          presentPaths: ['/roms/switch/hk.nsp', '/roms/switch/upd.nsp'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Zainstalowana'), findsOneWidget);
    expect(find.text('Usuń z urządzenia'), findsOneWidget);
    expect(find.textContaining('Pobierz'), findsNothing);
  });

  testWidgets('update available: update button and secondary delete', (
    tester,
  ) async {
    await _phoneSurface(tester);
    await tester.pumpWidget(
      _screen(
        _detail,
        local: const LocalGameState(
          status: InstallStatus.partial,
          updateAvailable: true,
          missing: [],
          presentPaths: ['/roms/switch/hk.nsp'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Jest aktualizacja'), findsOneWidget);
    expect(find.text('Pobierz aktualizację · 2 B'), findsOneWidget);
    expect(find.text('Usuń z urządzenia'), findsOneWidget);
  });

  testWidgets('partial without update shows the partial pill', (tester) async {
    await _phoneSurface(tester);
    await tester.pumpWidget(
      _screen(
        _detail,
        local: const LocalGameState(
          status: InstallStatus.partial,
          updateAvailable: false,
          missing: [],
          presentPaths: ['/roms/switch/upd.nsp'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Częściowo'), findsOneWidget);
  });

  testWidgets('offline disables download', (tester) async {
    await _phoneSurface(tester);
    await tester.pumpWidget(
      _screen(_detail, overrides: [isOfflineProvider.overrideWithValue(true)]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Offline — pobieranie niedostępne'), findsOneWidget);
  });

  testWidgets('with a cover the hero renders two images', (tester) async {
    await _phoneSurface(tester);
    await tester.pumpWidget(
      _screen(
        const GameDetail(
          id: 7,
          title: 'Hollow Knight',
          systemCode: 'switch',
          systemName: 'Switch',
          hasCover: true,
          totalSize: 3,
          folder: 'Hollow Knight',
          files: [],
        ),
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://nas:8000', token: 't'),
          ),
        ],
      ),
    );
    await tester.pump();
    expect(find.byType(CoverImage), findsNWidgets(2));
  });

  testWidgets('an error shows a retry action', (tester) async {
    await _phoneSurface(tester);
    await tester.pumpWidget(
      _screen(
        _detail,
        detailOverride: gameDetailProvider(7)
            .overrideWith((ref) async => throw StateError('x')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ponów'), findsOneWidget);
    await tester.tap(find.text('Ponów'));
    await tester.pumpAndSettle();
    expect(find.text('Ponów'), findsOneWidget);
  });

  testWidgets('local state error is humanized', (tester) async {
    await _phoneSurface(tester);
    await tester.pumpWidget(
      _screen(
        _detail,
        localOverride: localStateProvider(7)
            .overrideWith((ref) async => throw StateError('dysk')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Coś poszło nie tak'), findsOneWidget);
  });

  testWidgets('loading skeleton', (tester) async {
    await _phoneSurface(tester);
    final completer = Completer<GameDetail>();
    await tester.pumpWidget(
      _screen(
        _detail,
        detailOverride:
            gameDetailProvider(7).overrideWith((ref) => completer.future),
      ),
    );
    await tester.pump();
    expect(find.byType(PulseBox), findsWidgets);
    // Ekran nie ma AppBara — bez tego przycisku szkielet byłby ślepym
    // zaułkiem na nawigacji trójprzyciskowej.
    expect(find.byKey(const Key('back-button')), findsOneWidget);
  });

  testWidgets('the error state can go back', (tester) async {
    await _phoneSurface(tester);
    await tester.pumpWidget(
      _screen(
        _detail,
        detailOverride: gameDetailProvider(7)
            .overrideWith((ref) async => throw StateError('x')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Coś poszło nie tak'), findsOneWidget);
    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });
}
