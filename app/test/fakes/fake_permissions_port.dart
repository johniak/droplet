import 'package:droplet/core/platform/permissions_port.dart';

const fakeAppPrivateDirs = ['/data/user/0/dev.johniak.droplet/app_flutter'];

class FakePermissionsPort implements PermissionsPort {
  FakePermissionsPort({required this.granted, this.grantOnRequest = false});

  bool granted;
  final bool grantOnRequest;
  int requests = 0;

  @override
  Future<bool> hasAllFilesAccess() async => granted;

  @override
  Future<bool> requestAllFilesAccess() async {
    requests++;
    if (grantOnRequest) granted = true;
    return granted;
  }

  @override
  Future<List<String>> appPrivateDirs() async => fakeAppPrivateDirs;
}
