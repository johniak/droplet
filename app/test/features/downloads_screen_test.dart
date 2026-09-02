import 'package:droplet/core/downloads/download_manager.dart';
import 'package:droplet/features/downloads/downloads_screen.dart';
import 'package:droplet/features/downloads/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../fakes/fake_downloader_port.dart';
import '../fakes/fake_permissions_port.dart';

GoRouter _router() => GoRouter(
      initialLocation: '/downloads',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Home')),
          routes: [
            GoRoute(
              path: 'downloads',
              builder: (_, __) => const DownloadsScreen(),
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

Widget _screen(List<GameProgress> active, DownloadManager manager) =>
    ProviderScope(
      overrides: [
        activeDownloadsProvider.overrideWith((ref) => active),
        downloadManagerProvider.overrideWithValue(manager),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    );

GameProgress at(
  GameProgressStatus status, {
  int id = 7,
  double progress = 0.5,
  int done = 500,
  int total = 1000,
  int? speed,
}) =>
    GameProgress(
      gameId: id,
      title: 'Mario',
      systemCode: 'snes',
      hasCover: false,
      progress: progress,
      status: status,
      bytesDone: done,
      bytesTotal: total,
      speedBytesPerSec: speed,
    );

void main() {
  late FakeDownloaderPort port;
  late DownloadManager manager;

  setUp(() {
    port = FakeDownloaderPort();
    manager = DownloadManager(
      port,
      FakePermissionsPort(granted: true),
      onGameChanged: (_) {},
    );
  });

  tearDown(() => manager.dispose());

  test('progressSubtitle per status', () {
    expect(progressSubtitle(at(GameProgressStatus.running, speed: 2048)),
        '500 B / 1000 B · 2.0 KB/s');
    expect(progressSubtitle(at(GameProgressStatus.running)), '500 B / 1000 B');
    expect(progressSubtitle(at(GameProgressStatus.paused)),
        'Wstrzymane · 500 B / 1000 B');
    expect(progressSubtitle(at(GameProgressStatus.failed)),
        'Błąd pobierania — ponów');
    expect(progressSubtitle(at(GameProgressStatus.complete)), 'Gotowe · 1000 B');
  });

  testWidgets('empty state', (tester) async {
    await tester.pumpWidget(_screen(const [], manager));
    await tester.pumpAndSettle();
    expect(find.text('Brak pobierań'), findsOneWidget);
    expect(find.text('Brak aktywnych'), findsOneWidget);
  });

  testWidgets('header sums what is left; card opens the game', (tester) async {
    await tester.pumpWidget(
      _screen([at(GameProgressStatus.running), at(GameProgressStatus.paused, id: 8)], manager),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 aktywnych · pozostało 1000 B'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    await tester.tap(find.text('Mario').first);
    await tester.pumpAndSettle();
    expect(find.text('Gra 7'), findsOneWidget);
  });

  testWidgets('pause / cancel / resume / retry reach the manager', (
    tester,
  ) async {
    await tester.pumpWidget(_screen([at(GameProgressStatus.running)], manager));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(manager.progress, isEmpty);

    // Riverpod 3 does not re-run a Provider.overrideWith closure when the
    // ProviderScope above it is merely rebuilt with a new override — its
    // element only reacts to overrideWithValue changes. Force a fresh
    // ProviderContainer per pumpWidget so the next override actually applies.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_screen([at(GameProgressStatus.paused)], manager));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_screen([at(GameProgressStatus.failed)], manager));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
  });

  testWidgets('finished section and clear', (tester) async {
    await tester.pumpWidget(
      _screen([at(GameProgressStatus.complete), at(GameProgressStatus.failed, id: 9)], manager),
    );
    await tester.pumpAndSettle();
    expect(find.text('Zakończone'), findsOneWidget);
    expect(find.text('Gotowe · 1000 B'), findsOneWidget);
    await tester.tap(find.text('Wyczyść'));
    await tester.pumpAndSettle();
    // Manager had nothing of its own; the tap must not throw.
    expect(manager.progress, isEmpty);
  });

  test('activeCountProvider counts running and paused', () {
    final container = ProviderContainer(
      overrides: [
        activeDownloadsProvider.overrideWith(
          (ref) => [
            at(GameProgressStatus.running),
            at(GameProgressStatus.paused, id: 8),
            at(GameProgressStatus.complete, id: 9),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(activeCountProvider), 2);
  });
}
