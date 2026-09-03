# M11 — Play: uruchamianie gier z Dropletu

Data: 2026-09-04. Aplikacja Android; serwer bez zmian.

## 1. Cel

Na ekranie gry zainstalowanej na urządzeniu jest przycisk **Play**, który
uruchamia właściwy emulator z tą grą — tak jak robią to frontendy ES-DE/Cocoon.
Konfiguracja: Settings → **Emulators**, per system wybór spośród emulatorów
faktycznie zainstalowanych na telefonie. Bez emulatora Play pokazuje, co
zainstalować.

## 2. Model uruchamiania (zgodny z ES-DE Android)

Katalog emulatorów w aplikacji (`emulator_catalog.dart`) opisuje każdy wpis
szablonem w składni ES-DE, żeby dało się przenosić reguły 1:1 z `es_systems.xml`:

| Placeholder | Znaczenie |
|---|---|
| `%EMULATOR_X%` | pakiet + (opcjonalnie) aktywność z katalogu |
| `%ACTION%=a` | akcja intentu (domyślnie `android.intent.action.MAIN` gdy jest aktywność, inaczej `VIEW`) |
| `%CATEGORY%=c` | kategoria |
| `%DATA%=…` | `Intent.data` |
| `%EXTRA_k%=v` | extra typu String |
| `%EXTRABOOL_k%=v` | extra typu bool |
| `%ACTIVITY_CLEAR_TASK%`, `%ACTIVITY_CLEAR_TOP%` | flagi intentu |
| `%ROM%` | bezwzględna ścieżka pliku |
| `%ROMSAF%` | `content://` **document URI** z drzewa SAF katalogu ROM-ów |
| `%ROMPROVIDER%` | `content://` z naszego FileProvidera |
| `%ANDROIDPACKAGE%` | pakiet emulatora |
| `%INTERNALDATA%` / `%EXTERNALDATA%` | `/data/data` / `/storage/emulated/0` |

Wynik rozwiązania szablonu to `LaunchSpec` (czysty Dart, w pełni testowalny):
`package, activity?, action?, category?, dataMode (none|path|saf|provider),
extras: Map<String, Object>, flags: {clearTask, clearTop}`. Wartości extras i
`data` mogą być ścieżką lub URI wg trybu; URI buduje strona natywna.

## 3. Katalog (wersja startowa)

Kolejność w systemie = preferencja domyślna (pierwszy zainstalowany wygrywa).
Pakiety i aktywności wg reguł ES-DE Android; `RA` = RetroArch
(`com.retroarch` lub `com.retroarch.aarch64`, aktywność
`com.retroarch.browser.retroactivity.RetroActivityFuture`) z szablonem
`%EXTRA_CONFIGFILE%=%EXTERNALDATA%/Android/data/%ANDROIDPACKAGE%/files/retroarch.cfg %EXTRA_LIBRETRO%=%INTERNALDATA%/%ANDROIDPACKAGE%/cores/<core>_libretro_android.so %EXTRA_ROM%=%ROM%`.

- **switch**: Eden `dev.eden.eden_emulator` / `org.yuzu.yuzu_emu.activities.EmulationActivity` — `%ACTION%=android.intent.action.VIEW %DATA%=%ROMPROVIDER%`; Citron `org.citron.citron_emu` / `org.citron.citron_emu.activities.EmulationActivity` (j.w.); Sudachi `org.sudachi.sudachi_emu` / `org.sudachi.sudachi_emu.activities.EmulationActivity` (j.w.); Yuzu `org.yuzu.yuzu_emu` / `org.yuzu.yuzu_emu.activities.EmulationActivity` (j.w.); Kenji-NX `org.kenjinx.android` / `org.kenjinx.android.MainActivity` — `%ACTION%=org.kenjinx.android.LAUNCH_GAME %EXTRA_bootPath%=%ROMSAF%`.
- **n3ds**: Azahar `org.azahar_emu.azahar` / `org.citra.citra_emu.activities.EmulationActivity` — `%ACTIVITY_CLEAR_TASK% %ACTIVITY_CLEAR_TOP% %ACTION%=android.intent.action.VIEW %DATA%=%ROMSAF%`; Citra `org.citra.emu` — `%ACTION%=android.intent.action.VIEW %DATA%=%ROMSAF%`; RA `citra`.
- **nds**: melonDS `me.magnum.melonds` / `me.magnum.melonds.ui.emulator.EmulatorActivity` — `%ACTION%=me.magnum.melonds.LAUNCH_ROM %EXTRA_uri%=%ROMSAF%`; melonDS DualDS `me.magnum.melondualds` / `me.magnum.melonds.ui.emulator.EmulatorActivity` — `%ACTION%=me.magnum.melondualds.LAUNCH_ROM %EXTRA_uri%=%ROMSAF%`; RA `melondsds`, RA `desmume`.
- **psx**: DuckStation `com.github.stenzek.duckstation` / `com.github.stenzek.duckstation.EmulationActivity` — `%ACTIVITY_CLEAR_TASK% %ACTIVITY_CLEAR_TOP% %EXTRABOOL_resumeState%=false %EXTRA_bootPath%=%ROMSAF%`; RA `mednafen_psx_hw`, RA `pcsx_rearmed`, RA `swanstation`.
- **ps2**: NetherSX2/AetherSX2 `xyz.aethersx2.android` / `xyz.aethersx2.android.EmulationActivity` — `%ACTIVITY_CLEAR_TASK% %ACTIVITY_CLEAR_TOP% %ACTION%=android.intent.action.MAIN %EXTRA_bootPath%=%ROMSAF%`.
- **psp**: PPSSPP `org.ppsspp.ppsspp` / `org.ppsspp.ppsspp.PpssppActivity` — `%ACTION%=android.intent.action.VIEW %DATA%=%ROMSAF%`; PPSSPP Gold `org.ppsspp.ppssppgold` (j.w.); RA `ppsspp`.
- **gc**, **wii**: Dolphin `org.dolphinemu.dolphinemu` / `org.dolphinemu.dolphinemu.ui.main.MainActivity` — `%ACTION%=android.intent.action.MAIN %CATEGORY%=android.intent.category.LEANBACK_LAUNCHER %EXTRA_AutoStartFile%=%ROMSAF%`; RA `dolphin`.
- **wiiu**: Cemu `info.cemu.cemu` / `info.cemu.cemu.emulation.EmulationActivity` — `%ACTION%=android.intent.action.VIEW %DATA%=%ROMSAF%`.
- **n64**: M64Plus FZ `org.mupen64plusae.v3.fzurita` / `paulscode.android.mupen64plusae.SplashActivity` — `%ACTION%=android.intent.action.VIEW %DATA%=%ROMSAF%`; RA `mupen64plus_next_gles3`, RA `parallel_n64`.
- **dreamcast**: Flycast `com.flycast.emulator` / `com.flycast.emulator.MainActivity` — `%ACTION%=android.intent.action.VIEW %DATA%=%ROMSAF%`; Redream `io.recompiled.redream` / `io.recompiled.redream.MainActivity` (j.w.); RA `flycast`.
- **saturn**: RA `mednafen_saturn`, RA `yabasanshiro`.
- **snes**: RA `snes9x`, RA `bsnes`. **nes**: RA `mesen`, RA `nestopia`. **gb**: RA `gambatte`, RA `sameboy`. **gbc**: RA `gambatte`. **gba**: RA `mgba`, RA `vbam`. **megadrive**: RA `genesis_plus_gx`, RA `picodrive`.
- **bios**: brak (paczki nie są grami; Play niewidoczny).

Systemy spoza katalogu: brak emulatorów → Play pokazuje „No emulator configured”.

## 4. Który plik uruchomić

`bootFile(GameDetail)` → pierwszy wg kolejności: `role == support && .m3u` →
`role == disc && discNumber == 1` → `role == base && .cue` → `role == base`
(dla Switcha preferuj `.xci`/`.nsp` — pierwszy `base` po nazwie) → pierwszy
plik z roli innej niż `mod`/`other`. Gra bez takiego pliku → Play ukryty.
Ścieżka na urządzeniu: `StorageSettings.pathFor(systemCode, folder, name)`.

## 5. Strona natywna (Kotlin, `MainActivity` + `LauncherChannel`)

MethodChannel `dev.johniak.droplet/launcher`:
- `installedPackages(candidates: List<String>) -> List<String>` (przez
  `PackageManager.getPackageInfo`; manifest deklaruje `<queries>` z tymi
  pakietami, bo Android 11+ ukrywa listę aplikacji).
- `launch(spec: Map) -> null | String(error)` — buduje Intent: pakiet/aktywność
  (`setClassName` gdy aktywność jest, inaczej `setPackage`), action, category,
  data + `setDataAndType(uri, "application/octet-stream")` gdy tryb `saf`/
  `provider`, extras (String/bool), flagi `FLAG_ACTIVITY_NEW_TASK` +
  opcjonalnie CLEAR_TASK/CLEAR_TOP, `FLAG_GRANT_READ_URI_PERMISSION |
  FLAG_GRANT_WRITE_URI_PERMISSION` dla URI; dodatkowo
  `grantUriPermission(package, uri, flags)` dla URI w extras. `ActivityNotFoundException`
  / `SecurityException` → zwraca komunikat błędu (string), nie crash.
- `pickRomTree() -> {uri, path?}` — `ACTION_OPEN_DOCUMENT_TREE`, po wyborze
  `takePersistableUriPermission` (read+write), zwraca tree URI i ścieżkę dla
  pamięci wewnętrznej (`primary:` → `/storage/emulated/0/…`), `null` gdy anulowano.
- Tryby URI: `provider` → `FileProvider.getUriForFile` (authority
  `dev.johniak.droplet.files`, `<external-path name="external" path="."/>`,
  `<root-path>` jako zapas dla ścieżek poza pamięcią wewnętrzną);
  `saf` → `DocumentsContract.buildDocumentUriUsingTree(tree, treeDocId + "/" + relativeToTree)`,
  gdzie `relativeToTree` = ścieżka pliku względem katalogu drzewa; gdy plik leży
  poza drzewem albo drzewa brak → błąd `saf-tree-missing` (UI: „Grant folder access”).

Drzewo SAF: Settings → Emulators → wiersz **Folder access for emulators**
(`Grant` / `Granted: <ścieżka>`), zapisywane w SharedPreferences
(`rom_tree_uri`, `rom_tree_path`). Przycisk **Browse** w dialogu katalogu ROM-ów
(z 0.5.2) zostaje osobno — ale gdy użytkownik wybierze tam folder, zapisujemy
też jego tree URI, więc zwykle drugie klikanie nie jest potrzebne.

## 6. Aplikacja (Dart)

- `lib/core/platform/launcher_port.dart` (`coverage:ignore-file`):
  `LauncherPort { installedPackages(List<String>); launch(LaunchRequest) -> String?; pickRomTree() -> RomTree? }`
  + provider `launcherPortProvider`; fake w `test/fakes`.
- `lib/core/launch/emulator_catalog.dart`: `EmulatorSpec{id, name, package, activity?, template}`, `catalogFor(systemCode) -> List<EmulatorSpec>`.
- `lib/core/launch/launch_plan.dart`: `bootFile`, `resolveTemplate(spec, romPath, romTree?) -> LaunchRequest`, błędy planowania (brak drzewa SAF gdy szablon go wymaga).
- `lib/core/launch/emulator_settings.dart`: `EmulatorSettingsRepository` (SharedPreferences: `emulator.<system>` = id, `rom_tree_uri/path`), `emulatorChoiceProvider(system)`, `installedEmulatorsProvider(system)` (katalog ∩ zainstalowane), `effectiveEmulatorProvider(system)` = wybór, jeśli zainstalowany, inaczej pierwszy zainstalowany.
- Ekran gry: gdy `status == installed` i jest efektywny emulator i `bootFile != null` → pierwszy przycisk w dolnym pasku to **Play** (`PrimaryButton`, ikona play), obok dotychczasowe akcje. Tap → `launch`; błąd → snackbar z treścią (`Couldn't start <emulator>: <error>`; dla `saf-tree-missing`: `Grant folder access in Settings → Emulators`). Brak emulatora → tekstowy link **Set up emulator** → `/settings/emulators`.
- Settings → **Emulators** (`/settings/emulators`): wiersz dostępu do drzewa; potem per system z biblioteki (bez `bios`): nazwa systemu, dropdown zainstalowanych emulatorów (nazwa z katalogu), podtytuł `Not installed: <lista nazw>` gdy żaden nie jest zainstalowany; systemy bez wpisów w katalogu: `No known emulator`.

## 7. Testy i bramki

- Dart: katalog (każdy wpis ma poprawny szablon, `%ROM%`/`%ROMSAF%`/`%ROMPROVIDER%` dokładnie jeden), `resolveTemplate` dla każdego rodzaju placeholdera i błędów, `bootFile` dla m3u/cue/disc/switch/mod-only, settings repo, providery (fake port), ekran Emulators (pusty, z wyborami, zmiana zapisuje), ekran gry (Play widoczny/ukryty, sukces, błąd, brak drzewa, link do ustawień), router. 100% linii, `flutter analyze` czysto.
- Kotlin: nietestowany jednostkowo (jak inne porty); weryfikacja ręczna na Thorze: Eden (Switch), Azahar (3DS), melonDS (DS) uruchamiają grę z Dropletu.
- E2E na emulatorze: brak emulatorów → ekran gry pokazuje `Set up emulator`, ekran Emulators pokazuje `Not installed`.
- Wersja aplikacji `0.6.0+8`.
