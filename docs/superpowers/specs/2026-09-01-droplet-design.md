# Droplet — prywatna biblioteka ROMów (design)

Data: 2026-09-01
Status: do akceptacji

## 1. Wizja

Prywatny „Steam" do własnych dumpów. Backend na TrueNAS indeksuje bibliotekę ROMów
(read-only), aplikacja Flutter na Androidzie pięknie ją prezentuje, pobiera gry do
struktury katalogów RetroArch i zarządza lokalną kopią (w tym usuwanie ROMów bez
ruszania save'ów). Jeden użytkownik, wszystko za logowaniem.

## 2. Ustalenia z brainstormingu

| Temat | Decyzja |
|---|---|
| Źródło prawdy | Istniejące drzewo katalogów na TrueNAS, backend skanuje **read-only** |
| Systemy | Kartridże + płyty (PS1/PS2/GC…), także Switch (base + update + DLC) |
| Nazewnictwo plików | Mieszane → fuzzy matching + ręczna poprawka dopasowania okładki |
| Okładki | libretro-thumbnails (bez API key), etap 2: opisy z IGDB/ScreenScraper |
| Metadane MVP | Same okładki + nazwa + system; opisy później |
| Klient | Flutter Android; pobiera do katalogu RetroArch, umie usuwać ROMy (nie save'y) |
| Web UI | Nie — tylko Django admin do administracji |
| Auth | Jedno konto, login + hasło → długożyjący token |
| Deployment | Aplikacja Docker na TrueNAS; reverse proxy/wystawienie na świat po stronie użytkownika; na razie apka łączy się po lokalnym IP wpisanym w ustawieniach |
| Multi-file | Pobieranie plik po pliku (lepsze wznawianie dużych gier) |
| DB | SQLite (WAL) — jeden użytkownik, async taski przez Django Tasks działają na SQLite |
| Wygląd | Ciemny, premium — klimat współczesnego launchera konsolowego |
| Save sync | Etap 2 — projektujemy model pod to, budujemy po MVP |

## 3. Architektura

```
┌─────────────── TrueNAS ───────────────┐
│  Docker compose (aplikacja TrueNAS)   │
│  ┌──────────┐   ┌───────────────┐     │      ┌──────────────┐
│  │ web      │   │ worker        │     │ HTTP │ Flutter      │
│  │ Django + │   │ django-tasks  │     │◄────►│ Android      │
│  │ DRF      │   │ (skan, cover) │     │      │ (token auth) │
│  └────┬─────┘   └──────┬────────┘     │      └──────────────┘
│       │   SQLite (WAL) │              │
│       ▼                ▼              │
│  /data (db, cache okładek)  [RW]      │
│  /library (ROMy)            [RO]      │
└───────────────────────────────────────┘
```

### 3.1 Backend

- Python 3.13, Django 6.x (wbudowany framework Tasks), Django REST Framework,
  `django-tasks` (backend DB + proces workera), SQLite w trybie WAL.
- Dwa procesy w jednym obrazie Docker (compose: `web` + `worker`), wspólny wolumen
  `/data`. `/library` montowany read-only.
- Konfiguracja przez zmienne środowiskowe: `LIBRARY_ROOT`, `DATA_DIR`,
  `DJANGO_SECRET_KEY`, `ALLOWED_HOSTS` itd.

### 3.2 Model danych

- **System** — katalog 1. poziomu w `/library`; kod, nazwa wyświetlana, mapowanie na
  nazwę repo w libretro-thumbnails, kolejność/ikona.
- **Game** — FK do System, tytuł znormalizowany (bez tagów regionu/wersji), tytuł
  oryginalny, slug.
- **GameFile** — FK do Game, ścieżka względna w `/library`, rola:
  `base | update | dlc | disc | support | other`, numer płyty, wersja (Switch),
  rozmiar, mtime. Tożsamość pliku = ścieżka + rozmiar + mtime (bez hashowania
  wielogigabajtowych obrazów przy skanie).
- **Cover** — 1:1 z Game; źródło (libretro/manual), plik w cache, score dopasowania,
  flaga ręcznego nadpisania (skan nie nadpisuje ręcznych poprawek).
- **ScanRun** — log skanów (start, koniec, liczba zmian, błędy).
- (Etap 2) **SaveMapping / SaveSnapshot** — patrz §3.6.

### 3.3 Skaner biblioteki

Task w tle (Django Tasks), uruchamiany ręcznie (admin/API) i okresowo:

1. Katalogi 1. poziomu → Systemy (mapa nazw katalogów RetroArch → systemy libretro;
   nieznane katalogi trafiają jako systemy „do konfiguracji" w adminie).
2. Grupowanie plików w gry:
   - `.cue` + `.bin` → jedna gra (parsowanie cue),
   - `.m3u` → gra wielopłytowa (płyty jako `disc` z numerami),
   - Switch: tagi w nazwie (`[titleid]`, `(UPD)`, `[vX]`, `(DLC)` itp.) → grupowanie
     base + updaty + DLC pod jedną grą; heurystyka + ręczna korekta w adminie,
   - pozostałe: 1 plik = 1 gra.
3. Normalizacja tytułu: zdjęcie tagów `(USA)`, `[!]`, `(Rev A)`… do wyszukiwania
   i dopasowania okładek.
4. Skan przyrostowy: porównanie po ścieżce+rozmiarze+mtime; usunięte pliki znikają
   z indeksu.

### 3.4 Okładki

- Źródło: libretro-thumbnails (GitHub, per system, bez klucza API).
- Dopasowanie: exact po nazwie pliku → exact po nazwie znormalizowanej → fuzzy
  (rapidfuzz, próg pewności). Wynik poniżej progu = brak okładki + pozycja na liście
  „do przejrzenia" w adminie.
- Admin: akcja „popraw dopasowanie" (wybór z kandydatów), upload własnej okładki.
- Cache na dysku w `/data/covers`, serwowane wyłącznie przez zautoryzowany endpoint.

### 3.5 API (DRF, wszystko za tokenem)

| Endpoint | Opis |
|---|---|
| `POST /api/auth/token/` | login + hasło → token (throttling prób) |
| `GET /api/systems/` | lista systemów z licznikami gier |
| `GET /api/games/?system=&search=&ordering=` | lista gier (paginacja, okładka-miniatura) |
| `GET /api/games/{id}/` | detale + manifest plików (role, rozmiary, wersje) |
| `GET /api/files/{id}/download` | pobieranie z obsługą HTTP Range (wznawianie) |
| `GET /api/games/{id}/cover?size=` | okładka z cache |
| `POST /api/scan/` | trigger rescanu |

Bezpieczeństwo: wszystkie endpointy wymagają tokenu; pliki serwowane tylko po
ścieżkach z indeksu (zero path traversal); throttling logowania; token w
`flutter_secure_storage` po stronie klienta.

### 3.6 Save sync (etap 2) — odpowiedź na pytanie o różne emulatory

Podejście: **konfigurowalne mapowania folderów**, nie integracje per emulator.
Użytkownik wskazuje w aplikacji foldery do backupu (np. `RetroArch/saves`,
`RetroArch/states`, folder save'ów emulatora Switcha), aplikacja robi wersjonowane
snapshoty na backend i umie je przywrócić.

- RetroArch: proste — stałe, dostępne foldery.
- Standalone (Game Boy, PSX itd.): działa, jeśli emulator trzyma save'y w dostępnym
  folderze lub pozwala go ustawić.
- Emulatory Switcha: część trzyma save'y w prywatnym storage aplikacji
  (`/data/data/...`) — **bez roota niedostępne**; obsłużymy te, które eksportują /
  pozwalają wskazać folder. To ograniczenie Androida, nie nasze.

### 3.7 Aplikacja Flutter

- Stack: Flutter (Material 3, ciemny motyw premium), Riverpod, dio,
  `background_downloader` (kolejka, powiadomienia, wznawianie via Range),
  `flutter_secure_storage`, go_router, cache obrazków z auth headerem.
- Dostęp do katalogu RetroArch: uprawnienie **All Files Access**
  (`MANAGE_EXTERNAL_STORAGE`) — aplikacja prywatna, poza Play Store, więc bez
  ograniczeń sklepu; prostsze i pewniejsze niż SAF.
- Ekrany: onboarding (adres serwera + logowanie) → biblioteka (grid okładek, filtry
  per system, szukajka) → karta gry (hero, pliki/wersje/DLC, Pobierz/Usuń) →
  pobierania (kolejka, progres) → ustawienia (folder ROMów, ścieżki per system).
- Stan „zainstalowane": porównanie lokalnych plików (nazwa + rozmiar) z manifestem gry.
- Switch na karcie gry: domyślne zaznaczenie base + najnowszy update + DLC.
- Usuwanie: kasuje wyłącznie pliki ROM danej gry; save'y/state'y nietknięte.

## 4. Obsługa błędów

- Skan: błędy pojedynczych plików logowane w ScanRun, nie przerywają skanu.
- Pobieranie: wznawianie po zerwaniu (Range); weryfikacja rozmiaru po pobraniu;
  niekompletne pliki pobierane do `.part` i przenoszone po sukcesie.
- Brak okładki: elegancki placeholder z tytułem (nie łamie siatki).
- Utrata połączenia w aplikacji: cache ostatnio pobranej biblioteki, tryb offline
  do przeglądania.

## 5. Testowanie

Polityka (obowiązuje w każdym milestone):

- **Pokrycie 100%** — twarda bramka: backend `pytest --cov --cov-fail-under=100`
  (wyłączenia tylko techniczne: migracje, settings, manage.py, wsgi); Flutter
  `flutter test --coverage` + skrypt wymuszający 100% linii z lcov. Zadanie nie
  jest ukończone, dopóki bramka nie przechodzi.
- **Automatyczne e2e** — obok testów jednostkowych każdy milestone utrzymuje suitę
  e2e: backend `backend/e2e/` (pytest + requests przeciwko realnemu deploymentowi
  z docker compose i fixture'ową biblioteką ROMów; pełny flow z HTTP Range),
  Flutter `app/integration_test/` (realne urządzenie/emulator + realny backend:
  login → biblioteka → karta gry → pobranie → usunięcie). E2e są wyłączone
  z liczenia pokrycia.
- Backend unit: testy skanera na fixture'owych drzewach katalogów (cue/bin, m3u,
  Switch base+UPD+DLC), normalizacja nazw, fuzzy matching, API (auth, Range,
  path traversal).
- Flutter unit/widget: diff manifest↔lokalne pliki, parsowanie ról, selekcja
  plików, widgety kluczowych ekranów.

## 6. Poza zakresem (świadomie)

- Wydajność wieloużytkownikowa, web UI, transkodowanie/konwersje ROMów,
  automatyczne wystawianie na świat (robi to reverse proxy użytkownika),
  integracje per emulator dla save'ów.
