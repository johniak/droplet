import 'dart:async';

import 'package:droplet/app/input/gamepad.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/features/home/home_screen.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/library/widgets/game_tile.dart';
import 'package:droplet/features/library/widgets/games_grid.dart';
import 'package:droplet/features/library/widgets/shelf.dart';
import 'package:droplet/features/library/widgets/search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../fakes/fake_device_index.dart';
import '../helpers/focus.dart';

GameSummary g(int id, String title, String system) => GameSummary(
  id: id,
  title: title,
  systemCode: system,
  hasCover: false,
  totalSize: 5,
  folder: title,
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

LibrarySnapshot snap({
  bool fromCache = false,
  Set<int> previous = const {1, 2},
}) => LibrarySnapshot(
  systems: systems,
  games: games,
  manifest: [],
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
              Scaffold(body: Text('Game ${s.pathParameters['id']}')),
        ),
      ],
    ),
  ],
);

// riverpod 3 throws if the same provider appears twice in an overrides list
// (even with different values), so — unlike the naive `...overrides` spread —
// a per-slot override (snapshot, second game's local state) replaces the
// matching default instead of sitting next to it.
Widget _app({Override? snapshotOverride, LocalGameState local2 = _none}) =>
    ProviderScope(
      overrides: [
        snapshotOverride ??
            librarySnapshotProvider.overrideWith((ref) async => snap()),
        deviceIndexProvider.overrideWith(
          () => FakeDeviceIndex({1: _none, 2: local2}),
        ),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    );

/// The same screen as `_app`, but with a handle on the container — tests
/// that need to touch the notifier or invalidate a provider need it from
/// the outside.
Widget _appWithContainer(
  void Function(ProviderContainer) onContainer, {
  Override? snapshotOverride,
  Override? indexOverride,
}) => ProviderScope(
  overrides: [
    snapshotOverride ??
        librarySnapshotProvider.overrideWith((ref) async => snap()),
    indexOverride ??
        deviceIndexProvider.overrideWith(
          () => FakeDeviceIndex({1: _none, 2: _none}),
        ),
  ],
  child: Consumer(
    builder: (context, ref, _) {
      onContainer(ProviderScope.containerOf(context));
      return MaterialApp.router(routerConfig: _router());
    },
  ),
);

void main() {
  // The focus glow follows Flutter's highlight mode: visible only after a key
  // or pad event. These tests assert on the glow, so they run in that mode.
  setUp(() => FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional);
  tearDown(() => FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.automatic);

  testWidgets('shelves keep stable keys when the installed shelf appears', (
    tester,
  ) async {
    late ProviderContainer container;
    // Empty index: no game is on the device yet, so the "On device" shelf
    // doesn't exist yet.
    await tester.pumpWidget(
      _appWithContainer(
        (c) => container = c,
        indexOverride: deviceIndexProvider.overrideWith(
          () => FakeDeviceIndex({}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    const snesKey = ValueKey('shelf-snes');
    expect(find.byKey(const ValueKey('shelf-installed')), findsNothing);
    expect(find.byKey(snesKey), findsOneWidget);
    final before = tester.element(find.byKey(snesKey));

    // A rescan finds game 1 on disk — the shelf then jumps into the middle
    // of the list.
    final index =
        container.read(deviceIndexProvider.notifier) as FakeDeviceIndex;
    index.states[1] = const LocalGameState(
      status: InstallStatus.installed,
      updateAvailable: false,
      missing: [],
      presentPaths: ['/x'],
    );
    await index.refresh();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shelf-installed')), findsOneWidget);
    expect(find.byKey(snesKey), findsOneWidget);
    // Same element, despite the insertion before it: the key preserved the
    // shelf's state.
    expect(identical(tester.element(find.byKey(snesKey)), before), isTrue);
    expect(find.byKey(const ValueKey('shelf-recent')), findsOneWidget);
  });

  testWidgets('a later refresh announces new games again', (tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      _appWithContainer(
        (c) => container = c,
        // Each call builds a new snapshot — the latch keyed on object
        // identity, not a bool flag, has to notice this.
        snapshotOverride: librarySnapshotProvider.overrideWith(
          (ref) async => snap(previous: {1}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('New in library: 1 game'), findsOneWidget);
    // Wait for the banner to disappear on its own (default 4s) so the second
    // occurrence is a new banner, not a leftover from the first.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('New in library: 1 game'), findsNothing);

    container.invalidate(librarySnapshotProvider);
    await tester.pumpAndSettle();
    expect(find.text('New in library: 1 game'), findsOneWidget);
  });

  testWidgets('new in library ignores support packs', (tester) async {
    // A pack has an id the snapshot never saw before, but it must not show
    // up in the "New in library" count — only real games do.
    final withPack = LibrarySnapshot(
      systems: systems,
      games: games,
      supportPacks: const [
        GameSummary(
          id: 99,
          title: 'RetroArch',
          systemCode: 'bios',
          hasCover: false,
          totalSize: 4,
          folder: 'RetroArch',
        ),
      ],
      manifest: const [],
      fromCache: false,
      previousIds: const {1, 2},
    );
    await tester.pumpWidget(
      _appWithContainer(
        (_) {},
        snapshotOverride: librarySnapshotProvider.overrideWith(
          (ref) async => withPack,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('New in library'), findsNothing);
  });

  testWidgets('several new games use the plural form', (tester) async {
    await tester.pumpWidget(
      _appWithContainer(
        (_) {},
        snapshotOverride: librarySnapshotProvider.overrideWith(
          (ref) async => snap(previous: {99}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('New in library: 2 games'), findsOneWidget);
  });

  testWidgets('wide layout puts the search field into the header row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final title = tester.getCenter(find.text('Droplet'));
    final field = tester.getCenter(find.byType(SearchField));
    // Same row as the title, to its right — not a row of its own below it.
    expect((field.dy - title.dy).abs(), lessThan(24));
    expect(field.dx, greaterThan(title.dx));
    expect(find.byType(SearchField), findsOneWidget);
  });

  testWidgets('narrow layout keeps the search field under the header', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final title = tester.getCenter(find.text('Droplet'));
    final field = tester.getCenter(find.byType(SearchField));
    expect(field.dy, greaterThan(title.dy + 24));
  });

  testWidgets('shelves: recent + per system, header opens the system', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('Droplet'), findsOneWidget);
    expect(find.text('Recently added'), findsOneWidget);
    expect(find.text('On device'), findsNothing);
    expect(find.text('SNES'), findsOneWidget);
    expect(find.text('Super Mario World'), findsWidgets);
    // The whole shelf header — title and trailing "N ›" alike — is one tap
    // target (see library_widgets_test.dart: 'Shelf header tap fires
    // onSeeAll from either the title or the trailing text').
    await tester.tap(find.text('SNES'));
    await tester.pumpAndSettle();
    expect(find.text('System snes'), findsOneWidget);
  });

  testWidgets('shelf header: tapping the trailing count also navigates', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    // Both fixture systems have exactly one game, so both shelves show
    // "1 ›" — the SNES shelf is first in system order, hence `.first`.
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
    expect(find.text('On device'), findsOneWidget);
  });

  testWidgets('typing swaps shelves for a results grid', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'tek');
    await tester.pumpAndSettle();
    expect(find.byType(Shelf), findsNothing);
    expect(find.byType(GamesGrid), findsOneWidget);
    expect(find.text('Results · 1'), findsOneWidget);
    // 'Tekken' has no cover, so it renders twice: once as the placeholder
    // title, once as the tile caption (see library_widgets_test.dart).
    expect(find.text('Tekken'), findsNWidgets(2));
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No results'), findsOneWidget);
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
      find.text('Offline — showing the last synced library'),
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
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('empty library', (tester) async {
    await tester.pumpWidget(
      _app(
        snapshotOverride: librarySnapshotProvider.overrideWith(
          (ref) async => const LibrarySnapshot(
            systems: [],
            games: [],
            manifest: [],
            fromCache: false,
            previousIds: {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing here yet'), findsOneWidget);
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
    expect(find.text('New in library: 1 game'), findsOneWidget);
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

  testWidgets('the pad starts on the first card and walks right', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    // 'Recently added' is the first shelf and lists the newest first, so its
    // first card is Tekken (id 2) and the second Super Mario World (id 1).
    final cards = find.byType(ShelfCard);
    expect(hasGlow(tester, cards.first), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(hasGlow(tester, cards.first), isFalse);
    expect(hasGlow(tester, cards.at(1)), isTrue);

    // A is the pad's "open".
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(find.text('Game 1'), findsOneWidget);
  });

  testWidgets('Y focuses the search field, B hands the focus back', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ProviderScope(
          overrides: [
            librarySnapshotProvider.overrideWith((ref) async => snap()),
            deviceIndexProvider.overrideWith(
              () => FakeDeviceIndex({1: _none, 2: _none}),
            ),
          ],
          // The shell is what carries the Y shortcut in the real app.
          child: GamepadShortcuts(
            currentIndex: 0,
            onTab: (_) {},
            child: const HomeScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonY);
    await tester.pumpAndSettle();
    expect(field.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();
    expect(field.focusNode!.hasFocus, isFalse);
  });

  testWidgets('skeleton does not overflow on a narrow phone screen', (
    tester,
  ) async {
    // Regression: the skeleton shelf row used to be a fixed-width Row (4 ×
    // 96 + padding = 424dp) that overflowed on real phone widths narrower
    // than that — caught by app_flow_test.dart on an emulator (~395dp).
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomeSkeleton())),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
