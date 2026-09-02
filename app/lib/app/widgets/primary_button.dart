import 'package:flutter/material.dart';

import '../tokens.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.ghost = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool ghost;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final radius = BorderRadius.circular(kRadiusCard);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          gradient: ghost ? null : kPrimaryGradient,
          color: ghost ? kGlass : null,
          border: ghost ? Border.all(color: kGlassBorder) : null,
          borderRadius: radius,
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
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: radius,
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
                  : Text(
                      label,
                      style: TextStyle(
                        color: ghost ? kText : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
