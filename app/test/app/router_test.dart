import 'package:droplet/app/router.dart';
import 'package:droplet/app/widgets/glass_bar.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/platform/downloader_port.dart';
import 'package:droplet/core/platform/permissions_port.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:droplet/features/auth/login_screen.dart';
import 'package:droplet/features/downloads/downloads_screen.dart';
import 'package:droplet/features/game/game_detail_screen.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:droplet/features/home/home_screen.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/settings/folders_screen.dart';
import 'package:droplet/features/settings/settings_screen.dart';
import 'package:droplet/features/system/system_screen.dart';
import 'package:droplet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../fakes/fake_downloader_port.dart';
import '../fakes/fake_permissions_port.dart';

const _detail = GameDetail(
  id: 7,
  title: 'Hollow Knight',
  systemCode: 'switch',
  systemName: 'Switch',
  hasCover: false,
  totalSize: 1,
  files: [],
);

const _games = [
  GameSummary(
    id: 7,
    title: 'Hollow Knight',
    systemCode: 'switch',
    hasCover: false,
    totalSize: 1,
  ),
];
const _systems = [
  SystemModel(id: 1, code: 'switch', name: 'Switch', gameCount: 1),
];

Widget _app(KeyValueStore store) => ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(SessionRepository(store)),
        librarySnapshotProvider.overrideWith(
          (ref) async => const LibrarySnapshot(
            systems: _systems,
            games: _games,
            fromCache: false,
            previousIds: {7},
          ),
        ),
        gameDetailProvider(7).overrideWith((ref) async => _detail),
        localStateProvider(7).overrideWith(
          (ref) async => const LocalGameState(
            status: InstallStatus.none,
            updateAvailable: false,
            missing: [],
            presentPaths: [],
          ),
        ),
        downloaderPortProvider.overrideWithValue(FakeDownloaderPort()),
        permissionsPortProvider.overrideWithValue(
          FakePermissionsPort(granted: true),
        ),
      ],
      child: const DropletApp(),
    );

Future<MemoryKeyValueStore> _signedIn() async {
  final store = MemoryKeyValueStore();
  await SessionRepository(store)
      .save(const Session(serverUrl: 'http://nas:8000', token: 't'));
  return store;
}

void main() {
  test('hidesNavBar only on the game screen', () {
    expect(hidesNavBar('/game/7'), isTrue);
    expect(hidesNavBar('/system/snes'), isFalse);
    expect(hidesNavBar('/downloads'), isFalse);
  });

  testWidgets('no session -> login screen', (tester) async {
    await tester.pumpWidget(_app(MemoryKeyValueStore()));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(GlassBar), findsNothing);
  });

  testWidgets('session -> home with the bar', (tester) async {
    await tester.pumpWidget(_app(await _signedIn()));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(GlassBar), findsOneWidget);
  });

  testWidgets('library branch keeps its stack; bar hides on the game', (
    tester,
  ) async {
    await tester.pumpWidget(_app(await _signedIn()));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(HomeScreen));

    context.go('/system/switch');
    await tester.pumpAndSettle();
    expect(find.byType(SystemScreen), findsOneWidget);

    context.go('/system/switch/game/7');
    await tester.pumpAndSettle();
    expect(find.byType(GameDetailScreen), findsOneWidget);
    expect(find.byType(GlassBar), findsNothing);

    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    expect(find.byType(SystemScreen), findsOneWidget);
    expect(find.byType(GlassBar), findsOneWidget);
  });

  testWidgets('bottom tabs switch branches', (tester) async {
    await tester.pumpWidget(_app(await _signedIn()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-downloads')));
    await tester.pumpAndSettle();
    expect(find.byType(DownloadsScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-library')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('settings folders route is reachable and keeps the bar', (
    tester,
  ) async {
    await tester.pumpWidget(_app(await _signedIn()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
    tester.element(find.byType(SettingsScreen)).go('/settings/folders');
    await tester.pumpAndSettle();
    expect(find.byType(FoldersScreen), findsOneWidget);
    expect(find.byType(GlassBar), findsOneWidget);
  });

  testWidgets('go to a game from downloads lands in the library branch', (
    tester,
  ) async {
    await tester.pumpWidget(_app(await _signedIn()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-downloads')));
    await tester.pumpAndSettle();
    tester.element(find.byType(DownloadsScreen)).go('/game/7');
    await tester.pumpAndSettle();
    expect(find.byType(GameDetailScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('signing in redirects away from login', (tester) async {
    final store = MemoryKeyValueStore();
    final repo = SessionRepository(store);
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(repo),
          librarySnapshotProvider.overrideWith(
            (ref) async => const LibrarySnapshot(
              systems: [],
              games: [],
              fromCache: false,
              previousIds: {},
            ),
          ),
          downloaderPortProvider.overrideWithValue(FakeDownloaderPort()),
          permissionsPortProvider.overrideWithValue(
            FakePermissionsPort(granted: true),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const DropletApp();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    await repo.save(const Session(serverUrl: 'http://nas:8000', token: 't'));
    container.read(sessionProvider.notifier).state =
        const AsyncData(Session(serverUrl: 'http://nas:8000', token: 't'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
