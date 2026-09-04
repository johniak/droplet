import 'package:flutter/material.dart';

import '../tokens.dart';

/// One wrapper for every interactive surface the gamepad has to reach: it is
/// focusable, it activates on A (`ActivateIntent`) and on touch, it draws a
/// visible accent ring while focused, and it scrolls itself into view when
/// the focus lands on it.
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
    this.ring = true,
    this.fill = true,
  });

  /// What A and a tap do. Null keeps the surface focusable but inert — a
  /// button that is busy must not drop the focus it holds.
  final VoidCallback? onTap;
  final Widget child;
  final bool autofocus;
  final FocusNode? focusNode;
  final double borderRadius;

  /// How much the surface grows while focused — 1.0 for list rows, where a
  /// growing row would push its neighbours around.
  final double scale;

  /// Whether the surface takes the focus at all. False for a control with
  /// nothing to do, which must not swallow a D-pad press.
  final bool enabled;

  /// Draw the ring around the whole surface. False when one part of it
  /// should carry the ring instead — a tile's cover, not its caption —
  /// through a [FocusRing] inside.
  final bool ring;

  /// A faint accent wash under the content while focused, so a flat row or
  /// panel reads as chosen. Off for a surface with its own colour, such as
  /// the gradient button, which the wash would only dull.
  final bool fill;

  /// Whether the nearest enclosing [FocusGlow] is showing its highlight.
  static bool highlighted(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlowScope>()?.highlighted ??
      false;

  @override
  State<FocusGlow> createState() => _FocusGlowState();
}

class _FocusGlowState extends State<FocusGlow> {
  /// Focus itself (drives scroll-into-view) versus the visible highlight:
  /// Flutter only shows focus highlights in "traditional" mode, which starts
  /// after the first key/pad event and ends at the next touch — so a screen
  /// opens with nothing selected and the glow appears once the pad is used.
  bool _highlight = false;

  void _onShowHighlight(bool show) => setState(() => _highlight = show);

  void _onFocusChange(bool focused) {
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
    Widget surface = Material(
      color: Colors.transparent,
      child: InkWell(
        // The detector above owns the focus; a second focusable node
        // here would make every surface take two D-pad presses.
        canRequestFocus: false,
        focusColor: Colors.transparent,
        onTap: widget.enabled ? widget.onTap : null,
        borderRadius: radius,
        child: widget.child,
      ),
    );
    if (widget.ring) {
      surface = FocusChrome(
        on: _highlight,
        radius: radius,
        fill: widget.fill,
        child: surface,
      );
    }
    return FocusableActionDetector(
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      onFocusChange: _onFocusChange,
      onShowFocusHighlight: _onShowHighlight,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: _GlowScope(
        highlighted: _highlight,
        child: AnimatedScale(
          scale: _highlight ? widget.scale : 1,
          duration: const Duration(milliseconds: 150),
          child: surface,
        ),
      ),
    );
  }
}

/// The ring for one part of a [FocusGlow] surface (its cover), lit whenever
/// the enclosing surface is. Nothing without a [FocusGlow] above it.
class FocusRing extends StatelessWidget {
  const FocusRing({
    super.key,
    required this.child,
    this.borderRadius = kRadiusCover,
  });

  final Widget child;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => FocusChrome(
    on: FocusGlow.highlighted(context),
    radius: BorderRadius.circular(borderRadius),
    fill: false,
    child: child,
  );
}

/// The focused look: a soft accent halo (and, for a flat surface, a faint
/// wash) painted *under* the content, with a thin light ring over it. The
/// halo has to sit underneath — a blurred shadow in a foreground decoration
/// covers the whole box and washes the content out.
class FocusChrome extends StatelessWidget {
  const FocusChrome({
    super.key,
    required this.on,
    required this.radius,
    required this.fill,
    required this.child,
  });

  final bool on;
  final BorderRadius radius;
  final bool fill;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const Key('focus-glow-halo'),
    decoration: BoxDecoration(
      borderRadius: radius,
      color: on && fill ? kAccent.withValues(alpha: 0.12) : null,
      boxShadow: on
          ? [
              BoxShadow(
                color: kAccent.withValues(alpha: 0.55),
                blurRadius: 10,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: kAccent.withValues(alpha: 0.30),
                blurRadius: 26,
                spreadRadius: 4,
              ),
            ]
          : null,
    ),
    child: DecoratedBox(
      key: const Key('focus-glow-ring'),
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: on ? Border.all(color: kFocusRing, width: 2) : null,
      ),
      child: child,
    ),
  );
}

class _GlowScope extends InheritedWidget {
  const _GlowScope({required this.highlighted, required super.child});

  final bool highlighted;

  @override
  bool updateShouldNotify(_GlowScope old) => old.highlighted != highlighted;
}
