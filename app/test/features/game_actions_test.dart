import 'dart:io';

import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/features/game/delete_dialog.dart';
import 'package:droplet/features/game/game_detail_screen.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const detail = GameDetail(
  id: 7,
  title: 'Mario',
  systemCode: 'snes',
  systemName: 'SNES',
  hasCover: false,
  totalSize: 1024,
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

Widget build(LocalGameState state) => ProviderScope(
      overrides: [
        gameDetailProvider(7).overrideWith((ref) async => detail),
        localStateProvider(7).overrideWith((ref) async => state),
      ],
      child: const MaterialApp(home: GameDetailScreen(gameId: 7)),
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
    expect(find.textContaining('Pobierz'), findsOneWidget);
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
    expect(find.text('Pobierz aktualizację'), findsOneWidget);
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
    expect(find.textContaining('Pobierz (0 B)'), findsOneWidget);
    // ...and selecting it again brings the size back.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Pobierz (1.0 KB)'), findsOneWidget);
  });

  test('deleteLocalFiles ignores missing paths', () async {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    await deleteLocalFiles(['${dir.path}/nie-ma.sfc']);
  });
}
