import 'package:droplet/app/widgets/pulse_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pulse box animates opacity', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PulseBox(width: 100, height: 100))),
    );
    final first = tester
        .widget<AnimatedOpacity>(find.byType(AnimatedOpacity))
        .opacity;
    await tester.pump(const Duration(milliseconds: 950));
    final second = tester
        .widget<AnimatedOpacity>(find.byType(AnimatedOpacity))
        .opacity;
    expect(first == second, false);
    // Stop the looping timer so the test can finish.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
  });
}
