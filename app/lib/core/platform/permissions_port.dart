// coverage:ignore-file
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Thin adapter over permission_handler; all decisions live in
/// `lib/core/downloads/permissions.dart` and are tested on fakes.
abstract class PermissionsPort {
  Future<bool> hasAllFilesAccess();
  Future<bool> requestAllFilesAccess();
  Future<List<String>> appPrivateDirs();
}

class PermissionHandlerPort implements PermissionsPort {
  const PermissionHandlerPort();

  @override
  Future<bool> hasAllFilesAccess() =>
      Permission.manageExternalStorage.isGranted;

  @override
  Future<bool> requestAllFilesAccess() async {
    final status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) {
      await openAppSettings();
      return Permission.manageExternalStorage.isGranted;
    }
    return true;
  }

  @override
  Future<List<String>> appPrivateDirs() async {
    final docs = await getApplicationDocumentsDirectory();
    final external = await getExternalStorageDirectory();
    return [docs.path, if (external != null) external.path];
  }
}

final permissionsPortProvider = Provider<PermissionsPort>(
  (ref) => const PermissionHandlerPort(),
);
