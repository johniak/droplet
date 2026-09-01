import 'package:droplet/core/downloads/permissions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_permissions_port.dart';

void main() {
  const appDirs = fakeAppPrivateDirs;

  test('app-private dir needs no permission, shared storage does', () {
    expect(needsAllFilesAccess('${appDirs.first}/roms', appDirs), false);
    expect(
      needsAllFilesAccess('/storage/emulated/0/RetroArch/roms', appDirs),
      true,
    );
  });

  test('skips request for app-private base dir', () async {
    final port = FakePermissionsPort(granted: false);
    expect(await ensureStoragePermission(port, '${appDirs.first}/roms'), true);
    expect(port.requests, 0);
  });

  test('requests when missing and returns result', () async {
    final ok = FakePermissionsPort(granted: false, grantOnRequest: true);
    expect(await ensureStoragePermission(ok, '/storage/emulated/0/roms'), true);
    expect(ok.requests, 1);
    final denied = FakePermissionsPort(granted: false);
    expect(
      await ensureStoragePermission(denied, '/storage/emulated/0/roms'),
      false,
    );
  });

  test('already granted -> no request', () async {
    final port = FakePermissionsPort(granted: true);
    expect(await ensureStoragePermission(port, '/storage/emulated/0/roms'), true);
    expect(port.requests, 0);
  });
}
