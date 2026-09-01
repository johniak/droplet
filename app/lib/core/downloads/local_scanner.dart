import 'dart:io';

/// The only place that touches the filesystem when reading local ROMs.
Future<Map<String, int>> scanSystemDir(String dirPath) async {
  final dir = Directory(dirPath);
  if (!await dir.exists()) return {};
  final sizes = <String, int>{};
  await for (final entity in dir.list()) {
    if (entity is File) {
      sizes[entity.uri.pathSegments.last] = await entity.length();
    }
  }
  return sizes;
}
