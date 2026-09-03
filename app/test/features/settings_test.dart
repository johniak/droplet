import 'dart:async';
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

/// A non-empty manifest means the library is known, so "unknown" really
/// means "redundant" and it's fine to delete it.
final knownLibrary = [
  ManifestEntry(
    gameId: 1,
    systemCode: 'snes',
    folder: 'G1',
    files: const [],
  ),
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
                  builder: (_, __) => const Scaffold(body: Text('Folders')),
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
  bool pendingSettings = false,
  List<UnknownEntry> unknown = const [],
  List<ManifestEntry> manifest = const [],
  FakeDeviceIndex? index,
}) =>
    ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        deviceIndexProvider.overrideWith(
          () => index ?? FakeDeviceIndex(const {}, unknown: unknown),
        ),
        if (pendingSettings)
          storageSettingsProvider
              .overrideWith((ref) => Completer<StorageSettings>().future),
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
            manifest: manifest,
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
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('http://nas:8000 · 3 games · 2 systems'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Droplet $appVersion'), 200);
    expect(find.text('Droplet $appVersion'), findsOneWidget);
    expect(find.text('API v1'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Sign out'), -200);
    await tester.tap(find.text('Sign out'));
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
    expect(find.textContaining('Not signed in'), findsOneWidget);
  });

  testWidgets('folders row opens the sub-screen', (tester) async {
    await tester.pumpWidget(_screen(repo: await _signedIn()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Folders per system'), 200);
    await tester.tap(find.text('Folders per system'));
    await tester.pumpAndSettle();
    expect(find.text('Folders'), findsOneWidget);
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
    final index = FakeDeviceIndex(const {}, unknown: unknown);
    await tester.pumpWidget(
      _screen(
        repo: await _signedIn(),
        baseDir: root.path,
        unknown: unknown,
        manifest: knownLibrary,
        index: index,
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('unknown-on-device')),
      200,
    );
    expect(find.text('2 items · 5 B'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unknown-on-device')));
    await tester.pumpAndSettle();
    // The summary also shows in the dialog — the user sees the scale of the
    // deletion where they click, not just in the row behind the dialog.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('2 items · 5 B'),
      ),
      findsOneWidget,
    );
    expect(find.text('snes/old.sfc'), findsOneWidget);
    expect(find.text('snes/Old Game'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unknown-delete-all')));
    await tester.pumpAndSettle();
    expect(stray.existsSync(), isFalse);
    expect(strayDir.existsSync(), isFalse);
    expect(index.refreshes, 1, reason: 'the index should refresh after deleting');
  });

  testWidgets('an empty manifest disables deleting everything', (tester) async {
    final root = Directory.systemTemp.createTempSync('roms');
    addTearDown(() => root.deleteSync(recursive: true));
    final stray = File('${root.path}/snes/old.sfc')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2]);
    final index = FakeDeviceIndex(
      const {},
      unknown: [
        UnknownEntry(
          systemCode: 'snes',
          path: stray.path,
          bytes: 2,
          isDirectory: false,
        ),
      ],
    );
    await tester.pumpWidget(
      _screen(
        repo: await _signedIn(),
        baseDir: root.path,
        unknown: index.unknown,
        index: index,
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('unknown-on-device')),
      200,
    );
    await tester.tap(find.byKey(const Key('unknown-on-device')));
    await tester.pumpAndSettle();
    expect(find.text('Sync the library from the server first'), findsOneWidget);
    final button = tester.widget<TextButton>(
      find.byKey(const Key('unknown-delete-all')),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.byKey(const Key('unknown-delete-all')));
    await tester.pumpAndSettle();
    expect(stray.existsSync(), isTrue);
    expect(index.refreshes, 0);
  });

  testWidgets('an entry outside the ROM dir keeps its full path', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('roms');
    addTearDown(() => root.deleteSync(recursive: true));
    const outside = '/var/elsewhere/stray.sfc';
    await tester.pumpWidget(
      _screen(
        repo: await _signedIn(),
        baseDir: root.path,
        manifest: knownLibrary,
        unknown: const [
          UnknownEntry(
            systemCode: 'snes',
            path: outside,
            bytes: 1,
            isDirectory: false,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('unknown-on-device')),
      200,
    );
    await tester.tap(find.byKey(const Key('unknown-on-device')));
    await tester.pumpAndSettle();
    expect(find.text(outside), findsOneWidget);
  });

  testWidgets('without a known ROM dir the row is not tappable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen(
        repo: await _signedIn(),
        pendingSettings: true,
        unknown: const [
          UnknownEntry(
            systemCode: 'snes',
            path: '/roms/snes/old.sfc',
            bytes: 1,
            isDirectory: false,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('unknown-on-device')),
      200,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('unknown-on-device')),
        matching: find.byIcon(Icons.chevron_right),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('unknown-on-device')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
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
      _screen(
        repo: await _signedIn(),
        baseDir: root.path,
        unknown: unknown,
        manifest: knownLibrary,
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('unknown-on-device')),
      200,
    );
    expect(find.text('60 items · 60 B'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unknown-on-device')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('… and 10 more'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('… and 10 more'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(stray.existsSync(), isTrue);
  });

  testWidgets('no unknown entries shows None and opens nothing', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(repo: await _signedIn()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('unknown-on-device')),
      200,
    );
    expect(find.text('None'), findsOneWidget);
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
      StorageSettings(root.path, const {}),
      const ['snes'],
    );
    expect(outside.existsSync(), isTrue);
  });

  test('deleteUnknown refuses a system dir and a path with ..', () {
    final root = Directory.systemTemp.createTempSync('roms');
    addTearDown(() => root.deleteSync(recursive: true));
    final settings = StorageSettings(root.path, const {});
    final systemDir = Directory('${root.path}/snes')..createSync();
    final sibling = Directory('${root.path}/keep')..createSync();
    deleteUnknown(
      [
        UnknownEntry(
          systemCode: 'snes',
          path: systemDir.path,
          bytes: 0,
          isDirectory: true,
        ),
        UnknownEntry(
          systemCode: 'snes',
          path: '${root.path}/snes/../keep',
          bytes: 0,
          isDirectory: true,
        ),
      ],
      settings,
      const ['snes'],
    );
    expect(systemDir.existsSync(), isTrue);
    expect(sibling.existsSync(), isTrue);
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
      StorageSettings(root.path, const {}),
      const ['snes'],
    );
    expect(Directory(root.path).listSync(), isEmpty);
  });

  test('displayPath trims the ROM dir, keeps anything outside it', () {
    expect(displayPath('/roms/snes/x.sfc', '/roms'), 'snes/x.sfc');
    expect(displayPath('/other/x.sfc', '/roms'), '/other/x.sfc');
    expect(displayPath('/roms', '/roms/deeper'), '/roms');
  });

  test('pluralPositions is singular-aware', () {
    expect(pluralPositions(1), '1 item');
    expect(pluralPositions(2), '2 items');
    expect(pluralPositions(5), '5 items');
    expect(pluralPositions(11), '11 items');
    expect(pluralPositions(22), '22 items');
    expect(pluralPositions(25), '25 items');
  });
}
