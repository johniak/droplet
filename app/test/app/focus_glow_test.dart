import 'package:droplet/app/theme.dart';
import 'package:droplet/app/widgets/focus_glow.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

BoxDecoration _ring(WidgetTester tester, Finder inside) =>
    tester.widget<DecoratedBox>(
      find.descendant(
        of: inside,
        matching: find.byKey(const Key('focus-glow-ring')),
      ),
    ).decoration as BoxDecoration;

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildTheme(), home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('a tap calls onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(FocusGlow(onTap: () => taps++, child: const Text('Go'))),
    );
    await tester.tap(find.text('Go'));
    expect(taps, 1);
  });

  testWidgets('focus draws the ring, gameButtonA activates', (tester) async {
    var taps = 0;
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _wrap(
        FocusGlow(
          focusNode: node,
          onTap: () => taps++,
          child: const Text('Go'),
        ),
      ),
    );
    final glow = find.byType(FocusGlow);
    expect(_ring(tester, glow).border, isNull);

    node.requestFocus();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);
    final decoration = _ring(tester, glow);
    expect(decoration.border, isNotNull);
    expect(decoration.boxShadow, isNotNull);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.04);

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('autofocus takes the focus on the first frame', (tester) async {
    await tester.pumpWidget(
      _wrap(FocusGlow(autofocus: true, onTap: () {}, child: const Text('Go'))),
    );
    await tester.pumpAndSettle();
    expect(_ring(tester, find.byType(FocusGlow)).border, isNotNull);
  });

  testWidgets('focus scrolls the item into view', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          height: 400,
          width: 300,
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < 20; i++)
                  SizedBox(
                    height: 100,
                    child: FocusGlow(
                      focusNode: i == 19 ? node : null,
                      onTap: () {},
                      child: Text('item $i'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final last = find.text('item 19');
    expect(tester.getRect(last).top, greaterThan(600));

    node.requestFocus();
    await tester.pumpAndSettle();
    final rect = tester.getRect(last);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(600));
  });

  testWidgets('focus outside a Scrollable is harmless', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _wrap(FocusGlow(focusNode: node, onTap: () {}, child: const Text('Go'))),
    );
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled takes no focus and ignores taps', (tester) async {
    var taps = 0;
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _wrap(
        FocusGlow(
          enabled: false,
          focusNode: node,
          scale: 1,
          onTap: () => taps++,
          child: const Text('Go'),
        ),
      ),
    );
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isFalse);
    expect(_ring(tester, find.byType(FocusGlow)).border, isNull);
    await tester.tap(find.text('Go'), warnIfMissed: false);
    expect(taps, 0);
  });
}
