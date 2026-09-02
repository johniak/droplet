import 'dart:async';

import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:droplet/features/home/home_screen.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/library/widgets/games_grid.dart';
import 'package:droplet/features/library/widgets/shelf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GameSummary g(int id, String title, String system) => GameSummary(
      id: id,
      title: title,
      systemCode: system,
      hasCover: false,
      totalSize: 5,
    );

final games = [g(1, 'Super Mario World', 'snes'), g(2, 'Tekken', 'psx')];
const systems = [
  SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 1),
  SystemModel(id: 2, code: 'psx', name: 'PSX', gameCount: 1),
];

const _none = LocalGameState(
  status: InstallStatus.none,
  updateAvailable: false,
  missing: [],
  presentPaths: [],
);

LibrarySnapshot snap({bool fromCache = false, Set<int> previous = const {1, 2}}) =>
    LibrarySnapshot(
      systems: systems,
      games: games,
      fromCache: fromCache,
      previousIds: previous,
    );

GoRouter _router() => GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const HomeScreen(),
          routes: [
            GoRoute(
              path: 'system/:code',
              builder: (_, s) =>
                  Scaffold(body: Text('System ${s.pathParameters['code']}')),
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

// riverpod 3 throws if the same provider appears twice in an overrides list
// (even with different values), so — unlike the naive `...overrides` spread —
// a per-slot override (snapshot, second game's local state) replaces the
// matching default instead of sitting next to it.
Widget _app({
  Override? snapshotOverride,
  LocalGameState local2 = _none,
}) => ProviderScope(
      overrides: [
        snapshotOverride ??
            librarySnapshotProvider.overrideWith((ref) async => snap()),
        localStateProvider(1).overrideWith((ref) async => _none),
        localStateProvider(2).overrideWith((ref) async => local2),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    );

void main() {
  testWidgets('shelves: recent + per system, header opens the system', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('Droplet'), findsOneWidget);
    expect(find.text('Ostatnio dodane'), findsOneWidget);
    expect(find.text('Na urządzeniu'), findsNothing);
    expect(find.text('SNES'), findsOneWidget);
    expect(find.text('Super Mario World'), findsWidgets);
    // Shelf wires navigation to the "see all" trailing text next to the
    // title, not the title itself (see library_widgets_test.dart). Both
    // fixture systems have exactly one game, so both shelves show "1 ›" —
    // the SNES shelf is first in system order, hence `.first`.
    await tester.tap(find.text('1 ›').first);
    await tester.pumpAndSettle();
    expect(find.text('System snes'), findsOneWidget);
  });

  testWidgets('installed shelf appears when something is on disk', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        local2: const LocalGameState(
          status: InstallStatus.installed,
          updateAvailable: false,
          missing: [],
          presentPaths: ['/x'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Na urządzeniu'), findsOneWidget);
  });

  testWidgets('typing swaps shelves for a results grid', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'tek');
    await tester.pumpAndSettle();
    expect(find.byType(Shelf), findsNothing);
    expect(find.byType(GamesGrid), findsOneWidget);
    expect(find.text('Wyniki · 1'), findsOneWidget);
    // 'Tekken' has no cover, so it renders twice: once as the placeholder
    // title, once as the tile caption (see library_widgets_test.dart).
    expect(find.text('Tekken'), findsNWidgets(2));
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Brak wyników'), findsOneWidget);
  });

  testWidgets('offline pill', (tester) async {
    await tester.pumpWidget(
      _app(
        snapshotOverride: librarySnapshotProvider.overrideWith(
          (ref) async => snap(fromCache: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Tryb offline — pokazuję ostatnio pobraną bibliotekę'),
      findsOneWidget,
    );
  });

  testWidgets('error state retries', (tester) async {
    await tester.pumpWidget(
      _app(
        snapshotOverride: librarySnapshotProvider.overrideWith(
          (ref) async => throw StateError('x'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ponów'), findsOneWidget);
    await tester.tap(find.text('Ponów'));
    await tester.pumpAndSettle();
    expect(find.text('Ponów'), findsOneWidget);
  });

  testWidgets('empty library', (tester) async {
    await tester.pumpWidget(
      _app(
        snapshotOverride: librarySnapshotProvider.overrideWith(
          (ref) async => const LibrarySnapshot(
            systems: [],
            games: [],
            fromCache: false,
            previousIds: {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nic tu nie ma'), findsOneWidget);
  });

  testWidgets('new games are announced once', (tester) async {
    await tester.pumpWidget(
      _app(
        snapshotOverride: librarySnapshotProvider.overrideWith(
          (ref) async => snap(previous: {1}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nowe w bibliotece: 1 gier'), findsOneWidget);
  });

  testWidgets('pull to refresh reloads the library', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    // The outer vertical shelf list is first; the shelves' own horizontal
    // ListViews come after it in tree order.
    await tester.fling(find.byType(ListView).first, const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Super Mario World'), findsWidgets);
  });

  testWidgets('loading shows skeleton', (tester) async {
    // A Completer that is never completed — unlike Future.delayed, it
    // schedules no pending Timer for flutter_test to complain about at the
    // end of the test.
    final completer = Completer<LibrarySnapshot>();
    await tester.pumpWidget(
      _app(
        snapshotOverride: librarySnapshotProvider.overrideWith(
          (ref) => completer.future,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(HomeSkeleton), findsOneWidget);
  });
}
