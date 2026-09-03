import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/library/widgets/cover_image.dart';
import 'package:droplet/features/library/widgets/game_tile.dart';
import 'package:droplet/features/library/widgets/games_grid.dart';
import 'package:droplet/features/library/widgets/install_badge.dart';
import 'package:droplet/features/library/widgets/search_field.dart';
import 'package:droplet/features/library/widgets/shelf.dart';
import 'package:droplet/features/library/widgets/sort_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GameSummary g(int id, String title, {bool cover = false}) => GameSummary(
      id: id,
      title: title,
      systemCode: 'snes',
      hasCover: cover,
      totalSize: 1024,
      folder: title,
    );

LocalGameState local(InstallStatus status, {bool update = false}) =>
    LocalGameState(
      status: status,
      updateAvailable: update,
      missing: const [],
      presentPaths: const [],
    );

GoRouter _router(Widget home) => GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(body: home),
          routes: [
            GoRoute(
              path: 'game/:id',
              builder: (_, s) =>
                  Scaffold(body: Text('Game ${s.pathParameters['id']}')),
            ),
            GoRoute(
              path: 'x/:id',
              builder: (_, s) =>
                  Scaffold(body: Text('X ${s.pathParameters['id']}')),
            ),
          ],
        ),
      ],
    );

Widget _app(Widget home, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://nas:8000', token: 't'),
        ),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: _router(home)),
    );

void main() {
  testWidgets('CoverImage: placeholder without cover, network with cover', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Row(
          children: [
            SizedBox(
              width: 100,
              height: 130,
              child: CoverImage(
                title: 'Mario',
                url: '',
                headers: {},
                hasCover: false,
              ),
            ),
            SizedBox(
              width: 100,
              height: 130,
              child: CoverImage(
                title: 'Zelda',
                url: 'http://nas:8000/c.png',
                headers: {},
                hasCover: true,
              ),
            ),
          ],
        ),
      ),
    );
    expect(find.text('Mario'), findsOneWidget);
    // Blurred backdrop + the sharp, contained box on top.
    expect(find.byType(CachedNetworkImage), findsNWidgets(2));
    expect(find.byType(ImageFiltered), findsOneWidget);
    for (final element in find.byType(CachedNetworkImage).evaluate()) {
      final image = element.widget as CachedNetworkImage;
      expect(image.placeholder!(element, image.imageUrl), isA<Widget>());
      expect(image.errorWidget!(element, image.imageUrl, 'boom'), isA<Widget>());
    }
    final fits = [
      for (final e in find.byType(CachedNetworkImage).evaluate())
        (e.widget as CachedNetworkImage).fit,
    ];
    expect(fits, [BoxFit.cover, BoxFit.contain]);
  });

  testWidgets('CoverImage with a cropping fit needs no backdrop', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const SizedBox(
          width: 100,
          height: 130,
          child: CoverImage(
            title: 'Zelda',
            url: 'http://nas:8000/c.png',
            headers: {},
            hasCover: true,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('GameTile with a cover requests the network image', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 180,
          height: 300,
          child: GameTile(game: g(9, 'Zelda', cover: true)),
        ),
        overrides: [
          localStateProvider(9).overrideWith(
            (ref) async => local(InstallStatus.none),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    // backdrop + sharp image, both pointing at the same cover URL
    expect(find.byType(CachedNetworkImage), findsNWidgets(2));
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage).last,
    );
    expect(image.imageUrl, contains('/api/games/9/cover'));
    expect(image.httpHeaders, containsPair('Authorization', 'Token t'));
  });

  testWidgets(
    'GameTile and ShelfCard without a cover never touch apiClientProvider',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStateProvider(11).overrideWith(
              (ref) async => local(InstallStatus.none),
            ),
            localStateProvider(12).overrideWith(
              (ref) async => local(InstallStatus.none),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    width: 180,
                    height: 300,
                    child: GameTile(game: g(11, 'Sonic')),
                  ),
                  ShelfCard(game: g(12, 'Rayman')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sonic'), findsWidgets);
      expect(find.text('Rayman'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('GameTile shows title and size and navigates', (tester) async {
    await tester.pumpWidget(
      _app(
        SizedBox(width: 180, height: 300, child: GameTile(game: g(7, 'Mario'))),
        overrides: [
          localStateProvider(7).overrideWith(
            (ref) async => local(InstallStatus.none),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mario'), findsWidgets);
    expect(find.text('1.0 KB'), findsOneWidget);
    await tester.tap(find.byType(GameTile));
    await tester.pumpAndSettle();
    expect(find.text('Game 7'), findsOneWidget);
  });

  testWidgets('GameTile honours a custom route', (tester) async {
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 180,
          height: 300,
          child: GameTile(game: g(7, 'Mario'), route: '/x/7'),
        ),
        overrides: [
          localStateProvider(7).overrideWith(
            (ref) async => local(InstallStatus.none),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GameTile));
    await tester.pumpAndSettle();
    expect(find.text('X 7'), findsOneWidget);
  });

  testWidgets('InstallBadge reflects state', (tester) async {
    await tester.pumpWidget(
      _app(
        const Row(
          children: [
            InstallBadge(gameId: 1),
            InstallBadge(gameId: 2),
            InstallBadge(gameId: 3),
            InstallBadge(gameId: 4),
          ],
        ),
        overrides: [
          localStateProvider(1).overrideWith(
            (ref) async => local(InstallStatus.installed),
          ),
          localStateProvider(2).overrideWith(
            (ref) async => local(InstallStatus.partial, update: true),
          ),
          localStateProvider(3).overrideWith(
            (ref) async => local(InstallStatus.partial),
          ),
          localStateProvider(4).overrideWith(
            (ref) async => local(InstallStatus.none),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
  });

  testWidgets(
    'InstallBadge survives being culled in the frame its state resolves',
    (tester) async {
      // A badge inside a scrolled list whose local state resolves in the very
      // frame the list also scrolls it out of the cache extent: `ListView`'s
      // layout pass unmounts the culled item's element while the provider is
      // delivering its value.
      final completer = Completer<LocalGameState>();
      final controller = ScrollController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://nas:8000', token: 't'),
            ),
            localStateProvider(0).overrideWith((ref) async => completer.future),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 300,
                child: ListView.builder(
                  controller: controller,
                  itemExtent: 50,
                  itemCount: 500,
                  itemBuilder: (_, i) => SizedBox(
                    height: 50,
                    child: i == 0
                        ? const InstallBadge(gameId: 0)
                        : Text('item $i'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      completer.complete(local(InstallStatus.installed));
      // Scrolling far enough evicts item 0 (and its badge) from the cache
      // extent during this same frame's layout pass.
      controller.jumpTo(100000);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Shelf caps cards and offers "All"', (tester) async {
    var seeAll = 0;
    final games = [for (var i = 1; i <= 14; i++) g(i, 'G$i')];
    await tester.pumpWidget(
      _app(
        Shelf(
          title: 'SNES',
          trailing: '14 ›',
          games: games,
          onSeeAll: () => seeAll++,
        ),
        overrides: [
          for (final game in games)
            localStateProvider(game.id).overrideWith(
              (ref) async => local(InstallStatus.none),
            ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('SNES'), findsOneWidget);
    await tester.tap(find.text('14 ›'));
    expect(seeAll, 1);
    await tester.drag(find.byType(ListView), const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(find.text('All (14)'), findsOneWidget);
    await tester.tap(find.text('All (14)'));
    expect(seeAll, 2);
    expect(find.text('G13'), findsNothing);
  });

  testWidgets('Shelf without overflow has no "All" tile', (tester) async {
    await tester.pumpWidget(
      _app(
        Shelf(title: 'PSX', games: [g(1, 'Tekken')]),
        overrides: [
          localStateProvider(1).overrideWith(
            (ref) async => local(InstallStatus.none),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('All'), findsNothing);
    // 'Tekken' without a cover renders twice: once as the title on the
    // cover placeholder, once as the tile caption (same as in the GameTile
    // test above).
    expect(find.text('Tekken'), findsNWidgets(2));
  });

  testWidgets(
    'Shelf header tap fires onSeeAll from either the title or the trailing text',
    (tester) async {
      var seeAll = 0;
      await tester.pumpWidget(
        _app(
          Shelf(
            title: 'Nintendo Switch',
            trailing: '3 ›',
            games: [g(1, 'Mario')],
            onSeeAll: () => seeAll++,
          ),
          overrides: [
            localStateProvider(1).overrideWith(
              (ref) async => local(InstallStatus.none),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nintendo Switch'));
      expect(seeAll, 1);
      await tester.tap(find.text('3 ›'));
      expect(seeAll, 2);
    },
  );

  testWidgets(
    'Shelf without onSeeAll leaves the title non-interactive',
    (tester) async {
      await tester.pumpWidget(
        _app(
          Shelf(title: 'PSX', games: [g(1, 'Tekken')]),
          overrides: [
            localStateProvider(1).overrideWith(
              (ref) async => local(InstallStatus.none),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      // No onSeeAll means no navigation to assert — this only needs to not
      // throw when the header (still just a plain title) is tapped.
      await tester.tap(find.text('PSX'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ShelfCard navigates on tap', (tester) async {
    await tester.pumpWidget(
      _app(
        Shelf(title: 'SNES', games: [g(5, 'Mario')]),
        overrides: [
          localStateProvider(5).overrideWith(
            (ref) async => local(InstallStatus.none),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ShelfCard));
    await tester.pumpAndSettle();
    expect(find.text('Game 5'), findsOneWidget);
  });

  testWidgets('GamesGrid lays out tiles', (tester) async {
    await tester.pumpWidget(
      _app(
        GamesGrid(games: [g(1, 'A'), g(2, 'B')]),
        overrides: [
          for (final id in [1, 2])
            localStateProvider(id).overrideWith(
              (ref) async => local(InstallStatus.none),
            ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GameTile), findsNWidgets(2));
  });

  testWidgets('GamesGrid resolves its bottom padding from MediaQuery', (
    tester,
  ) async {
    // The shell has extendBody: true, so padding.bottom in this branch is
    // already the bar's height plus the system inset — the grid only adds
    // 16 on top.
    await tester.pumpWidget(
      _app(
        const MediaQuery(
          data: MediaQueryData(padding: EdgeInsets.only(bottom: 120)),
          child: GamesGrid(games: []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect((grid.padding! as EdgeInsets).bottom, 136);
  });

  testWidgets('GamesGrid honours an explicit padding', (tester) async {
    await tester.pumpWidget(
      _app(
        const GamesGrid(games: [], padding: EdgeInsets.all(4)),
      ),
    );
    await tester.pumpAndSettle();
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.padding, const EdgeInsets.all(4));
  });

  testWidgets('CoverThumb without a badge renders no InstallBadge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Row(
          children: [
            SizedBox(width: 40, child: CoverThumb(game: g(1, 'A'))),
            SizedBox(
              width: 40,
              child: CoverThumb(game: g(2, 'B'), showBadge: false),
            ),
          ],
        ),
        overrides: [
          for (final id in [1, 2])
            localStateProvider(id).overrideWith(
              (ref) async => local(InstallStatus.installed),
            ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InstallBadge), findsOneWidget);
    expect(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is CoverThumb && !w.showBadge,
        ),
        matching: find.byType(InstallBadge),
      ),
      findsNothing,
    );
  });

  testWidgets('GamesGrid honours routeFor for custom routes', (tester) async {
    await tester.pumpWidget(
      _app(
        GamesGrid(
          games: [g(1, 'A')],
          routeFor: (id) => '/x/$id',
        ),
        overrides: [
          localStateProvider(1).overrideWith(
            (ref) async => local(InstallStatus.none),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GameTile));
    await tester.pumpAndSettle();
    expect(find.text('X 1'), findsOneWidget);
  });

  testWidgets('SearchField forwards input', (tester) async {
    String? last;
    await tester.pumpWidget(
      _app(SearchField(hint: 'Search', onChanged: (v) => last = v)),
    );
    await tester.enterText(find.byType(TextField), 'tek');
    expect(last, 'tek');
    expect(find.text('Search'), findsOneWidget);
  });

  testWidgets('SortMenu switches the sort provider', (tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      _app(
        Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const SortMenu();
          },
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recently added'));
    await tester.pumpAndSettle();
    expect(container.read(sortProvider), LibrarySort.recentlyAdded);
  });

  testWidgets('a Switch tile is square, a SNES tile is portrait', (
    tester,
  ) async {
    GameSummary g(int id, String system) => GameSummary(
          id: id,
          title: 'G$id',
          systemCode: system,
          hasCover: false,
          totalSize: 1,
          folder: 'G$id',
        );
    await tester.pumpWidget(
      _app(
        Row(
          children: [
            SizedBox(width: 100, child: CoverThumb(game: g(1, 'switch'))),
            SizedBox(width: 100, child: CoverThumb(game: g(2, 'snes'))),
          ],
        ),
      ),
    );
    final ratios = [
      for (final e in find.byType(AspectRatio).evaluate())
        (e.widget as AspectRatio).aspectRatio,
    ];
    expect(ratios, [1, 3 / 4]);
  });
}
