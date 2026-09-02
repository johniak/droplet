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
                  Scaffold(body: Text('Gra ${s.pathParameters['id']}')),
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
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    final context = tester.element(find.byType(CachedNetworkImage));
    expect(image.placeholder!(context, image.imageUrl), isA<Widget>());
    expect(image.errorWidget!(context, image.imageUrl, 'boom'), isA<Widget>());
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
    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });

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
    expect(find.text('Gra 7'), findsOneWidget);
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

  testWidgets('InstallBadge reflects state and feeds id sets', (tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      _app(
        Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const Row(
              children: [
                InstallBadge(gameId: 1),
                InstallBadge(gameId: 2),
                InstallBadge(gameId: 3),
                InstallBadge(gameId: 4),
              ],
            );
          },
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
    expect(container.read(installedIdsProvider), {1, 2, 3});
    expect(container.read(updatableIdsProvider), {2});
  });

  testWidgets('Shelf caps cards and offers "Wszystkie"', (tester) async {
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
    expect(find.text('Wszystkie (14)'), findsOneWidget);
    await tester.tap(find.text('Wszystkie (14)'));
    expect(seeAll, 2);
    expect(find.text('G13'), findsNothing);
  });

  testWidgets('Shelf without overflow has no "Wszystkie" tile', (tester) async {
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
    expect(find.textContaining('Wszystkie'), findsNothing);
    // 'Tekken' bez okładki renderuje się dwa razy: raz jako tytuł na
    // placeholderze okładki, raz jako podpis kafla (tak jak w teście
    // GameTile powyżej).
    expect(find.text('Tekken'), findsWidgets);
  });

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
    expect(find.text('Gra 5'), findsOneWidget);
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
      _app(SearchField(hint: 'Szukaj', onChanged: (v) => last = v)),
    );
    await tester.enterText(find.byType(TextField), 'tek');
    expect(last, 'tek');
    expect(find.text('Szukaj'), findsOneWidget);
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
    await tester.tap(find.text('Ostatnio dodane'));
    await tester.pumpAndSettle();
    expect(container.read(sortProvider), LibrarySort.recentlyAdded);
  });
}
