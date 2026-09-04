import 'package:flutter/material.dart';

import '../tokens.dart';
import 'focus_glow.dart';

/// A round button on a dark pill — readable even over a light cover.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.autofocus = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  /// Screens whose first useful control is Back start here.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final button = FocusGlow(
      scale: 1,
      borderRadius: 18,
      autofocus: autofocus,
      onTap: onPressed,
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(side: BorderSide(color: kGlassBorder)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: kText),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
