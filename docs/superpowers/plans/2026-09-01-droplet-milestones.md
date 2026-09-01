# Droplet — plan milestone'ów

Data: 2026-09-01. Spec: `../specs/2026-09-01-droplet-design.md`.

Zasada: każdy milestone kończy się czymś **działającym i sprawdzalnym**. Kolejność
jest tak dobrana, żeby backend dało się testować z curla zanim powstanie aplikacja,
a aplikację rozwijać na prawdziwym API.

Przegląd:

| # | Milestone | Efekt |
|---|---|---|
| M0 | Fundament backendu | Działający kontener na TrueNAS z loginem |
| M1 | Skaner biblioteki | Kompletny indeks ROMów w adminie |
| M2 | Okładki | Biblioteka z okładkami + korekty w adminie |
| M3 | API dla klienta | Pełne API: listy, detale, pobieranie z Range |
| M4 | Fundament aplikacji | Flutter: login + piękna biblioteka + karta gry |
| M5 | Pobieranie na urządzenie | Download manager + stan „zainstalowane" + usuwanie |
| M6 | Szlif | Animacje, offline, dopracowanie UX |
| M7 | Save sync (etap 2) | Backup/restore save'ów na NAS |
| M8 | Pełne metadane (etap 2) | Opisy/gatunki/oceny z IGDB lub ScreenScraper |

---

## M0 — Fundament backendu

**Cel:** pusty, ale poprawnie postawiony Django w Dockerze, uruchamialny jako
aplikacja TrueNAS, z jednym kontem i logowaniem.

**Zadania:**
1. Struktura repo: `backend/` (Django), `app/` (Flutter, na razie pusty), `docs/`.
2. Projekt Django 6.x + DRF; settings przez zmienne środowiskowe
   (`LIBRARY_ROOT`, `DATA_DIR`, `DJANGO_SECRET_KEY`, `ALLOWED_HOSTS`,
   `CSRF_TRUSTED_ORIGINS`); SQLite w `/data/db.sqlite3` z włączonym WAL.
3. Konfiguracja Django Tasks + `django-tasks` (backend DB) i proces workera.
4. Auth: endpoint `POST /api/auth/token/` (login+hasło → token DRF,
   throttling prób logowania), `GET /api/me/` do weryfikacji tokenu.
5. Komenda `createinitialuser` (login/hasło z env) — wygodne przy pierwszym starcie.
6. `Dockerfile` (multi-stage, gunicorn) + `docker-compose.yml`: serwisy `web`
   i `worker`, wolumeny `/data` (RW) i `/library` (RO), healthcheck `GET /api/health/`.
7. Instrukcja wdrożenia na TrueNAS (custom app z compose) w `docs/deploy.md`.
8. Testy: pytest-django skonfigurowany; testy auth (zły login, throttling, token działa).

**Kryteria ukończenia:**
- `docker compose up` lokalnie i na TrueNAS: `/api/health/` odpowiada, admin działa.
- Bez tokenu każde `/api/*` (poza health i auth) zwraca 401.
- Testy przechodzą w czystym środowisku.

---

## M1 — Skaner biblioteki

**Cel:** backend zna całą kolekcję: systemy, gry, pliki z rolami — widoczne
i poprawialne w Django admin.

**Zadania:**
1. Modele: `System`, `Game`, `GameFile`, `ScanRun` (wg specu §3.2) + migracje.
2. Mapa katalogów → systemy (nazwy katalogów RetroArch/libretro, np. `Nintendo - SNES`);
   nieznany katalog tworzy System z flagą „do konfiguracji".
3. Skaner jako task w tle:
   - walk `/library`, skan przyrostowy (ścieżka+rozmiar+mtime),
   - grupowanie: parsowanie `.cue` (biny jako `support`), `.m3u` (multi-disc),
   - Switch: parser tagów nazw (`[0100ABC...]`, `(UPD)`, `[v131072]`, `(DLC)`…) →
     role `base/update/dlc`, grupowanie po title-id lub znormalizowanym tytule,
   - normalizacja tytułów (zdjęcie tagów regionu/wersji/dumpów).
4. Wyzwalanie: akcja w adminie, `POST /api/scan/`, harmonogram (np. co noc).
5. Admin: listy z filtrami/szukajką, ręczne przepięcie pliku do innej gry
   i korekta roli (poprawka błędnej heurystyki), podgląd ScanRun.
6. Testy: fixture'owe drzewa katalogów (kartridże, cue/bin, m3u, Switch z updatem
   i DLC, śmieciowe pliki), idempotencja skanu, wykrywanie usunięć, normalizacja nazw.

**Kryteria ukończenia:**
- Skan prawdziwej biblioteki na NAS kończy się bez błędów, liczby gier per system
  zgadzają się „na oko" z zawartością katalogów.
- Ponowny skan bez zmian = zero modyfikacji w DB.
- Gra Switch z updatem i DLC to jedna pozycja z poprawnymi rolami.

**Ryzyka:** nazewnictwo Switch bywa dzikie — heurystyka + korekta w adminie
zamiast pogoni za 100% automatu.

---

## M2 — Okładki

**Cel:** każda gra, którą da się dopasować, ma okładkę; reszta ma ładny placeholder
i ścieżkę ręcznej poprawki.

**Zadania:**
1. Model `Cover`; katalog cache `/data/covers` (oryginał + miniatura).
2. Klient libretro-thumbnails: pobranie listy nazw per system, pobieranie plików
   boxartów; szanowanie rate-limitów, cache indeksu nazw.
3. Task dopasowania (po skanie): exact → znormalizowany exact → fuzzy (rapidfuzz,
   próg); wynik + score zapisywane; poniżej progu = „do przejrzenia".
4. Admin: lista „bez okładki / niepewne", akcja „wybierz z kandydatów"
   (top N z fuzzy), upload własnego pliku; ręczne wybory oznaczone jako trwałe
   (kolejne skany ich nie nadpisują).
5. Endpoint `GET /api/games/{id}/cover?size=thumb|full` (za tokenem, z cache
   headerami).
6. Testy: matcher na złośliwych przypadkach (subtytuły, `&` vs `and`, regiony),
   nienadpisywanie ręcznych wyborów, generowanie miniatur.

**Kryteria ukończenia:**
- Po pełnym przebiegu większość biblioteki ma okładki; lista „do przejrzenia"
  w adminie działa i da się z niej poprawić dopasowanie w < 30 s na grę.
- Endpoint okładki wymaga tokenu.

---

## M3 — API dla klienta

**Cel:** kompletne API, na którym da się zbudować całą aplikację; testowalne curlem.

**Zadania:**
1. `GET /api/systems/` — lista z licznikami gier i metadanymi wyglądu (kolor/ikona).
2. `GET /api/games/` — paginacja, filtr po systemie, szukajka (tytuł znormalizowany),
   sortowanie (alfabetycznie, ostatnio dodane), pole `coverThumbUrl`.
3. `GET /api/games/{id}/` — manifest: pliki z rolami, rozmiarami, wersjami,
   numerami płyt; flaga `hasCover`.
4. `GET /api/files/{id}/download` — streaming z obsługą **HTTP Range** (wznawianie),
   `Content-Length`, poprawne nazwy plików; tylko ścieżki z indeksu.
5. Wersjonowanie odpowiedzi pod przyszłe rozszerzenia (spokojnie: jedno pole
   `apiVersion` w `/api/health/` wystarczy dla jednego klienta).
6. Testy: paginacja/filtry, Range (pełny plik, wznowienie od offsetu, zły zakres),
   401 bez tokenu na wszystkim, próba pobrania ścieżki spoza indeksu.

**Kryteria ukończenia:**
- Skryptem/curlem da się: zalogować, wylistować systemy i gry, pobrać okładkę,
  pobrać duży plik z przerwaniem i wznowieniem (`curl -C -`).

---

## M4 — Fundament aplikacji Flutter

**Cel:** aplikacja, w której chce się przebywać: login, biblioteka, karta gry —
w ciemnym, premium stylu. Jeszcze bez pobierania.

**Zadania:**
1. Projekt Flutter: Riverpod, go_router, dio, flutter_secure_storage; motyw
   Material 3 dark — dopracowana typografia, kolor akcentu, tła warstwowe
   (użyć skilla frontend-design przy implementacji).
2. Onboarding: adres serwera (lokalny IP:port) + login/hasło → token w secure
   storage; obsługa błędów (zły adres, złe hasło); auto-login przy starcie.
3. Klient API (dio + interceptor tokenu; wylogowanie przy 401).
4. Biblioteka: grid okładek z filtrowaniem per system (poziomy pasek systemów),
   szukajka, pull-to-refresh; cache obrazków z auth headerem; placeholder
   okładki z tytułem.
5. Karta gry: hero z okładką, tytuł, system, lista plików (role, rozmiary,
   wersje/DLC dla Switcha, płyty dla multi-disc); przyciski na razie nieaktywne
   („Pobierz" przyjdzie w M5).
6. Ustawienia: adres serwera, wylogowanie, wersja.
7. Testy: unit (parsowanie modeli API), widget (login, grid renderuje się z mocków).

**Kryteria ukończenia:**
- Na fizycznym telefonie: logowanie do backendu po lokalnym IP, płynne przeglądanie
  pełnej biblioteki z okładkami, karta gry pokazuje komplet plików.
- Wygląd zaakceptowany przez Ciebie (przegląd buildu przed zamknięciem milestone'u).

---

## M5 — Pobieranie na urządzenie

**Cel:** pełna pętla wartości: zobacz → pobierz → zagraj w RetroArch → usuń gdy brak
miejsca.

**Zadania:**
1. Uprawnienie All Files Access + ekran ustawień ścieżki bazowej ROMów
   (np. `/storage/emulated/0/RetroArch/roms` albo własna), podkatalogi per system
   (domyślna mapa nazw, edytowalna).
2. Download manager na `background_downloader`: kolejka, powiadomienia systemowe,
   progres, pauza/wznowienie (Range), pobieranie do `.part` + rename po weryfikacji
   rozmiaru; gry wieloplikowe jako grupa zadań (jedna pozycja w UI).
3. Karta gry: wybór plików do pobrania (Switch: domyślnie base + najnowszy update
   + DLC; multi-disc: wszystkie płyty + m3u/cue), przycisk „Pobierz".
4. Stan „zainstalowane": skan lokalnego katalogu przy starcie/refresh, porównanie
   z manifestem (nazwa + rozmiar); badge w gridzie i na karcie gry
   (zainstalowana / częściowo / dostępny update Switcha).
5. Usuwanie: kasuje wyłącznie pliki ROM danej gry z lokalnego katalogu; potwierdzenie;
   save'y/state'y nieruszane (nie dotykamy niczego poza plikami z manifestu).
6. Ekran „Pobierania": aktywne + historia, retry nieudanych.
7. Testy: unit na diff manifest↔lokalne pliki i wybór domyślnych plików;
   test ręczny wznowienia dużego pliku (przerwanie sieci w trakcie).

**Kryteria ukończenia:**
- Duża gra (kilka GB) pobiera się z pauzą/wznowieniem i przerwaniem Wi-Fi po drodze,
  ląduje we właściwym katalogu i RetroArch ją widzi.
- Usunięcie gry z aplikacji zostawia save'y nietknięte.
- Badge'e zainstalowania zgadzają się ze stanem dysku.

---

## M6 — Szlif („ma być piękna")

**Cel:** z „działa" do „przyjemność używania".

**Zadania:**
1. Animacje: hero transition grid→karta gry, skeleton loading, mikrointerakcje
   przycisku pobierania (progres w miejscu przycisku).
2. Tryb offline: cache biblioteki (ostatni stan), przeglądanie + zarządzanie
   lokalnymi plikami bez sieci.
3. Sortowania i widoki: ostatnio dodane na serwerze, tylko zainstalowane,
   rozmiar zajmowany per system; licznik wolnego miejsca przy pobieraniu.
4. Jakość życia: obsługa błędów z ludzkimi komunikatami, ekran „co nowego
   w bibliotece" po refreshu, ikona i splash aplikacji.
5. Przegląd całości na urządzeniu + poprawki z Twojego feedbacku.

**Kryteria ukończenia:** Twoja akceptacja po tygodniu normalnego używania —
lista zgłoszonych irytacji pusta albo świadomie odłożona.

---

## M7 — Save sync (etap 2)

**Cel:** backup i przywracanie save'ów na NAS — odpowiednik cloud saves.

**Zadania:**
1. Backend: modele `SaveMapping` (nazwa, ścieżka lokalna na urządzeniu) i
   `SaveSnapshot` (mapping, timestamp, archiwum zip w `/data/saves`, rozmiar);
   API: lista mappingów, upload snapshotu, lista/pobranie/przywrócenie snapshotu;
   retencja (np. ostatnich N snapshotów per mapping).
2. Aplikacja: ekran „Save'y" — dodanie folderu do backupu (RetroArch `saves/`
   i `states/` proponowane automatycznie, inne foldery ręcznie), backup na żądanie
   + automatyczny (np. przy starcie na Wi-Fi), przywracanie wybranego snapshotu
   z potwierdzeniem.
3. Ograniczenia jawnie w UI: emulatory trzymające save'y w prywatnym storage
   (część emulatorów Switcha) są poza zasięgiem bez roota — pokazujemy to
   przy dodawaniu folderu, nie udajemy że działa.
4. Testy: snapshot→restore round-trip, retencja, konflikt (restore nadpisuje —
   zawsze za potwierdzeniem, przed restore robimy snapshot bieżącego stanu).

**Kryteria ukończenia:** save RetroArcha zrobiony na telefonie A da się przywrócić
na telefonie B i gra kontynuuje się z tego miejsca.

---

## M8 — Pełne metadane (etap 2)

**Cel:** karta gry jak w Steamie: opis, gatunek, rok, ocena, screenshoty.

**Zadania:**
1. Wybór źródła (decyzja przed startem milestone'u): IGDB (konto Twitch, bogate
   opisy) vs ScreenScraper (retro-first, dopasowanie po hashach — pomaga przy
   niestandardowych nazwach). Model danych neutralny wobec źródła.
2. Backend: task wzbogacania (po dopasowaniu okładek), pola na Game (opis, rok,
   gatunki, ocena, screenshoty w cache), korekta dopasowania w adminie.
3. API + aplikacja: rozszerzona karta gry (opis, galeria), filtry po gatunku/roku.

**Kryteria ukończenia:** większość biblioteki ma opisy; karta gry robi efekt „wow".

---

## Kolejność i zależności

M0 → M1 → M2 → M3 → M4 → M5 → M6, potem M7 i M8 w dowolnej kolejności.
M4 można zacząć równolegle z M2/M3 na zamockowanym API, ale zamknąć dopiero
na prawdziwym backendzie.
