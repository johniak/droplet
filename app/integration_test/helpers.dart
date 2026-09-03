import 'package:flutter_test/flutter_test.dart';

/// `pumpAndSettle` wraca, gdy nie ma zaplanowanych klatek — a zapytanie HTTP
/// w locie żadnej nie planuje, więc ekran potrafi być jeszcze szkieletem.
/// Na urządzeniu czekamy więc realnym czasem, aż pojawi się treść.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int seconds = 20,
}) async {
  for (var i = 0; i < seconds && !tester.any(finder); i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  expect(finder, findsWidgets, reason: 'nie doczekałem się $finder');
}
