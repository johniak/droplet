import 'dart:io';

import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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
    await tester.tap(find.text('Zaloguj'));
    await tester.pumpAndSettle(const Duration(seconds: 10));

    // In e2e the base directory is the app's own documents directory:
    // needsAllFilesAccess() is false, so the app never raises the system
    // MANAGE_EXTERNAL_STORAGE dialog (a driver cannot tap it), and
    // --dart-define=E2E=true skips the notification prompt.
    final baseDir = '${(await getApplicationDocumentsDirectory()).path}/roms';
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zmień'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('base-dir-field')), baseDir);
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-library')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Super Mario World').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Pobierz ·'));
    await tester.pumpAndSettle();

    var installed = false;
    for (var i = 0; i < 60 && !installed; i++) {
      await tester.pump(const Duration(seconds: 1));
      installed = tester.any(find.text('Zainstalowana'));
    }
    expect(installed, isTrue, reason: 'pobieranie nie zakończyło się w 60 s');

    // Pigułka „Zainstalowana" czyta stan lokalny, ale to plik na dysku jest
    // dowodem — bez tej asercji test przeszedłby też, gdyby manager tylko
    // zameldował sukces. Domyślny podkatalog to kod systemu (dirFor).
    final romFile = File('$baseDir/snes/Super Mario World (USA).sfc');
    expect(romFile.existsSync(), isTrue, reason: 'brak ROM-u pod $romFile');
    expect(romFile.lengthSync(), 4); // rozmiar z fixture-library

    await tester.tap(find.text('Usuń z urządzenia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuń'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(romFile.existsSync(), isFalse, reason: 'ROM został po usunięciu');
    expect(find.textContaining('Pobierz ·'), findsOneWidget);
  });
}
