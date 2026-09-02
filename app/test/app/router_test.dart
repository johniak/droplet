import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/features/auth/login_screen.dart';
import 'package:droplet/features/downloads/downloads_screen.dart';
import 'package:droplet/features/game/game_detail_screen.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:droplet/features/library/library_screen.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/settings/folders_screen.dart';
import 'package:droplet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';


const _detail = GameDetail(
  id: 7,
  title: 'Hollow Knight',
  systemCode: 'switch',
  systemName: 'Switch',
  hasCover: false,
  totalSize: 1,
  files: [],
);

// The library and game screens are stubbed out at the data level so routing tests stay
// about routing (and never touch the network).
Widget _app(KeyValueStore store) => ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(SessionRepository(store)),
        gamesProvider.overrideWith((ref) async => <GameSummary>[]),
        systemsProvider.overrideWith((ref) async => <SystemModel>[]),
        gameDetailProvider(7).overrideWith((ref) async => _detail),
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
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('no session -> login screen', (tester) async {
    await tester.pumpWidget(_app(MemoryKeyValueStore()));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('session -> library', (tester) async {
    await tester.pumpWidget(_app(await _signedIn()));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);
  });

  testWidgets('nested routes render below the library', (tester) async {
    await tester.pumpWidget(_app(await _signedIn()));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(LibraryScreen));

    context.go('/game/7');
    await tester.pumpAndSettle();
    expect(find.byType(GameDetailScreen), findsOneWidget);

    context.go('/downloads');
    await tester.pumpAndSettle();
    expect(find.byType(DownloadsScreen), findsOneWidget);

    context.go('/settings');
    await tester.pumpAndSettle();
    expect(find.text('Ustawienia'), findsOneWidget);

    context.go('/settings/folders');
    await tester.pumpAndSettle();
    expect(find.byType(FoldersScreen), findsOneWidget);
  });

  testWidgets('signing in redirects away from login', (tester) async {
    final store = MemoryKeyValueStore();
    final repo = SessionRepository(store);
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(repo),
          gamesProvider.overrideWith((ref) async => <GameSummary>[]),
          systemsProvider.overrideWith((ref) async => <SystemModel>[]),
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
    expect(find.byType(LibraryScreen), findsOneWidget);
  });
}
