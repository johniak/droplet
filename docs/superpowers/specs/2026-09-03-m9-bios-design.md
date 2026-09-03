# M9 — Pliki systemowe (BIOS, firmware, klucze)

Data: 2026-09-03. Poprzednik: M8 (mody).

## 1. Cel

Miejsce w bibliotece na pliki, które nie są grami, ale emulatory ich potrzebują:
BIOS-y (PSX, Dreamcast…), firmware i `prod.keys` Switcha, klucze 3DS. Droplet
pobiera je na telefon jak grę; użytkownik wskazuje je w emulatorze.

## 2. Konwencja (zero nowej mechaniki skanera)

```
<biblioteka>/bios/<Paczka>/<pliki>
```

- `bios/` jest zwykłym katalogiem systemu o kodzie `bios` i nazwie
  „BIOS & firmware” (wpis w `systems_map`, aliasy: `bios`, `firmware`,
  `system`, bez repozytorium okładek).
- Każdy podkatalog to **paczka** = jedna „gra” tego systemu: `bios/RetroArch/`
  (scph1001.bin, dc_boot.bin…), `bios/Switch/` (`Firmware 22.5.0.zip`,
  `prod.keys`, `title.keys`). Pliki bezpośrednio w `bios/` = luzem (jak wszędzie).
- Role plików: `other`/`base` wg dzisiejszych reguł — bez znaczenia dla UI
  paczek. `is_switch=False`, więc nazwy plików nie są parsowane jak dumpy.
- Na telefonie: `<ROMs>/bios/<Paczka>/<pliki>` (ta sama ścieżka co dla gier,
  `Folders per system` może nadpisać `bios` jak każdy inny kod).

## 3. API

Bez zmian. `GET /api/systems/` zwraca `bios`, gdy ma paczki; gry, szczegóły,
manifest i pobieranie działają jak dla systemów gier.

## 4. Aplikacja

- `LibrarySnapshot` dostaje pole `supportPacks: List<GameSummary>` (gry systemu
  `bios`); `games` i `systems` **nie zawierają** systemu `bios`. Dzięki temu
  półki, wyszukiwarka, „New in library”, licznik gier w karcie serwera i filtry
  ignorują paczki. Manifest zostaje pełny (skan urządzenia zna folder `bios/`,
  więc nie zgłasza go jako nieznany; `localStateProvider` działa dla paczek).
- Ustawienia: nowa sekcja **System files** między „Downloads” a „Device”:
  karta z wierszem per paczka: tytuł, podtytuł `N files · size` (pliki z
  manifestu), trailing = pigułka stanu (`Installed` / `Partial` / brak), tap
  otwiera ekran gry (`/settings/game/:id` — trasa `game/:id` dopięta także pod
  gałęzią `/settings`, żeby nie przeskakiwać zakładki). Pod listą linia:
  `Point your emulator at <ROMs>/bios/<pack>` z przyciskiem `Copy path`
  (kopiuje `<ROMs>/bios`, snackbar `Path copied`).
- Gdy paczek nie ma: jeden wiersz `No system files on the server` z podtytułem
  `Put BIOS or firmware packs in bios/<pack>/ on the server`.
- Ekran gry dla paczki: bez zmian (pobieranie, pliki, usuwanie).

## 5. Testy i bramki

- Backend: `lookup_system("bios")`/`("firmware")`/`("system")` → kod `bios`;
  e2e fixture `bios/RetroArch/scph1001.bin` (bajty `BIOS`), asercje: system
  `bios` w `/api/systems/`, gra `RetroArch` z plikiem `scph1001.bin`; liczniki
  gier w e2e podniesione o 1. 100% pokrycia.
- Aplikacja: snapshot dzieli `bios` od gier (test providera), `New in library`
  nie liczy paczek, karta System files (pusta/pełna, pigułka stanu, tap →
  ekran gry, Copy path), 100% linii, `flutter analyze`. E2E na emulatorze:
  po zalogowaniu Settings pokazuje `RetroArch`, tap → Download → plik
  `<base>/bios/RetroArch/scph1001.bin` istnieje, `Delete from device` sprząta.
- Wersja aplikacji `0.5.0+5`, backend tag `v0.5.0`.
