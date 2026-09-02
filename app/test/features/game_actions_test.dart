import 'dart:io';

import 'package:droplet/app/widgets/primary_button.dart';
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/core/downloads/storage_settings.dart';
import 'package:droplet/core/platform/downloader_port.dart';
import 'package:droplet/features/game/delete_dialog.dart';
import 'package:droplet/features/game/game_detail_screen.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../fakes/fake_downloader_port.dart';

const detail = GameDetail(
  id: 7,
  title: 'Mario',
  systemCode: 'snes',
  systemName: 'SNES',
  hasCover: false,
  totalSize: 1024,
  folder: 'Mario',
  files: [
    GameFileModel(
      id: 1,
      name: 'm.sfc',
      relativePath: 'snes/m.sfc',
      role: FileRole.base,
      discNumber: null,
      version: '',
      size: 1024,
    ),
  ],
);

GoRouter _router() => GoRouter(
      initialLocation: '/game/7',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Home')),
          routes: [
            GoRoute(
              path: 'game/:id',
              builder: (_, s) =>
                  GameDetailScreen(gameId: int.parse(s.pathParameters['id']!)),
            ),
          ],
        ),
      ],
    );

Widget build(LocalGameState state) => ProviderScope(
      overrides: [
        gameDetailProvider(7).overrideWith((ref) async => detail),
        localStateProvider(7).overrideWith((ref) async => state),
        downloaderPortProvider.overrideWithValue(FakeDownloaderPort()),
        storageSettingsProvider.overrideWith(
          (ref) async => StorageSettings('/roms', const {}),
        ),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    );

void main() {
  testWidgets('not installed shows download with size', (tester) async {
    await tester.pumpWidget(
      build(
        const LocalGameState(
          status: InstallStatus.none,
          updateAvailable: false,
          missing: [],
          presentPaths: [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pobierz · 1.0 KB'), findsOneWidget);
    expect(find.textContaining('1.0 KB'), findsWidgets);
  });

  testWidgets('installed shows delete', (tester) async {
    await tester.pumpWidget(
      build(
        const LocalGameState(
          status: InstallStatus.installed,
          updateAvailable: false,
          missing: [],
          presentPaths: ['/roms/snes/m.sfc'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Usuń z urządzenia'), findsOneWidget);
    expect(find.text('Zainstalowana'), findsOneWidget);
  });

  testWidgets('update available shows update button', (tester) async {
    await tester.pumpWidget(
      build(
        const LocalGameState(
          status: InstallStatus.partial,
          updateAvailable: true,
          missing: [],
          presentPaths: ['/roms/snes/m.sfc'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Pobierz aktualizację'), findsOneWidget);
  });

  testWidgets('delete dialog removes only listed files', (tester) async {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    final rom = File('${dir.path}/m.sfc')..writeAsStringSync('rom');
    final save = File('${dir.path}/m.srm')..writeAsStringSync('save');
    await tester.pumpWidget(
      build(
        LocalGameState(
          status: InstallStatus.installed,
          updateAvailable: false,
          missing: const [],
          presentPaths: [rom.path],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuń z urządzenia'));
    await tester.pumpAndSettle();
    expect(find.textContaining('nie zostaną usunięte'), findsOneWidget);
    await tester.tap(find.text('Usuń'));
    await tester.pumpAndSettle();
    expect(rom.existsSync(), false);
    expect(save.existsSync(), true);
  });

  testWidgets('the delete dialog can be dismissed', (tester) async {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    final rom = File('${dir.path}/m.sfc')..writeAsStringSync('rom');
    await tester.pumpWidget(
      build(
        LocalGameState(
          status: InstallStatus.installed,
          updateAvailable: false,
          missing: const [],
          presentPaths: [rom.path],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuń z urządzenia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(rom.existsSync(), true);
  });

  testWidgets('files can be deselected, which changes the size', (
    tester,
  ) async {
    await tester.pumpWidget(
      build(
        const LocalGameState(
          status: InstallStatus.none,
          updateAvailable: false,
          missing: [],
          presentPaths: [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('Pobierz · 0 B'), findsOneWidget);
    // Nothing left to fetch: the button is disabled, not just relabeled.
    expect(
      tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
      isNull,
    );
    // ...and selecting it again brings the size back and re-enables it.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('Pobierz · 1.0 KB'), findsOneWidget);
    expect(
      tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
      isNotNull,
    );
  });

  test('deleteLocalFiles ignores missing paths', () async {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    await deleteLocalFiles(['${dir.path}/nie-ma.sfc']);
  });
}
