import 'package:flutter/material.dart';

import '../tokens.dart';

/// One wrapper for every interactive surface the gamepad has to reach: it is
/// focusable, it activates on A (`ActivateIntent`) and on touch, it draws a
/// visible accent ring while focused, and it scrolls itself into view when
/// the focus lands on it.
///
/// The ring follows plain focus rather than Flutter's "focus highlight" mode:
/// on Android that mode starts out as `touch`, which would leave a pad-driven
/// app with no visible focus at all until a key is pressed.
class FocusGlow extends StatefulWidget {
  const FocusGlow({
    super.key,
    required this.onTap,
    required this.child,
    this.autofocus = false,
    this.focusNode,
    this.borderRadius = kRadiusCover,
    this.scale = 1.04,
    this.enabled = true,
  });

  /// Null disables the surface just like `enabled: false` does — a button
  /// with nothing to do must not swallow the focus.
  final VoidCallback? onTap;
  final Widget child;
  final bool autofocus;
  final FocusNode? focusNode;
  final double borderRadius;

  /// How much the surface grows while focused — 1.0 for list rows, where a
  /// growing row would push its neighbours around.
  final double scale;

  final bool enabled;

  @override
  State<FocusGlow> createState() => _FocusGlowState();
}

class _FocusGlowState extends State<FocusGlow> {
  bool _focused = false;

  bool get _enabled => widget.enabled && widget.onTap != null;

  void _onFocusChange(bool focused) {
    setState(() => _focused = focused);
    if (!focused) return;
    if (!mounted) return;
    // A surface outside any viewport (a bottom bar, a dialog) has nothing to
    // scroll — asking anyway would throw.
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    return FocusableActionDetector(
      enabled: _enabled,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      onFocusChange: _onFocusChange,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: AnimatedScale(
        scale: _focused ? widget.scale : 1,
        duration: const Duration(milliseconds: 150),
        child: DecoratedBox(
          key: const Key('focus-glow-ring'),
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: _focused
                ? Border.all(color: kAccent, width: 2)
                : null,
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: kAccent.withValues(alpha: 0.45),
                      blurRadius: 14,
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              // The detector above owns the focus; a second focusable node
              // here would make every surface take two D-pad presses.
              canRequestFocus: false,
              focusColor: Colors.transparent,
              onTap: _enabled ? widget.onTap : null,
              borderRadius: radius,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
