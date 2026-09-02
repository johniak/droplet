import 'package:droplet/core/api/models.dart';
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
}) =>
    ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
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
                ),
            ],
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
    expect(find.text('Droplet $appVersion'), findsOneWidget);
    expect(find.text('API v1'), findsOneWidget);
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
}
