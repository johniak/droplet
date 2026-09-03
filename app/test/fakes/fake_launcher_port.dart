import 'package:droplet/core/launch/launch_request.dart';
import 'package:droplet/core/platform/launcher_port.dart';

class FakeLauncherPort implements LauncherPort {
  FakeLauncherPort({this.installed = const {}, this.launchResult, this.tree});

  final Set<String> installed;
  String? launchResult;
  RomTree? tree;
  final List<LaunchRequest> launched = [];
  int picks = 0;

  @override
  Future<List<String>> installedPackages(List<String> candidates) async => [
    for (final c in candidates)
      if (installed.contains(c)) c,
  ];

  @override
  Future<String?> launch(LaunchRequest request) async {
    launched.add(request);
    return launchResult;
  }

  @override
  Future<RomTree?> pickRomTree() async {
    picks++;
    return tree;
  }
}
