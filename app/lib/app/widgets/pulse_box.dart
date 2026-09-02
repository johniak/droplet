import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Skeleton block: a slow breath instead of a spinner, so a loading grid keeps
/// the shape of the content that is about to appear.
class PulseBox extends StatefulWidget {
  const PulseBox({super.key, this.width, this.height, this.radius});

  final double? width;
  final double? height;
  final BorderRadius? radius;

  @override
  State<PulseBox> createState() => _PulseBoxState();
}

class _PulseBoxState extends State<PulseBox> {
  static const _period = Duration(milliseconds: 900);
  double _opacity = 0.4;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_period, (_) {
      if (mounted) setState(() => _opacity = _opacity == 0.4 ? 0.8 : 0.4);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: _opacity,
        duration: _period,
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: widget.radius ?? BorderRadius.circular(12),
          ),
        ),
      );
}
