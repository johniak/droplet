import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Everything the pad asks for that Flutter has no intent of its own for.
/// A and B, the D-pad and the page keys are already handled by `WidgetsApp`'s
/// default shortcuts, so they are deliberately absent here.
sealed class GamepadIntent extends Intent {
  const GamepadIntent();
}

class PreviousTabIntent extends GamepadIntent {
  const PreviousTabIntent();
}

class NextTabIntent extends GamepadIntent {
  const NextTabIntent();
}

class OpenSettingsIntent extends GamepadIntent {
  const OpenSettingsIntent();
}

/// Y — handled by the screens that own a search field (Home, System).
class FocusSearchIntent extends GamepadIntent {
  const FocusSearchIntent();
}

/// Start — handled by the game screen (Play, else Download).
class PrimaryActionIntent extends GamepadIntent {
  const PrimaryActionIntent();
}

/// The same mapping as [gamepadShortcuts], as a pure function — testable
/// without building a widget tree.
GamepadIntent? intentFor(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.gameButtonLeft1 => const PreviousTabIntent(),
  LogicalKeyboardKey.gameButtonRight1 => const NextTabIntent(),
  LogicalKeyboardKey.gameButtonSelect => const OpenSettingsIntent(),
  LogicalKeyboardKey.gameButtonY => const FocusSearchIntent(),
  LogicalKeyboardKey.gameButtonStart => const PrimaryActionIntent(),
  _ => null,
};

/// True while a text field holds the focus. The pad's buttons reach the
/// shell from above `EditableText`, whose own shortcuts cover none of them —
/// so Start and Select would fire mid-word without this guard.
bool isTyping() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context != null &&
      context.findAncestorWidgetOfExactType<EditableText>() != null;
}

const gamepadShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.gameButtonLeft1): PreviousTabIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonRight1): NextTabIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonSelect): OpenSettingsIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonY): FocusSearchIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonStart): PrimaryActionIntent(),
};

/// The shell-wide half of the pad: the tab shortcuts plus quiet fallbacks for
/// the two intents the screens own, so an unhandled Y or Start does nothing
/// instead of ringing the "no action found" bell.
///
/// `Shortcuts` only fire while the focus sits inside them — the `FocusScope`
/// makes sure something always does, even before a screen picks its own
/// starting point.
class GamepadShortcuts extends StatelessWidget {
  const GamepadShortcuts({
    super.key,
    required this.currentIndex,
    required this.onTab,
    required this.child,
  });

  final int currentIndex;
  final ValueChanged<int> onTab;
  final Widget child;

  static const _tabs = 3;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: gamepadShortcuts,
    child: Actions(
      actions: {
        PreviousTabIntent: CallbackAction<PreviousTabIntent>(
          onInvoke: (_) {
            onTab((currentIndex + _tabs - 1) % _tabs);
            return null;
          },
        ),
        NextTabIntent: CallbackAction<NextTabIntent>(
          onInvoke: (_) {
            onTab((currentIndex + 1) % _tabs);
            return null;
          },
        ),
        OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(
          onInvoke: (_) {
            if (!isTyping()) onTab(_tabs - 1);
            return null;
          },
        ),
        FocusSearchIntent: CallbackAction<FocusSearchIntent>(
          onInvoke: (_) => null,
        ),
        PrimaryActionIntent: CallbackAction<PrimaryActionIntent>(
          onInvoke: (_) => null,
        ),
      },
      child: FocusScope(autofocus: true, child: child),
    ),
  );
}
