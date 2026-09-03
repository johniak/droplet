/// One emulator we know how to launch. [template] is the ES-DE launch
/// command minus the leading `%EMULATOR_X%`, so rules can be copied from
/// `es_systems.xml` one to one (see the spec, §2).
class EmulatorSpec {
  const EmulatorSpec({
    required this.id,
    required this.name,
    required this.package,
    this.activity,
    required this.template,
  });

  /// Unique across the whole catalogue, e.g. 'eden', 'ra-snes9x'.
  final String id;

  /// The name shown in Settings, e.g. 'RetroArch (Snes9x)'.
  final String name;

  final String package;
  final String? activity;
  final String template;
}

const _raPackage = 'com.retroarch';
const _raActivity = 'com.retroarch.browser.retroactivity.RetroActivityFuture';

/// A RetroArch core entry: the same three extras for every core, only the
/// `.so` changes.
EmulatorSpec _ra(String id, String core, String name) => EmulatorSpec(
  id: 'ra-$id',
  name: 'RetroArch ($name)',
  package: _raPackage,
  activity: _raActivity,
  template:
      '%EXTRA_CONFIGFILE%=%EXTERNALDATA%/Android/data/%ANDROIDPACKAGE%'
      '/files/retroarch.cfg '
      '%EXTRA_LIBRETRO%=%INTERNALDATA%/%ANDROIDPACKAGE%/cores/'
      '${core}_libretro_android.so '
      '%EXTRA_ROM%=%ROM%',
);

/// `%ACTION%=android.intent.action.VIEW` with the ROM as a SAF document URI —
/// by far the most common shape.
const _viewSaf = '%ACTION%=android.intent.action.VIEW %DATA%=%ROMSAF%';

/// The yuzu-family template: our own FileProvider URI, no SAF tree needed.
const _viewProvider =
    '%ACTION%=android.intent.action.VIEW %DATA%=%ROMPROVIDER%';

const _yuzuActivity = 'org.yuzu.yuzu_emu.activities.EmulationActivity';

const _dolphin = EmulatorSpec(
  id: 'dolphin',
  name: 'Dolphin',
  package: 'org.dolphinemu.dolphinemu',
  activity: 'org.dolphinemu.dolphinemu.ui.main.MainActivity',
  template:
      '%ACTION%=android.intent.action.MAIN '
      '%CATEGORY%=android.intent.category.LEANBACK_LAUNCHER '
      '%EXTRA_AutoStartFile%=%ROMSAF%',
);

/// GameCube and Wii run the very same emulators, so both systems point at
/// one list of specs (ids stay unique).
final List<EmulatorSpec> _dolphinSystems = [
  _dolphin,
  _ra('dolphin', 'dolphin', 'Dolphin'),
];

/// System code -> emulators, best first. The order is the default choice:
/// the first installed one wins until the user picks another.
final Map<String, List<EmulatorSpec>> _catalog = {
  'switch': [
    const EmulatorSpec(
      id: 'eden',
      name: 'Eden',
      package: 'dev.eden.eden_emulator',
      activity: _yuzuActivity,
      template: _viewProvider,
    ),
    const EmulatorSpec(
      id: 'citron',
      name: 'Citron',
      package: 'org.citron.citron_emu',
      activity: 'org.citron.citron_emu.activities.EmulationActivity',
      template: _viewProvider,
    ),
    const EmulatorSpec(
      id: 'sudachi',
      name: 'Sudachi',
      package: 'org.sudachi.sudachi_emu',
      activity: 'org.sudachi.sudachi_emu.activities.EmulationActivity',
      template: _viewProvider,
    ),
    const EmulatorSpec(
      id: 'yuzu',
      name: 'Yuzu',
      package: 'org.yuzu.yuzu_emu',
      activity: _yuzuActivity,
      template: _viewProvider,
    ),
    const EmulatorSpec(
      id: 'kenjinx',
      name: 'Kenji-NX',
      package: 'org.kenjinx.android',
      activity: 'org.kenjinx.android.MainActivity',
      template:
          '%ACTION%=org.kenjinx.android.LAUNCH_GAME '
          '%EXTRA_bootPath%=%ROMSAF%',
    ),
  ],
  'n3ds': [
    const EmulatorSpec(
      id: 'azahar',
      name: 'Azahar',
      package: 'org.azahar_emu.azahar',
      activity: 'org.citra.citra_emu.activities.EmulationActivity',
      template:
          '%ACTIVITY_CLEAR_TASK% %ACTIVITY_CLEAR_TOP% $_viewSaf',
    ),
    const EmulatorSpec(
      id: 'citra',
      name: 'Citra',
      package: 'org.citra.emu',
      template: _viewSaf,
    ),
    _ra('citra', 'citra', 'Citra'),
  ],
  'nds': [
    const EmulatorSpec(
      id: 'melonds',
      name: 'melonDS',
      package: 'me.magnum.melonds',
      activity: 'me.magnum.melonds.ui.emulator.EmulatorActivity',
      template: '%ACTION%=me.magnum.melonds.LAUNCH_ROM %EXTRA_uri%=%ROMSAF%',
    ),
    const EmulatorSpec(
      id: 'melonds-dualds',
      name: 'melonDS DualDS',
      package: 'me.magnum.melondualds',
      activity: 'me.magnum.melonds.ui.emulator.EmulatorActivity',
      template:
          '%ACTION%=me.magnum.melondualds.LAUNCH_ROM %EXTRA_uri%=%ROMSAF%',
    ),
    _ra('melondsds', 'melondsds', 'melonDS DS'),
    _ra('desmume', 'desmume', 'DeSmuME'),
  ],
  'psx': [
    const EmulatorSpec(
      id: 'duckstation',
      name: 'DuckStation',
      package: 'com.github.stenzek.duckstation',
      activity: 'com.github.stenzek.duckstation.EmulationActivity',
      template:
          '%ACTIVITY_CLEAR_TASK% %ACTIVITY_CLEAR_TOP% '
          '%EXTRABOOL_resumeState%=false %EXTRA_bootPath%=%ROMSAF%',
    ),
    _ra('mednafen-psx-hw', 'mednafen_psx_hw', 'Beetle PSX HW'),
    _ra('pcsx-rearmed', 'pcsx_rearmed', 'PCSX ReARMed'),
    _ra('swanstation', 'swanstation', 'SwanStation'),
  ],
  'ps2': [
    const EmulatorSpec(
      id: 'nethersx2',
      name: 'NetherSX2',
      package: 'xyz.aethersx2.android',
      activity: 'xyz.aethersx2.android.EmulationActivity',
      template:
          '%ACTIVITY_CLEAR_TASK% %ACTIVITY_CLEAR_TOP% '
          '%ACTION%=android.intent.action.MAIN %EXTRA_bootPath%=%ROMSAF%',
    ),
  ],
  'psp': [
    const EmulatorSpec(
      id: 'ppsspp',
      name: 'PPSSPP',
      package: 'org.ppsspp.ppsspp',
      activity: 'org.ppsspp.ppsspp.PpssppActivity',
      template: _viewSaf,
    ),
    const EmulatorSpec(
      id: 'ppsspp-gold',
      name: 'PPSSPP Gold',
      package: 'org.ppsspp.ppssppgold',
      activity: 'org.ppsspp.ppsspp.PpssppActivity',
      template: _viewSaf,
    ),
    _ra('ppsspp', 'ppsspp', 'PPSSPP'),
  ],
  'gc': _dolphinSystems,
  'wii': _dolphinSystems,
  'wiiu': [
    const EmulatorSpec(
      id: 'cemu',
      name: 'Cemu',
      package: 'info.cemu.cemu',
      activity: 'info.cemu.cemu.emulation.EmulationActivity',
      template: _viewSaf,
    ),
  ],
  'n64': [
    const EmulatorSpec(
      id: 'm64plus-fz',
      name: 'M64Plus FZ',
      package: 'org.mupen64plusae.v3.fzurita',
      activity: 'paulscode.android.mupen64plusae.SplashActivity',
      template: _viewSaf,
    ),
    _ra('mupen64plus-next', 'mupen64plus_next_gles3', 'Mupen64Plus-Next'),
    _ra('parallel-n64', 'parallel_n64', 'ParaLLEl N64'),
  ],
  'dreamcast': [
    const EmulatorSpec(
      id: 'flycast',
      name: 'Flycast',
      package: 'com.flycast.emulator',
      activity: 'com.flycast.emulator.MainActivity',
      template: _viewSaf,
    ),
    const EmulatorSpec(
      id: 'redream',
      name: 'Redream',
      package: 'io.recompiled.redream',
      activity: 'io.recompiled.redream.MainActivity',
      template: _viewSaf,
    ),
    _ra('flycast', 'flycast', 'Flycast'),
  ],
  'saturn': [
    _ra('mednafen-saturn', 'mednafen_saturn', 'Beetle Saturn'),
    _ra('yabasanshiro', 'yabasanshiro', 'YabaSanshiro'),
  ],
  'snes': [_ra('snes9x', 'snes9x', 'Snes9x'), _ra('bsnes', 'bsnes', 'bsnes')],
  'nes': [_ra('mesen', 'mesen', 'Mesen'), _ra('nestopia', 'nestopia', 'Nestopia')],
  'gb': [
    _ra('gambatte', 'gambatte', 'Gambatte'),
    _ra('sameboy', 'sameboy', 'SameBoy'),
  ],
  'gbc': [_ra('gambatte-gbc', 'gambatte', 'Gambatte')],
  'gba': [_ra('mgba', 'mgba', 'mGBA'), _ra('vbam', 'vbam', 'VBA-M')],
  'megadrive': [
    _ra('genesis-plus-gx', 'genesis_plus_gx', 'Genesis Plus GX'),
    _ra('picodrive', 'picodrive', 'PicoDrive'),
  ],
};

/// Every system the catalogue knows something about (`bios` is not one of
/// them — support packs are not games).
final List<String> kCatalogSystems = _catalog.keys.toList();

/// Emulators for a system, best first; empty for unknown systems.
List<EmulatorSpec> catalogFor(String systemCode) =>
    _catalog[systemCode] ?? const [];

final Map<String, EmulatorSpec> _byId = {
  for (final specs in _catalog.values)
    for (final spec in specs) spec.id: spec,
};

EmulatorSpec? specById(String id) => _byId[id];

/// Every package in the catalogue — what we ask the device about.
final Set<String> allCatalogPackages = {
  for (final spec in _byId.values) spec.package,
};
