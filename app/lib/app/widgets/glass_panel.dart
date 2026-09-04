import 'package:flutter/material.dart';

import '../tokens.dart';
import 'focus_glow.dart';

/// A translucent card without blur — safe to use in lists.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = kRadiusCard,
    this.onTap,
    this.margin,
    this.autofocus = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  /// Only meaningful together with [onTap]: the first row of a list takes
  /// the focus when the screen opens.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    // The focus ring wraps the card from the outside — inside, the panel's
    // own antialiasing clip would cut the glow away.
    Widget panel = Container(
      decoration: BoxDecoration(
        color: kGlass,
        borderRadius: shape,
        border: Border.all(color: kGlassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
    if (onTap case final tap?) {
      panel = FocusGlow(
        scale: 1,
        borderRadius: radius,
        autofocus: autofocus,
        onTap: tap,
        child: panel,
      );
    }
    return margin == null ? panel : Padding(padding: margin!, child: panel);
  }
}
