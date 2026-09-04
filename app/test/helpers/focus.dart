import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// True when the `FocusGlow` inside [container] draws its accent ring, i.e.
/// when it holds the focus.
bool hasGlow(WidgetTester tester, Finder container) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: container,
          matching: find.byKey(const Key('focus-glow-ring')),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).border != null;
}

/// The widget of type [T] that actually holds the primary focus, if any —
/// the ring proves a repaint, this proves where the focus is.
T? focusedAncestor<T extends Widget>() => FocusManager
    .instance
    .primaryFocus
    ?.context
    ?.findAncestorWidgetOfExactType<T>();
