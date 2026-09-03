// coverage:ignore-file
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../launch/launch_request.dart';

/// Thin adapter over the native launcher channel: which emulators are
/// installed, starting one with a ROM, and the SAF tree picker. All the
/// planning lives in `lib/core/launch` and is tested on fakes.
abstract class LauncherPort {
  Future<List<String>> installedPackages(List<String> candidates);

  /// `null` = started; otherwise a short error code/message:
  /// 'saf-tree-missing', 'activity-not-found', 'security', or the
  /// exception text.
  Future<String?> launch(LaunchRequest request);

  Future<RomTree?> pickRomTree();
}

class MethodChannelLauncherPort implements LauncherPort {
  const MethodChannelLauncherPort();

  static const _channel = MethodChannel('dev.johniak.droplet/launcher');

  @override
  Future<List<String>> installedPackages(List<String> candidates) async =>
      await _channel.invokeListMethod<String>('installedPackages', {
        'candidates': candidates,
      }) ??
      const [];

  @override
  Future<String?> launch(LaunchRequest request) =>
      _channel.invokeMethod<String>('launch', request.toMap());

  @override
  Future<RomTree?> pickRomTree() async {
    final map = await _channel.invokeMapMethod<String, dynamic>('pickRomTree');
    return map == null ? null : RomTree.fromMap(map);
  }
}

final launcherPortProvider = Provider<LauncherPort>(
  (ref) => const MethodChannelLauncherPort(),
);
