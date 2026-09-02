import 'package:cached_network_image/cached_network_image.dart';
import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:droplet/features/downloads/downloads_screen.dart';
import 'package:droplet/features/library/library_screen.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:droplet/features/library/widgets/cover_image.dart';
import 'package:droplet/features/library/widgets/game_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _mario = GameSummary(
  id: 1,
  title: 'Super Mario World',
  systemCode: 'snes',
  hasCover: true,
  totalSize: 5,
);

GoRouter _router() => GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const LibraryScreen(),
          routes: [
            GoRoute(
              path: 'game/:id',
              builder: (_, s) =>
                  Scaffold(body: Text('Gra ${s.pathParameters['id']}')),
            ),
            GoRoute(
              path: 'settings',
              builder: (_, __) => const Scaffold(body: Text('Ustawienia')),
            ),
            GoRoute(
              path: 'downloads',
              builder: (_, __) => const DownloadsScreen(),
            ),
          ],
        ),
      ],
    );

Widget _app(List<GameSummary> games) => ProviderScope(
      overrides: [
        sessionRepositoryProvider
            .overrideWithValue(SessionRepository(MemoryKeyValueStore())),
        // The card only needs a client for cover URLs and headers.
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://nas:8000', token: 't'),
        ),
        gamesProvider.overrideWith((ref) async => games),
        systemsProvider.overrideWith((ref) async => <SystemModel>[]),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    );

void main() {
  testWidgets('tapping a card opens the game route', (tester) async {
    await tester.pumpWidget(_app([_mario]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(GameCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Gra 1'), findsOneWidget);
  });

  testWidgets('the settings action opens settings', (tester) async {
    await tester.pumpWidget(_app(const []));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ustawienia'), findsOneWidget);
  });

  testWidgets('pull to refresh reloads the games', (tester) async {
    await tester.pumpWidget(_app([_mario]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.fling(find.byType(GridView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(GameCard), findsWidgets);
  });

  testWidgets('a game with a cover renders the network image', (tester) async {
    await tester.pumpWidget(_app([_mario]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.imageUrl, contains('/api/games/1/cover'));
    expect(image.httpHeaders, containsPair('Authorization', 'Token t'));

    // The placeholder and error builders keep the grid intact while loading
    // or when the cover cannot be fetched.
    final context = tester.element(find.byType(CachedNetworkImage));
    expect(image.placeholder!(context, image.imageUrl), isA<Widget>());
    expect(
      image.errorWidget!(context, image.imageUrl, 'boom'),
      isA<Widget>(),
    );
  });

  testWidgets('CoverImage without a cover shows the title placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CoverImage(
          title: 'Bez okładki',
          url: '',
          headers: {},
          hasCover: false,
        ),
      ),
    );
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.text('Bez okładki'), findsOneWidget);
  });

  testWidgets('the downloads action opens the queue', (tester) async {
    await tester.pumpWidget(_app(const []));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Pobierania'), findsWidgets);
  });
}
