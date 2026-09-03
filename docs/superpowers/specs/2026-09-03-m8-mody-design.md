# M8 — Mody jako część gry

Data: 2026-09-03. Poprzednik: M7 (katalogi per gra, skan urządzenia).

## 1. Cel

Mod (np. Pokémon Luminescent Platinum dla Brilliant Diamond) jest częścią gry:
serwer go rozpoznaje, telefon pobiera razem z grą, a użytkownik instaluje go w
emulatorze z zipa („Add mod”). Droplet nie rozpakowuje modów i nie pisze do
katalogów emulatora.

## 2. Konwencja na serwerze

```
<biblioteka>/<system>/<Gra>/mods/<plik>
```

- Każdy **plik bezpośrednio** w `mods/` (porównanie nazwy katalogu bez
  rozróżniania wielkości liter) dostaje rolę `mod`. Rozszerzenie nie ma
  znaczenia: `.zip`, `.7z`, `.rar`, `.ips`, `.bps`, `.xdelta`. Działa dla
  każdego systemu.
- Sidecary w `mods/` (`.txt`, `.md`, `.png` itd. — `SIDECAR_EXTENSIONS`) też
  dostają rolę `mod`; zasada „w mods/ wszystko jest modem” jest prostsza niż
  wyjątki. Pliki ukryte (zaczynające się od kropki) są pomijane jak wszędzie.
- **Podkatalog** w `mods/` to rozpakowany mod. Nie wchodzi do gry. Trafia do
  `LooseFile` jako **jeden wpis na podkatalog**: `relative_path` = ścieżka
  katalogu zakończona `/`, `size` = suma rozmiarów plików w środku. W adminie
  lista „Do uporządkowania” pokazuje go jak inne wpisy; podpowiedź w pomocy
  kolumny: „Spakuj mod do zipa”.
- Pliki `mods/` nigdy nie są łączone z playlistami m3u/cue ani parsowane jako
  tagi Switcha.

## 3. Switch: DLC po title id

`parse_switch`: gdy title id (16 hex) ma końcówkę:
- `000` → `base`,
- `800` → `update`,
- inną → `dlc`.

Tagi `[UPD]`/`[UPDATE]` i `[DLC]` nadal mają pierwszeństwo nad końcówką.
Plik bez title id zachowuje dzisiejsze zachowanie (tagi albo `base`).

## 4. Dane i API

- `GameFile.Role` += `MOD = "mod"` (migracja `0003_mod_role`: tylko
  `AlterField` choices).
- Pierwszy skan po aktualizacji przepisuje role istniejących plików w `mods/`
  (`_sync_group` aktualizuje `role` przy zmianie — potwierdzić w planie, dopisać
  jeśli nie).
- API bez nowych endpointów. `files[].role == "mod"`,
  `files[].name == "mods/<plik>"`. `sorted_files`: kolejność ról
  `base, update, dlc, disc, support, mod, other`.
- Manifest niezmieniony strukturalnie (niesie już ścieżki względne).

## 5. Aplikacja

- `FileRole.mod`, etykieta `Mod`. Nieznane role nadal → `other`.
- `defaultSelection`: mody zawsze wybrane (zasada „wszystko poza update’ami”
  już to daje; test to przybija).
- Stan instalacji: mod w `wanted`, więc brak moda = `partial`. Usunięcie gry
  kasuje mody (są w `presentPaths`). `updateAvailable` bez zmian (tylko
  base+update).
- Ścieżka na telefonie: `pathFor(system, folder, 'mods/<plik>')` →
  `<ROMs>/<system>/<Gra>/mods/<plik>`. `buildTask` dzieli już podkatalogi.
  Skan urządzenia (`scanDevice`) czyta rekurencyjnie folder gry i zwraca nazwy
  względne z prefiksem `mods/` — istniejąca logika z M7 dla płyt w
  podkatalogach; test to potwierdza.
- Ekran gry: grupa **Mods** na liście plików (przez `roleLabels`). Pod grupą
  jedna linia: `Install in the emulator: Add mod → pick the zip from
  <ścieżka katalogu mods na telefonie>` oraz przycisk `Copy path`
  (`Clipboard.setData`), snackbar `Path copied`. Linia i przycisk pokazują się
  tylko, gdy gra ma co najmniej jeden plik `mod`.
- Ekran systemu/półki: bez zmian.

## 6. Przypadki brzegowe (świadome)

- Podmiana zipa na nowszy: nowy plik → `partial` → pobranie; stary zip zostaje
  na karcie. Spójne z podmienionym update’em. Sprzątanie osieroconych plików w
  folderze gry = osobny milestone.
- Sejwy i inne zipy poza `mods/` są plikami gry (Switch: `base` bez title id).
  To porządek biblioteki, nie konwencja.
- `mods/` w katalogu systemu (poza grą) jest zwykłym katalogiem gry o nazwie
  „mods” — akceptowalne, nie wprowadzamy wyjątku.

## 7. Testy i bramki

- Backend, `pytest --cov-fail-under=100`: grupowanie (`mods/` plik, sidecar w
  `mods/`, podkatalog → jeden LooseEntry z sumą, `mods/` w PSX z m3u obok,
  `.ips` w SNES), `parse_switch` końcówki `000/800/inne` + pierwszeństwo tagów,
  `sorted_files`, migracja, rescan przepisujący rolę.
- Backend e2e: fixture `switch/Hollow Knight/mods/Example Mod.zip` (kilka
  bajtów) oraz `switch/Hollow Knight/mods/Unpacked Mod/romfs/a.bin`; asercja:
  rola `mod`, nazwa `mods/Example Mod.zip`, plik rozpakowany nie występuje w
  `files[]`; `LooseFile` liczony przez admina/ORM jak w M7.
- Aplikacja, 100% linii: `roleFrom('mod')`, selekcja, `diffGame` z modem
  (brak → partial, obecny → installed, kasowanie obejmuje ścieżkę `mods/`),
  `scanDevice` z plikiem w `mods/`, ekran gry: grupa `Mods`, linia z
  podpowiedzią, `Copy path` (mock schowka przez `TestDefaultBinaryMessenger`),
  brak linii bez modów.
- Aplikacja e2e (emulator): przepływ pobierania Hollow Knight kończy się z
  zipem w `mods/` na dysku i stanem `Installed`.
- `flutter analyze` czysto; wersja aplikacji `0.4.0+4`, backend tag `v0.4.0`.
