import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../tokens.dart';
import 'focus_glow.dart';

/// The floating bottom navigation — the only BackdropFilter outside the hero.
class GlassBar extends StatelessWidget {
  const GlassBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.badge = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int badge;

  static const items = [
    (key: 'nav-library', icon: Icons.grid_view_rounded, label: 'Library'),
    (key: 'nav-downloads', icon: Icons.download_rounded, label: 'Downloads'),
    (key: 'nav-settings', icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kRadiusBar),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                height: kNavHeight,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(kRadiusBar),
                  border: Border.all(color: kGlassBorder),
                ),
                // Not a traversal target: directional focus cannot cross out
                // of a page's route scope into the bar anyway, and a tab the
                // pad could only reach by accident is worse than none. L1/R1
                // switch tabs; touch still works.
                child: ExcludeFocus(
                  child: Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _Tab(
                            key: Key(items[i].key),
                            icon: items[i].icon,
                            label: items[i].label,
                            selected: i == currentIndex,
                            badge: i == 1 ? badge : 0,
                            onTap: () => onTap(i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? kAccent : kTextDim;
    Widget iconWidget = Icon(icon, size: 22, color: color);
    if (badge > 0) {
      iconWidget = Badge(
        label: Text('$badge'),
        backgroundColor: kAccent,
        textColor: kBgBottom,
        child: iconWidget,
      );
    }
    return FocusGlow(
      onTap: onTap,
      scale: 1,
      borderRadius: kRadiusBar,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          iconWidget,
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
