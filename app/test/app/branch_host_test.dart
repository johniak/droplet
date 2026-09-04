import 'package:droplet/app/branch_host.dart';
import 'package:droplet/app/input/gamepad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(int index, FocusNode a, FocusNode b) => MaterialApp(
  home: BranchHost(
    index: index,
    children: [
      Focus(focusNode: a, child: const SizedBox(width: 10, height: 10)),
      Focus(focusNode: b, child: const SizedBox(width: 10, height: 10)),
    ],
  ),
);

void main() {
  late FocusNode a;
  late FocusNode b;

  setUp(() {
    a = FocusNode(debugLabel: 'a');
    b = FocusNode(debugLabel: 'b');
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });

  tearDown(() {
    a.dispose();
    b.dispose();
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  testWidgets('the shown branch holds the focus from the start', (
    tester,
  ) async {
    await tester.pumpWidget(_host(0, a, b));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'branch 0');
  });

  testWidgets('a branch that already has the focus is left alone', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BranchHost(
          index: 0,
          children: [
            Focus(
              focusNode: a,
              autofocus: true,
              child: const SizedBox(width: 10, height: 10),
            ),
            Focus(focusNode: b, child: const SizedBox(width: 10, height: 10)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(a.hasPrimaryFocus, isTrue);
  });

  testWidgets('only the shown branch can take the focus', (tester) async {
    await tester.pumpWidget(_host(0, a, b));
    b.requestFocus();
    await tester.pump();
    expect(b.hasFocus, isFalse);
    a.requestFocus();
    await tester.pump();
    expect(a.hasPrimaryFocus, isTrue);
  });

  testWidgets('a switch hands the focus to the branch coming in', (
    tester,
  ) async {
    await tester.pumpWidget(_host(1, a, b));
    b.requestFocus();
    await tester.pump();
    expect(b.hasPrimaryFocus, isTrue);

    await tester.pumpWidget(_host(0, a, b));
    await tester.pumpAndSettle();
    expect(b.hasFocus, isFalse);
    a.requestFocus();
    await tester.pump();
    expect(a.hasPrimaryFocus, isTrue);

    // Back to branch 1: it remembers b.
    await tester.pumpWidget(_host(1, a, b));
    await tester.pumpAndSettle();
    expect(a.hasFocus, isFalse);
    expect(b.hasPrimaryFocus, isTrue);
  });

  testWidgets('in touch mode a switch only drops the old focus', (
    tester,
  ) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    await tester.pumpWidget(_host(1, a, b));
    b.requestFocus();
    await tester.pump();
    await tester.pumpWidget(_host(0, a, b));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_host(1, a, b));
    await tester.pumpAndSettle();
    expect(a.hasFocus, isFalse);
    expect(b.hasFocus, isFalse);
  });

  testWidgets('a remembered text field does not come back focused', (
    tester,
  ) async {
    Widget host(int index) => MaterialApp(
      home: BranchHost(
        index: index,
        children: [
          Focus(focusNode: a, child: const SizedBox(width: 10, height: 10)),
          Material(child: TextField(focusNode: b)),
        ],
      ),
    );
    await tester.pumpWidget(host(1));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(isTyping(), isTrue);

    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    expect(isTyping(), isFalse);

    await tester.pumpWidget(host(1));
    await tester.pumpAndSettle();
    expect(isTyping(), isFalse);
    expect(b.hasFocus, isFalse);
  });

  testWidgets('a rebuild with the same index leaves the focus alone', (
    tester,
  ) async {
    await tester.pumpWidget(_host(0, a, b));
    a.requestFocus();
    await tester.pump();
    await tester.pumpWidget(_host(0, a, b));
    await tester.pumpAndSettle();
    expect(a.hasPrimaryFocus, isTrue);
  });
}
