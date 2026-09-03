import 'dart:io';

import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers.dart';
import 'package:path_provider/path_provider.dart';

const server = String.fromEnvironment('E2E_SERVER');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await const FlutterSecureStorage().deleteAll();
    final client = ApiClient(baseUrl: server);
    final token = await client.login('e2e', 'e2e-pass-123');
    await ApiClient(baseUrl: server, token: token).triggerScan();
    await Future<void>.delayed(const Duration(seconds: 5));
  });

  testWidgets('download then delete a game', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DropletApp()));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), server);
    await tester.enterText(fields.at(1), 'e2e');
    await tester.enterText(fields.at(2), 'e2e-pass-123');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle(const Duration(seconds: 10));

    // In e2e the base directory is the app's own documents directory:
    // needsAllFilesAccess() is false, so the app never raises the system
    // MANAGE_EXTERNAL_STORAGE dialog (a driver cannot tap it), and
    // --dart-define=E2E=true skips the notification prompt.
    final baseDir = '${(await getApplicationDocumentsDirectory()).path}/roms';
    await pumpUntil(tester, find.byKey(const Key('nav-settings')));
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Change'));
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('base-dir-field')), baseDir);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-library')));
    await tester.pumpAndSettle();

    await pumpUntil(tester, find.text('Super Mario World'));
    await tester.tap(find.text('Super Mario World').first);
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.textContaining('Download ·'));
    await tester.tap(find.textContaining('Download ·'));
    await tester.pumpAndSettle();

    var installed = false;
    for (var i = 0; i < 60 && !installed; i++) {
      await tester.pump(const Duration(seconds: 1));
      installed = tester.any(find.text('Installed'));
    }
    expect(installed, isTrue, reason: "download didn't finish within 60s");

    // The 'Installed' pill reads local state, but the file on disk is the
    // proof — without this assertion the test would also pass if the manager
    // merely reported success. The subdirectory is the system code (dirFor),
    // and inside it the game folder (M7: folder = game).
    final gameDir = Directory('$baseDir/snes/Super Mario World (USA)');
    final romFile = File('${gameDir.path}/Super Mario World (USA).sfc');
    expect(romFile.existsSync(), isTrue, reason: 'missing ROM at $romFile');
    expect(romFile.lengthSync(), 4); // size from the fixture library

    await pumpUntil(tester, find.text('Delete from device'));
    await tester.tap(find.text('Delete from device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(romFile.existsSync(), isFalse, reason: 'ROM was left behind after deletion');
    expect(
      gameDir.existsSync(),
      isFalse,
      reason: 'empty game folder was left behind after deletion',
    );
    expect(find.textContaining('Download ·'), findsOneWidget);
  });

  testWidgets('a game with a mod downloads the mod into mods/', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DropletApp()));
    await tester.pumpAndSettle();
    // Session and base directory survive from the first test (secure storage
    // and settings are persisted), so we go straight to the library.
    final baseDir = '${(await getApplicationDocumentsDirectory()).path}/roms';
    await pumpUntil(tester, find.byKey(const Key('nav-library')));
    await pumpUntil(tester, find.text('Hollow Knight'));
    await tester.tap(find.text('Hollow Knight').first);
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Copy path'));
    await pumpUntil(tester, find.textContaining('Download ·'));
    await tester.tap(find.textContaining('Download ·'));
    await tester.pumpAndSettle();

    var installed = false;
    for (var i = 0; i < 60 && !installed; i++) {
      await tester.pump(const Duration(seconds: 1));
      installed = tester.any(find.text('Installed'));
    }
    expect(installed, isTrue, reason: "download didn't finish within 60s");

    final modFile = File('$baseDir/switch/Hollow Knight/mods/Example Mod.zip');
    expect(modFile.existsSync(), isTrue, reason: 'mod missing at $modFile');
    expect(modFile.lengthSync(), 4);
    expect(
      File('$baseDir/switch/Hollow Knight/Hollow Knight [0100633007D48000][v0].nsp')
          .existsSync(),
      isTrue,
    );

    await pumpUntil(tester, find.text('Delete from device'));
    await tester.tap(find.text('Delete from device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(modFile.existsSync(), isFalse);
    expect(Directory('$baseDir/switch/Hollow Knight').existsSync(), isFalse,
        reason: 'game folder (with mods/) was left behind');
  });

  testWidgets('a bios pack downloads into bios/<pack> from Settings', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: DropletApp()));
    await tester.pumpAndSettle();
    // Session and base directory survive from the first test.
    final baseDir = '${(await getApplicationDocumentsDirectory()).path}/roms';

    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('RetroArch'));
    await tester.tap(find.text('RetroArch'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.textContaining('Download ·'));
    await tester.tap(find.textContaining('Download ·'));
    await tester.pumpAndSettle();

    var installed = false;
    for (var i = 0; i < 60 && !installed; i++) {
      await tester.pump(const Duration(seconds: 1));
      installed = tester.any(find.text('Installed'));
    }
    expect(installed, isTrue, reason: "download didn't finish within 60s");

    final packDir = Directory('$baseDir/bios/RetroArch');
    final biosFile = File('${packDir.path}/scph1001.bin');
    expect(biosFile.existsSync(), isTrue, reason: 'missing BIOS at $biosFile');
    expect(biosFile.lengthSync(), 4); // size from the fixture library

    await pumpUntil(tester, find.text('Delete from device'));
    await tester.tap(find.text('Delete from device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(biosFile.existsSync(), isFalse,
        reason: 'BIOS file was left behind after deletion');
    expect(packDir.existsSync(), isFalse,
        reason: 'empty pack folder was left behind after deletion');
  });
}
