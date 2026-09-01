import '../platform/permissions_port.dart';

/// A base directory inside the app's own storage is writable without the
/// All Files Access permission — that is what the e2e run uses.
bool needsAllFilesAccess(String baseDir, List<String> appPrivateDirs) =>
    !appPrivateDirs.any((dir) => baseDir == dir || baseDir.startsWith('$dir/'));

Future<bool> ensureStoragePermission(
  PermissionsPort port,
  String baseDir,
) async {
  if (!needsAllFilesAccess(baseDir, await port.appPrivateDirs())) return true;
  if (await port.hasAllFilesAccess()) return true;
  return port.requestAllFilesAccess();
}
