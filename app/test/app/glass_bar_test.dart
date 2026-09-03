import 'package:droplet/app/widgets/glass_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('three tabs, taps report index, badge shows count', (
    tester,
  ) async {
    final taps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GlassBar(
            currentIndex: 0,
            onTap: taps.add,
            badge: 2,
          ),
        ),
      ),
    );
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-downloads')));
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.tap(find.byKey(const Key('nav-library')));
    expect(taps, [1, 2, 0]);
  });

  testWidgets('no badge when nothing downloads', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GlassBar(currentIndex: 1, onTap: (_) {}),
        ),
      ),
    );
    expect(find.byType(Badge), findsNothing);
  });
}
