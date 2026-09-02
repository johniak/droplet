import 'package:flutter/material.dart';

import '../tokens.dart';

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.accent = false});

  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: accent ? kAccent.withValues(alpha: 0.22) : kGlass,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: accent ? kAccent.withValues(alpha: 0.5) : kGlassBorder,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: accent ? const Color(0xFFBFD0FF) : kText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}
