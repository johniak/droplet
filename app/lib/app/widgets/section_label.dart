import 'package:flutter/material.dart';

import '../tokens.dart';

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.onTrailingTap});

  final String text;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  static const _style = TextStyle(
    color: kTextDim,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
  );

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Row(
          children: [
            Expanded(child: Text(text, style: _style)),
            if (trailing != null)
              GestureDetector(
                onTap: onTrailingTap,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  trailing!,
                  style: _style.copyWith(
                    color: onTrailingTap == null ? kTextDim : kAccent,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
          ],
        ),
      );
}
