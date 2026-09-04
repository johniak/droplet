import 'package:flutter/material.dart';

import '../tokens.dart';
import 'focus_glow.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.ghost = false,
    this.busy = false,
    this.icon,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool ghost;
  final bool busy;

  /// Drawn before the label — for buttons that do more than the screen's
  /// default action (Play).
  final IconData? icon;

  /// The screen's primary control takes the focus when it opens.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          gradient: ghost ? null : kPrimaryGradient,
          color: ghost ? kGlass : null,
          border: ghost ? Border.all(color: kGlassBorder) : null,
          borderRadius: BorderRadius.circular(kRadiusCard),
          boxShadow: ghost || !enabled
              ? null
              : [
                  BoxShadow(
                    color: kAccent.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        // No clip here: the focus ring's glow has to reach past the button's
        // edge, and the ripple is clipped by the InkWell's own radius anyway.
        child: FocusGlow(
          scale: 1,
          borderRadius: kRadiusCard,
          autofocus: autofocus,
          onTap: enabled ? onPressed : null,
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kText,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 20, color: ghost ? kText : Colors.white),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: TextStyle(
                          color: ghost ? kText : Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
