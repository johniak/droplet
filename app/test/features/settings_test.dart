import 'dart:io';

import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/device_scan.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/core/platform/downloader_port.dart';
import 'package:droplet/core/platform/permissions_port.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../fakes/fake_device_index.dart';
import '../fakes/fake_downloader_port.dart';
import '../fakes/fake_permissions_port.dart';

const systems = [
  SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 2),
  SystemModel(id: 2, code: 'psx', name: 'PSX', gameCount: 1),
];

GoRouter _router() => GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Home')),
          routes: [
            GoRoute(
              path: 'settings',
              builder: (_, __) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'folders',
                  builder: (_, __) => const Scaffold(body: Text('Foldery')),
                ),
              ],
            ),
          ],
        ),
      ],
    );

Widget _screen({
  required SessionRepository repo,
  PermissionsPort? port,
  FakeDownloaderPort? downloader,
  bool offline = false,
  String? baseDir,
  List<UnknownEntry> unknown = const [],
}) =>
    ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        deviceIndexProvider.overrideWith(
          () => FakeDeviceIndex(const {}, unknown: unknown),
        ),
        if (baseDir != null)
          storageSettingsProvider
              .overrideWith((ref) async => StorageSettings(baseDir, const {})),
        permissionsPortProvider
            .overrideWithValue(port ?? FakePermissionsPort(granted: true)),
        downloaderPortProvider
            .overrideWithValue(downloader ?? FakeDownloaderPort()),
        librarySnapshotProvider.overrideWith(
          (ref) async => LibrarySnapshot(
            systems: systems,
            games: [
              for (var i = 1; i <= 3; i++)
                GameSummary(
                  id: i,
                  title: 'G$i',
                  systemCode: 'snes',
                  hasCover: false,
                  totalSize: 1,
                  folder: 'G$i',
                ),
            ],
            manifest: [],
            fromCache: offline,
            previousIds: const {},
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    );

Future<SessionRepository> _signedIn() async {
  final repo = SessionRepository(MemoryKeyValueStore());
  await repo.save(const Session(serverUrl: 'http://nas:8000', token: 't'));
  return repo;
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('server card: status, counts, sign out', (tester) async {
    final repo = await _signedIn();
    await tester.pumpWidget(_screen(repo: repo));
    await tester.pumpAndSettle();
    expect(find.text('Ustawienia'), findsOneWidget);
    expect(find.text('Połączono'), findsOneWidget);
    expect(find.text('http://nas:8000 · 3 gier · 2 systemów'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Droplet $appVersion'), 200);
    expect(find.text('Droplet $appVersion'), findsOneWidget);
    expect(find.text('API v1'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Wyloguj'), -200);
    await tester.tap(find.text('Wyloguj'));
    await tester.pumpAndSettle();
    expect(await repo.load(), isNull);
  });

  testWidgets('offline status and unknown free space', (tester) async {
    await tester.pumpWidget(_screen(repo: await _signedIn(), offline: true));
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('free space is shown when known', (tester) async {
    final downloader = FakeDownloaderPort()..free = 2048;
    await tester.pumpWidget(
      _screen(repo: await _signedIn(), downloader: downloader),
    );
    await tester.pumpAndSettle();
    expect(find.text('2.0 KB'), findsOneWidget);
  });

  testWidgets('no session shows placeholder', (tester) async {
    await tester.pumpWidget(
      _screen(repo: SessionRepository(MemoryKeyValueStore())),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Nie zalogowano'), findsOneWidget);
  });

  testWidgets('folders row opens the sub-screen', (tester) async {
    await tester.pumpWidget(_screen(repo: await _signedIn()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Foldery per system'), 200);
    await tester.tap(find.text('Foldery per system'));
    await tester.pumpAndSettle();
    expect(find.text('Foldery'), findsOneWidget);
  });

  testWidgets('folders subtitle lists configured system codes', (
    tester,
  ) async {
    final repo = StorageSettingsRepository(SharedPreferencesAsync());
    await repo.saveSystemDir('snes', 'SNES');
    await repo.saveSystemDir('psx', 'PSX');
    await tester.pumpWidget(_screen(repo: await _signedIn()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('snes, psx'), 200);
    expect(find.text('snes, psx'), findsOneWidget);
  });

  testWidgets('unknown-on-device row shows count and deletes on request', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('roms');
    addTearDown(() => root.deleteSync(recursive: true));
    final stray = File('${root.path}/snes/old.sfc')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2]);
    final strayDir = Directory('${root.path}/snes/Old Game')
      ..createSync(recursive: true);
    File('${strayDir.path}/x.sfc').writeAsBytesSync([1, 2, 3]);
    final unknown = [
      UnknownEntry(
        systemCode: 'snes',
        path: stray.path,
        bytes: 2,
        isDirectory: false,
      ),
      UnknownEntry(
        systemCode: 'snes',
        path: strayDir.path,
        bytes: 3,
        isDirectory: true,
      ),
    ];
    await tester.pumpWidget(
      _screen(repo: await _signedIn(), baseDir: root.path, unknown: unknown),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('unknown-on-device')),
      200,
    );
    expect(find.text('2 pozycje · 5 B'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unknown-on-device')));
    await tester.pumpAndSettle();
    expect(find.text('snes/old.sfc'), findsOneWidget);
    expect(find.text('snes/Old Game'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unknown-delete-all')));
    await tester.pumpAndSettle();
    expect(stray.existsSync(), isFalse);
    expect(strayDir.existsSync(), isFalse);
  });

  testWidgets('the dialog closes without deleting anything', (tester) async {
    final root = Directory.systemTemp.createTempSync('roms');
    addTearDown(() => root.deleteSync(recursive: true));
    final stray = File('${root.path}/snes/old.sfc')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1]);
    final unknown = [
      for (var i = 0; i < 60; i++)
        UnknownEntry(
          systemCode: 'snes',
          path: i == 0 ? stray.path : '${root.path}/snes/ghost$i.sfc',
          bytes: 1,
          isDirectory: false,
        ),
    ];
    await tester.pumpWidget(
      _screen(repo: await _signedIn(), baseDir: root.path, unknown: unknown),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('unknown-on-device')),
      200,
    );
    expect(find.text('60 pozycji · 60 B'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unknown-on-device')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('… i 10 więcej'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('… i 10 więcej'), findsOneWidget);
    await tester.tap(find.text('Zamknij'));
    await tester.pumpAndSettle();
    expect(stray.existsSync(), isTrue);
  });

  testWidgets('no unknown entries shows Brak and opens nothing', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(repo: await _signedIn()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('unknown-on-device')),
      200,
    );
    expect(find.text('Brak'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unknown-on-device')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  test('deleteUnknown refuses paths outside the base dir', () {
    final root = Directory.systemTemp.createTempSync('roms');
    addTearDown(() => root.deleteSync(recursive: true));
    final outside = File(
      '${Directory.systemTemp.path}/droplet-outside-${root.hashCode}.tmp',
    )..writeAsBytesSync([1]);
    addTearDown(() {
      if (outside.existsSync()) outside.deleteSync();
    });
    deleteUnknown(
      [
        UnknownEntry(
          systemCode: 'x',
          path: outside.path,
          bytes: 1,
          isDirectory: false,
        ),
      ],
      root.path,
    );
    expect(outside.existsSync(), isTrue);
  });

  test('deleteUnknown skips entries that are already gone', () {
    final root = Directory.systemTemp.createTempSync('roms');
    addTearDown(() => root.deleteSync(recursive: true));
    deleteUnknown(
      [
        UnknownEntry(
          systemCode: 'x',
          path: '${root.path}/ghost.sfc',
          bytes: 1,
          isDirectory: false,
        ),
        UnknownEntry(
          systemCode: 'x',
          path: '${root.path}/ghost',
          bytes: 1,
          isDirectory: true,
        ),
      ],
      root.path,
    );
    expect(Directory(root.path).listSync(), isEmpty);
  });

  test('Polish plural of "pozycja"', () {
    expect(pluralPositions(1), '1 pozycja');
    expect(pluralPositions(2), '2 pozycje');
    expect(pluralPositions(5), '5 pozycji');
    expect(pluralPositions(11), '11 pozycji');
    expect(pluralPositions(22), '22 pozycje');
    expect(pluralPositions(25), '25 pozycji');
  });
}
