import 'package:droplet/app/input/gamepad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('intentFor maps the five global buttons and nothing else', () {
    expect(
      intentFor(LogicalKeyboardKey.gameButtonLeft1),
      isA<PreviousTabIntent>(),
    );
    expect(
      intentFor(LogicalKeyboardKey.gameButtonRight1),
      isA<NextTabIntent>(),
    );
    expect(
      intentFor(LogicalKeyboardKey.gameButtonSelect),
      isA<OpenSettingsIntent>(),
    );
    expect(intentFor(LogicalKeyboardKey.gameButtonY), isA<FocusSearchIntent>());
    expect(
      intentFor(LogicalKeyboardKey.gameButtonStart),
      isA<PrimaryActionIntent>(),
    );
    expect(intentFor(LogicalKeyboardKey.keyA), isNull);
    expect(intentFor(LogicalKeyboardKey.gameButtonA), isNull);
  });

  test('the Shortcuts map covers exactly the mapped buttons', () {
    expect(gamepadShortcuts, hasLength(5));
  });

  Future<int?> pressFrom(WidgetTester tester, int index, LogicalKeyboardKey key) async {
    int? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: GamepadShortcuts(
          currentIndex: index,
          onTab: (i) => tapped = i,
          child: const Scaffold(body: Text('body')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
    return tapped;
  }

  testWidgets('R1 and L1 cycle through the three tabs', (tester) async {
    expect(await pressFrom(tester, 0, LogicalKeyboardKey.gameButtonRight1), 1);
    expect(await pressFrom(tester, 2, LogicalKeyboardKey.gameButtonRight1), 0);
    expect(await pressFrom(tester, 0, LogicalKeyboardKey.gameButtonLeft1), 2);
    expect(await pressFrom(tester, 2, LogicalKeyboardKey.gameButtonLeft1), 1);
  });

  testWidgets('Select opens the settings tab', (tester) async {
    expect(await pressFrom(tester, 0, LogicalKeyboardKey.gameButtonSelect), 2);
  });

  testWidgets('Y and Start are swallowed when no screen handles them', (
    tester,
  ) async {
    expect(await pressFrom(tester, 0, LogicalKeyboardKey.gameButtonY), isNull);
    expect(
      await pressFrom(tester, 0, LogicalKeyboardKey.gameButtonStart),
      isNull,
    );
  });

  testWidgets('Select is ignored while a text field has the focus', (
    tester,
  ) async {
    int? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: GamepadShortcuts(
          currentIndex: 0,
          onTab: (i) => tapped = i,
          child: const Scaffold(body: TextField(autofocus: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(isTyping(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonSelect);
    await tester.pumpAndSettle();
    expect(tapped, isNull);
  });

  testWidgets('a screen below the shell handles Y itself', (tester) async {
    var searched = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GamepadShortcuts(
          currentIndex: 0,
          onTab: (_) {},
          child: Actions(
            actions: {
              FocusSearchIntent: CallbackAction<FocusSearchIntent>(
                onInvoke: (_) {
                  searched++;
                  return null;
                },
              ),
            },
            // The handler is found by walking up from whatever holds the
            // focus, so a screen only gets its intents while the focus sits
            // inside it (spec §2.2).
            child: const Scaffold(
              body: Focus(autofocus: true, child: Text('body')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonY);
    await tester.pumpAndSettle();
    expect(searched, 1);
  });
}
