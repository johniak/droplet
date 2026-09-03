import 'package:flutter_test/flutter_test.dart';

/// `pumpAndSettle` returns once there are no frames scheduled — and an HTTP
/// request in flight doesn't schedule any, so the screen can still be a
/// skeleton. On a device we therefore wait in real time until the content
/// appears.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int seconds = 20,
}) async {
  for (var i = 0; i < seconds && !tester.any(finder); i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  expect(finder, findsWidgets, reason: "gave up waiting for $finder");
}
