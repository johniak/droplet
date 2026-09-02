import 'dart:io';

/// The only place that touches the filesystem when reading local ROMs.
///
/// Synchronous IO on purpose: async dart:io never completes inside
/// `testWidgets` (the fake-async zone does not pump the real event loop), and
/// the install badge on every game card depends on this call.
Future<Map<String, int>> scanSystemDir(String dirPath) async {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return {};
  final sizes = <String, int>{};
  for (final entity in dir.listSync()) {
    if (entity is File) {
      sizes[entity.uri.pathSegments.last] = entity.lengthSync();
    }
  }
  return sizes;
}
