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

  test('RetroArch answers to both of its packages', () {
    final spec = specById('ra-snes9x')!;
    expect(spec.packages, ['com.retroarch', 'com.retroarch.aarch64']);
    expect(allCatalogPackages, contains('com.retroarch.aarch64'));
    // Whichever build is on the device is the one we launch.
    expect(spec.installedPackage({'com.retroarch.aarch64'}),
        'com.retroarch.aarch64');
    expect(spec.installedPackage({'com.retroarch'}), 'com.retroarch');
    expect(spec.installedPackage({'org.citra.emu'}), isNull);
    final resolved = spec.withPackage('com.retroarch.aarch64');
    expect((resolved.id, resolved.name, resolved.activity),
        (spec.id, spec.name, spec.activity));
    expect(resolved.package, 'com.retroarch.aarch64');
    // A single-package entry keeps answering to just the one.
    expect(specById('eden')!.packages, ['dev.eden.eden_emulator']);
  });

  test('gc and wii share the Dolphin entries', () {
    expect(catalogFor('gc').first, same(catalogFor('wii').first));
    expect(catalogFor('gc').map((s) => s.id), ['dolphin', 'ra-dolphin']);
  });

  test('Citra MMJ (org.citra.emu) launches with a plain path extra', () {
    final mmj = specById('citra-mmj')!;
    expect((mmj.package, mmj.activity), ('org.citra.emu', 'org.citra.emu.ui.MainActivity'));
    expect(mmj.template, '%EXTRA_GamePath%=%ROM%');
    expect(specById('citra')!.package, 'org.citra.citra_emu');
    expect(catalogFor('n3ds').map((s) => s.id), ['azahar', 'citra-mmj', 'citra', 'ra-citra']);
  });
}
