import 'package:droplet/core/launch/emulator_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every entry has a unique id and exactly one ROM placeholder', () {
    // `gc` and `wii` share the very same Dolphin entries, so a repeated id
    // has to be the same object — not a second spec wearing the same name.
    final ids = <String, EmulatorSpec>{};
    for (final system in kCatalogSystems) {
      for (final spec in catalogFor(system)) {
        expect(
          ids.putIfAbsent(spec.id, () => spec),
          same(spec),
          reason: 'duplicate id ${spec.id}',
        );
        final count = [
          '%ROM%',
          '%ROMSAF%',
          '%ROMPROVIDER%',
        ].where(spec.template.contains).length;
        expect(count, 1, reason: '${spec.id}: ${spec.template}');
        expect(spec.package, isNotEmpty);
      }
    }
    expect(catalogFor('bios'), isEmpty);
    expect(catalogFor('unknown'), isEmpty);
  });

  test('preferred order and known entries', () {
    expect(catalogFor('switch').first.id, 'eden');
    expect(catalogFor('nds').map((s) => s.id), contains('melonds-dualds'));
    expect(catalogFor('psx').first.id, 'duckstation');
    expect(catalogFor('snes').first.id, 'ra-snes9x');
    expect(specById('eden')!.package, 'dev.eden.eden_emulator');
    expect(specById('nope'), isNull);
    expect(
      allCatalogPackages,
      containsAll(['com.retroarch', 'org.azahar_emu.azahar']),
    );
  });

  test('gc and wii share the Dolphin entries', () {
    expect(catalogFor('gc').first, same(catalogFor('wii').first));
    expect(catalogFor('gc').map((s) => s.id), ['dolphin', 'ra-dolphin']);
  });
}
