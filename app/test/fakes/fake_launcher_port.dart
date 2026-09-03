import 'dart:async';

import 'package:droplet/core/launch/launch_request.dart';
import 'package:droplet/core/platform/launcher_port.dart';

class FakeLauncherPort implements LauncherPort {
  FakeLauncherPort({this.installed = const {}, this.launchResult, this.tree});

  final Set<String> installed;
  String? launchResult;

  /// Thrown instead of answering — the channel does exactly this when the
  /// Kotlin handler blows up.
  Object? launchThrows;

  /// Holds `launch` open until the test completes it — for asserting what
  /// the screen does while a launch is in flight.
  Completer<void>? hold;
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
    if (hold case final gate?) await gate.future;
    if (launchThrows case final error?) throw error;
    return launchResult;
  }

  @override
  Future<RomTree?> pickRomTree() async {
    picks++;
    return tree;
  }
}
