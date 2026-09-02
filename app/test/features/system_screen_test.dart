import 'package:droplet/app/widgets/pulse_box.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/library/widgets/game_tile.dart';
import 'package:droplet/features/library/widgets/sort_menu.dart';
import 'package:droplet/features/system/system_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GameSummary g(int id, String title) => GameSummary(
      id: id,
      title: title,
      systemCode: 'snes',
      hasCover: false,
      totalSize: 5,
    );

LocalGameState local(InstallStatus s, {bool update = false}) => LocalGameState(
      status: s,
      updateAvailable: update,
      missing: const [],
      presentPaths: const [],
    );

const systems = [
  SystemModel(id: 1, code: 'snes', name: 'Super Nintendo', gameCount: 3),
];

GoRouter _router() => GoRouter(
      initialLocation: '/system/snes',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Home')),
          routes: [
            GoRoute(
              path: 'system/:code',
              builder: (_, s) => SystemScreen(code: s.pathParameters['code']!),
              routes: [
                GoRoute(
                  path: 'game/:id',
                  builder: (_, s) => Scaffold(
                    body: Text('Gra ${s.pathParameters['id']} z systemu'),
                  ),
                ),
              ],
            ),
            GoRoute(
              path: 'game/:id',
              builder: (_, s) =>
                  Scaffold(body: Text('Gra ${s.pathParameters['id']}')),
            ),
          ],
        ),
      ],
    );

Widget _app(List<GameSummary> games, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        librarySnapshotProvider.overrideWith(
          (ref) async => LibrarySnapshot(
            systems: systems,
            games: games,
            fromCache: false,
            previousIds: const {},
          ),
        ),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: _router()),
    );

void main() {
  final games = [g(1, 'Mario'), g(2, 'Zelda'), g(3, 'Metroid')];
  final states = [
    localStateProvider(1).overrideWith(
      (ref) async => local(InstallStatus.installed),
    ),
    localStateProvider(2).overrideWith(
      (ref) async => local(InstallStatus.partial, update: true),
    ),
    localStateProvider(3).overrideWith((ref) async => local(InstallStatus.none)),
  ];

  testWidgets('header, counts and back', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(games, overrides: states));
    await tester.pumpAndSettle();
    expect(find.text('Super Nintendo'), findsOneWidget);
    expect(find.text('3 gry · 2 na urządzeniu'), findsOneWidget);
    expect(find.text('Szukaj w Super Nintendo'), findsOneWidget);
    expect(find.byType(SortMenu), findsOneWidget);
    expect(find.byType(GameTile), findsNWidgets(3));
    await tester.tap(find.byKey(const Key('back-button')));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('chips filter installed and updatable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(games, overrides: states));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Na urządzeniu'));
    await tester.pumpAndSettle();
    expect(find.byType(GameTile), findsNWidgets(2));
    await tester.ensureVisible(
      find.text('Do aktualizacji', skipOffstage: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Do aktualizacji'));
    await tester.pumpAndSettle();
    expect(find.byType(GameTile), findsOneWidget);
    expect(find.text('Zelda'), findsWidgets);
    await tester.ensureVisible(find.text('Wszystkie', skipOffstage: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wszystkie'));
    await tester.pumpAndSettle();
    expect(find.byType(GameTile), findsNWidgets(3));
  });

  testWidgets('search narrows within the system', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(games, overrides: states));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'met');
    await tester.pumpAndSettle();
    expect(find.byType(GameTile), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.pumpAndSettle();
    expect(find.text('Nic nie pasuje'), findsOneWidget);
  });

  testWidgets('unknown system code shows a message', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          librarySnapshotProvider.overrideWith(
            (ref) async => const LibrarySnapshot(
              systems: [],
              games: [],
              fromCache: false,
              previousIds: {},
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nieznany system'), findsOneWidget);
  });

  testWidgets('loading skeleton and error, retry re-invokes the snapshot',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          librarySnapshotProvider.overrideWith((ref) async {
            attempts++;
            throw StateError('x');
          }),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    );
    expect(find.byType(PulseBox), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.text('Ponów'), findsOneWidget);
    expect(attempts, 1);
    await tester.tap(find.text('Ponów'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  testWidgets('tapping a game tile navigates within the system stack',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(games, overrides: states));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mario').first);
    await tester.pumpAndSettle();
    expect(find.text('Gra 1 z systemu'), findsOneWidget);
  });

  test('filterByQuery is case-insensitive', () {
    expect(filterByQuery(games, 'MAR').single.title, 'Mario');
    expect(filterByQuery(games, '  '), hasLength(3));
  });
}
