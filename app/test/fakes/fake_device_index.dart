import 'package:droplet/core/downloads/device_scan.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A device index that never touches disk: tests supply a ready-made state map.
///
/// `states` is a plain map, so a test can mutate it and call [refresh]
/// to simulate a rescan after a download or a delete.
class FakeDeviceIndex extends DeviceIndexController {
  FakeDeviceIndex(this.states, {this.unknown = const []});

  final Map<int, LocalGameState> states;
  final List<UnknownEntry> unknown;

  int refreshes = 0;

  @override
  DeviceIndex get lastIndex => DeviceIndex(games: const {}, unknown: unknown);

  @override
  Future<Map<int, LocalGameState>> build() async => states;

  /// A copy of the map, because `AsyncData` compares by value — the same map
  /// instance wouldn't wake up the listeners.
  @override
  Future<void> refresh() async {
    refreshes++;
    state = AsyncData({...states});
  }
}
