import 'package:droplet/core/downloads/device_scan.dart';
import 'package:droplet/core/downloads/local_state.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Indeks urządzenia bez dotykania dysku: testy podają gotową mapę stanów.
///
/// `states` jest zwykłą mapą, więc test może ją zmienić i wywołać [refresh],
/// żeby udać ponowny skan po pobraniu albo usunięciu plików.
class FakeDeviceIndex extends DeviceIndexController {
  FakeDeviceIndex(this.states, {this.unknown = const []});

  final Map<int, LocalGameState> states;
  final List<UnknownEntry> unknown;

  int refreshes = 0;

  @override
  DeviceIndex get lastIndex => DeviceIndex(games: const {}, unknown: unknown);

  @override
  Future<Map<int, LocalGameState>> build() async => states;

  /// Kopia mapy, bo `AsyncData` porównuje się po wartości — ta sama instancja
  /// mapy nie obudziłaby obserwatorów.
  @override
  Future<void> refresh() async {
    refreshes++;
    state = AsyncData({...states});
  }
}
