import 'package:droplet/app/input/gamepad.dart';
import 'package:droplet/app/widgets/focus_glow.dart';
import 'package:droplet/app/widgets/pulse_box.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/library/widgets/game_tile.dart';
import 'package:droplet/features/library/widgets/sort_menu.dart';
import 'package:droplet/features/system/system_screen.dart';
import 'package:droplet/features/library/widgets/search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../fakes/fake_device_index.dart';
import '../helpers/focus.dart';

Finder chip(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(FocusGlow));

GameSummary g(int id, String title) => GameSummary(
      id: id,
      title: title,
      systemCode: 'snes',
      hasCover: false,
      totalSize: 5,
      folder: title,
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
                    body: Text('Game ${s.pathParameters['id']} from system'),
                  ),
                ),
              ],
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

Widget _app(List<GameSummary> games, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        librarySnapshotProvider.overrideWith(
          (ref) async => LibrarySnapshot(
            systems: systems,
            games: games,
            manifest: [],
            fromCache: false,
            previousIds: const {},
          ),
        ),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: _router()),
    );

void main() {
  // The focus glow follows Flutter's highlight mode: visible only after a key
  // or pad event. These tests assert on the glow, so they run in that mode.
  setUp(() => FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional);
  tearDown(() => FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.automatic);

  final games = [g(1, 'Mario'), g(2, 'Zelda'), g(3, 'Metroid')];
  // One device index feeds both the badges and the filter chips.
  final states = [
    deviceIndexProvider.overrideWith(
      () => FakeDeviceIndex({
        1: local(InstallStatus.installed),
        2: local(InstallStatus.partial, update: true),
        3: local(InstallStatus.none),
      }),
    ),
  ];

  testWidgets('header, counts and back', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(games, overrides: states));
    await tester.pumpAndSettle();
    expect(find.text('Super Nintendo'), findsOneWidget);
    expect(find.text('3 games · 2 on device'), findsOneWidget);
    expect(find.text('Search in Super Nintendo'), findsOneWidget);
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
    await tester.tap(find.text('On device'));
    await tester.pumpAndSettle();
    expect(find.byType(GameTile), findsNWidgets(2));
    await tester.ensureVisible(
      find.text('Updates', skipOffstage: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Updates'));
    await tester.pumpAndSettle();
    expect(find.byType(GameTile), findsOneWidget);
    expect(find.text('Zelda'), findsWidgets);
    await tester.ensureVisible(find.text('All', skipOffstage: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All'));
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
    expect(find.text('Nothing matches'), findsOneWidget);
  });

  testWidgets('unknown system code shows a message', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          librarySnapshotProvider.overrideWith(
            (ref) async => const LibrarySnapshot(
              systems: [],
              games: [],
              manifest: [],
              fromCache: false,
              previousIds: {},
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unknown system'), findsOneWidget);
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
    expect(find.text('Retry'), findsOneWidget);
    expect(attempts, 1);
    await tester.tap(find.text('Retry'));
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
    expect(find.text('Game 1 from system'), findsOneWidget);
  });

  test('filterByQuery is case-insensitive', () {
    expect(filterByQuery(games, 'MAR').single.title, 'Mario');
    expect(filterByQuery(games, '  '), hasLength(3));
  });

  testWidgets('the pad starts on the first tile and reaches the chips', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(games, overrides: states));
    await tester.pumpAndSettle();
    expect(focusedAncestor<GameTile>()?.game.id, 1);
    expect(hasGlow(tester, find.byType(GameTile).first), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(hasGlow(tester, chip('All')), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(hasGlow(tester, chip('On device')), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(find.byType(GameTile), findsNWidgets(2));
  });

  testWidgets('Y focuses the search field, Escape hands the focus back', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          librarySnapshotProvider.overrideWith(
            (ref) async => LibrarySnapshot(
              systems: systems,
              games: games,
              manifest: [],
              fromCache: false,
              previousIds: const {},
            ),
          ),
          ...states,
        ],
        child: MaterialApp(
          home: GamepadShortcuts(
            currentIndex: 0,
            onTab: (_) {},
            child: const SystemScreen(code: 'snes'),
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

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(field.focusNode!.hasFocus, isFalse);
  });

  testWidgets('wide layout puts the search field into the header row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(const []));
    await tester.pumpAndSettle();
    final back = tester.getCenter(find.byKey(const Key('back-button')));
    final field = tester.getCenter(find.byType(SearchField));
    expect((field.dy - back.dy).abs(), lessThan(24));
    expect(field.dx, greaterThan(back.dx));
  });
}
