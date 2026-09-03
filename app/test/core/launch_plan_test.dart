import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/launch/emulator_catalog.dart';
import 'package:droplet/core/launch/launch_plan.dart';
import 'package:droplet/core/launch/launch_request.dart';
import 'package:flutter_test/flutter_test.dart';

GameFileModel f(int id, String name, FileRole role, {int? disc}) =>
    GameFileModel(
      id: id,
      name: name,
      relativePath: 'x/$name',
      role: role,
      discNumber: disc,
      version: '',
      size: 1,
    );

GameDetail game(String system, List<GameFileModel> files) => GameDetail(
  id: 1,
  title: 'T',
  systemCode: system,
  systemName: system,
  hasCover: false,
  totalSize: 1,
  folder: 'T',
  files: files,
);

void main() {
  group('bootFile', () {
    test('m3u wins over discs and cues', () {
      final g = game('psx', [
        f(1, 'disc1/a.cue', FileRole.disc, disc: 1),
        f(2, 'a.m3u', FileRole.support),
        f(3, 'disc1/a.bin', FileRole.support),
      ]);
      expect(bootFile(g)!.id, 2);
    });

    test('disc 1, then cue, then base', () {
      expect(
        bootFile(
          game('psx', [
            f(1, 'b.cue', FileRole.base),
            f(2, 'd2.cue', FileRole.disc, disc: 2),
            f(3, 'd1.cue', FileRole.disc, disc: 1),
          ]),
        )!.id,
        3,
      );
      expect(
        bootFile(
          game('psx', [
            f(1, 'b.bin', FileRole.support),
            f(2, 'b.cue', FileRole.base),
          ]),
        )!.id,
        2,
      );
      expect(bootFile(game('snes', [f(1, 'z.sfc', FileRole.base)]))!.id, 1);
    });

    test('switch: first base by name, updates and mods never boot', () {
      final g = game('switch', [
        f(1, 'mods/skin.zip', FileRole.mod),
        f(2, 'Game [UPD][0100000000000800][v2].nsp', FileRole.update),
        f(3, 'Game [0100000000000000][v0].nsp', FileRole.base),
      ]);
      expect(bootFile(g)!.id, 3);
    });

    test('a disc without a base or a cue still boots', () {
      expect(
        bootFile(
          game('psx', [f(1, 'd2.cue', FileRole.disc, disc: 2)]),
        )!.id,
        1,
      );
    });

    test('nothing bootable', () {
      expect(
        bootFile(
          game('switch', [
            f(1, 'mods/a.zip', FileRole.mod),
            f(2, 'readme.txt', FileRole.other),
          ]),
        ),
        isNull,
      );
      expect(bootFile(game('switch', [])), isNull);
    });
  });

  group('resolveTemplate', () {
    const tree = RomTree(uri: 'content://tree', path: '/roms');

    test('retroarch: path extras, package tokens expanded', () {
      final spec = specById('ra-snes9x')!;
      final r = resolveTemplate(
        spec: spec,
        romPath: '/roms/snes/G/g.sfc',
        tree: tree,
      );
      expect(r.package, 'com.retroarch');
      expect(
        r.activity,
        'com.retroarch.browser.retroactivity.RetroActivityFuture',
      );
      expect(r.action, isNull);
      expect(r.dataMode, DataMode.none);
      expect(r.extras['ROM'], ' ROM ');
      expect(
        r.extras['LIBRETRO'],
        '/data/data/com.retroarch/cores/snes9x_libretro_android.so',
      );
      expect(
        r.extras['CONFIGFILE'],
        '/storage/emulated/0/Android/data/com.retroarch/files/retroarch.cfg',
      );
      expect(r.romPath, '/roms/snes/G/g.sfc');
    });

    test('eden: VIEW with provider data, no tree needed', () {
      final r = resolveTemplate(
        spec: specById('eden')!,
        romPath: '/roms/switch/G/g.nsp',
      );
      // A record would compare the maps by identity, so extras stands alone.
      expect((r.action, r.dataMode), (
        'android.intent.action.VIEW',
        DataMode.provider,
      ));
      expect(r.extras, isEmpty);
    });

    test('duckstation: saf extra, bool extra, flags', () {
      final r = resolveTemplate(
        spec: specById('duckstation')!,
        romPath: '/roms/psx/G/g.cue',
        tree: tree,
      );
      expect(r.extras, {'resumeState': false, 'bootPath': ' ROMSAF '});
      expect((r.clearTask, r.clearTop, r.dataMode), (
        true,
        true,
        DataMode.none,
      ));
      expect((r.romTreeUri, r.romTreePath), ('content://tree', '/roms'));
    });

    test('azahar: saf data + category-less VIEW', () {
      final r = resolveTemplate(
        spec: specById('azahar')!,
        romPath: '/roms/n3ds/G/g.3ds',
        tree: tree,
      );
      expect((r.dataMode, r.action, r.clearTask), (
        DataMode.saf,
        'android.intent.action.VIEW',
        true,
      ));
      expect(r.category, isNull);
    });

    test('dolphin: category extra', () {
      final r = resolveTemplate(
        spec: specById('dolphin')!,
        romPath: '/roms/gc/G/g.iso',
        tree: tree,
      );
      expect(r.category, 'android.intent.category.LEANBACK_LAUNCHER');
      expect(r.extras['AutoStartFile'], ' ROMSAF ');
    });

    test('a %DATA%=%ROM% template asks for the plain path', () {
      const spec = EmulatorSpec(
        id: 'x',
        name: 'X',
        package: 'p',
        template: '%DATA%=%ROM%',
      );
      expect(resolveTemplate(spec: spec, romPath: '/r/g.iso').dataMode,
          DataMode.path);
    });

    test('saf template without a tree is an error', () {
      expect(
        () => resolveTemplate(spec: specById('azahar')!, romPath: '/r/g.3ds'),
        throwsA(
          isA<LaunchPlanError>().having((e) => e.code, 'code', 'saf-tree-missing'),
        ),
      );
    });

    test('unknown placeholder is a programming error', () {
      const bad = EmulatorSpec(
        id: 'x',
        name: 'x',
        package: 'p',
        template: '%BOGUS%=1 %DATA%=%ROM%',
      );
      expect(() => resolveTemplate(spec: bad, romPath: '/r'), throwsArgumentError);
      const noEquals = EmulatorSpec(
        id: 'x',
        name: 'x',
        package: 'p',
        template: '%WAT%',
      );
      expect(
        () => resolveTemplate(spec: noEquals, romPath: '/r'),
        throwsArgumentError,
      );
      const badData = EmulatorSpec(
        id: 'x',
        name: 'x',
        package: 'p',
        template: '%DATA%=%NOPE%',
      );
      expect(
        () => resolveTemplate(spec: badData, romPath: '/r'),
        throwsArgumentError,
      );
    });
  });
}
