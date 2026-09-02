import 'package:droplet/core/api/models.dart';
import 'package:droplet/features/library/library_screen.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  final games = [
    const GameSummary(
      id: 1,
      title: 'Super Mario World',
      systemCode: 'snes',
      hasCover: false,
      totalSize: 5,
    ),
    const GameSummary(
      id: 2,
      title: 'Tekken',
      systemCode: 'psx',
      hasCover: false,
      totalSize: 9,
    ),
  ];
  final systems = [
    const SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 1),
    const SystemModel(id: 2, code: 'psx', name: 'PSX', gameCount: 1),
  ];

  Widget build() => ProviderScope(
        overrides: [
          gamesProvider.overrideWith((ref) async => games),
          systemsProvider.overrideWith((ref) async => systems),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      );

  GoRouter routedRouter() => GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const LibraryScreen(),
            routes: [
              GoRoute(
                path: 'settings',
                builder: (_, __) => const Scaffold(body: Text('Ustawienia')),
              ),
              GoRoute(
                path: 'downloads',
                builder: (_, __) => const Scaffold(body: Text('Pobierania')),
              ),
            ],
          ),
        ],
      );

  Widget buildRouted() => ProviderScope(
        overrides: [
          gamesProvider.overrideWith((ref) async => games),
          systemsProvider.overrideWith((ref) async => systems),
        ],
        child: MaterialApp.router(routerConfig: routedRouter()),
      );

  testWidgets('shows games and system chips', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(find.text('Super Mario World'), findsWidgets);
    expect(find.text('SNES'), findsOneWidget);
    expect(find.text('Wszystkie'), findsOneWidget);
  });

  testWidgets('system chip filters and search updates provider', (
    tester,
  ) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    await tester.tap(find.text('PSX'));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryScreen)),
    );
    expect(container.read(selectedSystemProvider), 'psx');
    await tester.enterText(find.byType(TextField).first, 'tek');
    await tester.pump();
    expect(container.read(searchQueryProvider), 'tek');
  });

  testWidgets('tapping "Wszystkie" clears the system filter', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    await tester.tap(find.text('PSX'));
    await tester.pump();
    await tester.tap(find.text('Wszystkie'));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryScreen)),
    );
    expect(container.read(selectedSystemProvider), isNull);
  });

  testWidgets('error state shows retry', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gamesProvider.overrideWith((ref) async => throw StateError('x')),
          systemsProvider.overrideWith((ref) async => systems),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ponów'), findsOneWidget);
    await tester.tap(find.text('Ponów'));
    await tester.pumpAndSettle();
    expect(find.text('Ponów'), findsOneWidget);
  });

  testWidgets('empty library shows a message', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gamesProvider.overrideWith((ref) async => <GameSummary>[]),
          systemsProvider.overrideWith((ref) async => systems),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nic tu nie ma'), findsOneWidget);
  });

  testWidgets('offline mode explains itself with a banner', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gamesProvider.overrideWith((ref) async => games),
          systemsProvider.overrideWith((ref) async => systems),
          isOfflineProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Tryb offline — pokazuję ostatnio pobraną bibliotekę'),
      findsOneWidget,
    );
  });

  testWidgets('the sort menu switches ordering', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ostatnio dodane'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryScreen)),
    );
    expect(container.read(sortProvider), LibrarySort.recentlyAdded);
  });

  testWidgets('the installed-only chip toggles the filter', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tylko zainstalowane'));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryScreen)),
    );
    expect(container.read(installedOnlyProvider), true);
  });

  test('installedIds tracks games with files on disk', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ids = container.read(installedIdsProvider.notifier);
    ids.mark(1, installed: true);
    expect(container.read(installedIdsProvider), {1});
    ids.mark(1, installed: true); // no-op
    expect(container.read(installedIdsProvider), {1});
    ids.mark(1, installed: false);
    expect(container.read(installedIdsProvider), isEmpty);
  });

  testWidgets('a refresh announces what is new', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gamesProvider.overrideWith((ref) async => games),
          systemsProvider.overrideWith((ref) async => systems),
          librarySnapshotProvider.overrideWith(
            (ref) async => LibrarySnapshot(
              systems: systems,
              games: games,
              fromCache: false,
              previousIds: const {1},
            ),
          ),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nowe w bibliotece: 1 gier'), findsOneWidget);
  });

  testWidgets('nothing new means no snackbar', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gamesProvider.overrideWith((ref) async => games),
          systemsProvider.overrideWith((ref) async => systems),
          librarySnapshotProvider.overrideWith(
            (ref) async => LibrarySnapshot(
              systems: systems,
              games: games,
              fromCache: false,
              previousIds: const {1, 2},
            ),
          ),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Nowe w bibliotece'), findsNothing);
  });

  testWidgets('the settings action opens settings', (tester) async {
    await tester.pumpWidget(buildRouted());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Ustawienia'), findsOneWidget);
  });

  testWidgets('the downloads action opens the queue', (tester) async {
    await tester.pumpWidget(buildRouted());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Pobierania'), findsOneWidget);
  });

  testWidgets('pull to refresh reloads the games', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    await tester.fling(find.byType(GridView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Super Mario World'), findsWidgets);
  });
}
