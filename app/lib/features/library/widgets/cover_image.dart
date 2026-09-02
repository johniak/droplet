import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../app/tokens.dart';

/// Boxart with a graceful fallback: a game without a cover still fills its
/// slot in the grid instead of leaving a hole.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.title,
    required this.url,
    required this.headers,
    required this.hasCover,
    this.fit = BoxFit.contain,
  });

  final String title;
  final String url;
  final Map<String, String> headers;
  final bool hasCover;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (!hasCover) return _Placeholder(title: title);
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: headers,
      // Boxart aspect ratios differ per system; `contain` keeps the whole box
      // (and its title) visible instead of cropping it away.
      fit: fit,
      placeholder: (_, __) => _Placeholder(title: title),
      errorWidget: (_, __, ___) => _Placeholder(title: title),
    );
  }
}

const coverPlaceholderGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF242B45), Color(0xFF161A2C)],
);

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(gradient: coverPlaceholderGradient),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kTextDim,
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
}
