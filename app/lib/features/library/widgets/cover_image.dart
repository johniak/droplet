import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Boxart with a graceful fallback: a game without a cover still fills its
/// slot in the grid instead of leaving a hole.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.title,
    required this.url,
    required this.headers,
    required this.hasCover,
  });

  final String title;
  final String url;
  final Map<String, String> headers;
  final bool hasCover;

  @override
  Widget build(BuildContext context) {
    if (!hasCover) return _Placeholder(title: title);
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: headers,
      fit: BoxFit.cover,
      placeholder: (_, __) => _Placeholder(title: title),
      errorWidget: (_, __, ___) => _Placeholder(title: title),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kSurface, Color(0xFF10151C)],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kTextDim,
                fontSize: 13,
                height: 1.3,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      );
}
