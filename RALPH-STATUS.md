# RALPH-STATUS

Status pętli Ralph budującej Droplet wg planów M0–M7.

## Czeka na Jana

- **M7 na NAS-ie**: uporządkuj bibliotekę (każda gra w folderze),
  `docker compose up -d --build` (migracja 0002), a potem `manage.py scan`
  **dwa razy** — drugi przebieg musi dać `+0 ~0 -0` (pierwszy przepina pliki
  starych gier do katalogów). Przejrzyj `/admin/library/loosefile/`: gry sprzed
  M7 leżące luzem znikają z biblioteki, dopóki nie przeniesiesz ich do katalogu
  gry. W aplikacji 0.3.0 stary, płaski układ pokaże się w Ustawienia → Nieznane
  na urządzeniu, a w Ustawienia → Foldery per system puste pole znaczy
  „podkatalog o nazwie kodu systemu". Szczegóły: `docs/deploy.md` §4.

- **M1 Task 11 kroki 2–4 — skan prawdziwej biblioteki na TrueNAS.** Wymaga realnego
  NAS-a z Twoimi ROMami:
  1. `docker compose build && docker compose up -d`, potem
     `docker compose exec web python manage.py scan`.
  2. Porównaj liczby gier per system w adminie z zawartością katalogów „na oko";
     rozjazdy (złe grupowanie Switcha, nieznane katalogi) popraw w adminie albo
     dopisz aliasy do `backend/library/scanner/systems_map.py`.
  3. Drugi `manage.py scan` musi dać `+0 ~0 -0` (idempotencja na realnych danych).
  4. Ustaw nocny cron na TrueNAS wg `docs/deploy.md` §6
     (`docker exec <kontener-web> python manage.py scan`, 03:00).

- **M2 Task 8 krok 3 — przegląd okładek na realnej kolekcji.** Po skanie prawdziwej
  biblioteki sprawdź w adminie (`/admin/library/game/?has_cover=no`), ile gier nie ma
  okładki, i przeklikaj 5–10 poprawek akcją „Pokaż kandydatów okładki (top 5)" →
  wpisz `match_name` w `/admin/covers/cover/` → akcja „Pobierz ponownie wg match_name".
  Każda poprawka powinna zajmować poniżej 30 s — to kryterium akceptacji M2.
  Okładki Switcha wgrywasz ręcznie (upload w `CoverAdmin`), bo libretro-thumbnails
  nie ma repo dla tej konsoli.

- **M3 Task 6 - smoke na realnym NAS-ie.** Skrypt `scripts/smoke.sh` jest zweryfikowany
  na zywym deploymencie lokalnym (biblioteka z plikiem 300 kB: `RESUME OK`, `401 OK`,
  `SMOKE PASSED`). Na TrueNAS-ie uruchom go na swoich danych:
  `./scripts/smoke.sh http://<ip-nas>:8000 <user> <haslo>` - oczekiwane `RESUME OK`,
  `401 OK`, `SMOKE PASSED`.

- **M4 - uruchomienie aplikacji na fizycznym Androidzie.** Nie mam podpietego
  urzadzenia ani emulatora Androida (widoczne sa tylko Chrome i iPhone), wiec
  `flutter run` na Androidzie i wizualna akceptacja wygladu sa po Twojej stronie.
  Zweryfikowane automatycznie: `flutter test`, bramka pokrycia 100%
  (`./scripts/check_coverage_app.sh`) i `flutter build apk --debug` (APK sie buduje).

- **M4 Task 8 krok 5 - odbior M4 na urzadzeniu (akceptacja wygladu).** Zbuduj i wgraj
  APK (`cd app && flutter build apk --debug`, plik w `app/build/app/outputs/flutter-apk/`),
  potem przejdz checkliste: logowanie po lokalnym IP; restart aplikacji nie wymaga
  ponownego logowania; biblioteka przewija sie plynnie z okladkami; filtr systemem
  i szukajka dzialaja; karta gry pokazuje komplet plikow z rolami i rozmiarami;
  wylogowanie wraca do ekranu logowania. **Akceptacja wygladu jest bramka zamkniecia M4.**

- **M4 Task 9 krok 3 - e2e aplikacji na urzadzeniu.** Wymaga telefonu z Androidem
  podpietego przez adb (u mnie `flutter devices` widzi tylko Chrome i iPhone):
  `E2E_SERVER=http://<ip-hosta>:8800 ./scripts/e2e_app.sh` - skrypt stawia backend
  e2e z compose, sprawdza `adb devices`, uruchamia `integration_test` i sprzata.
  Telefon i host musza byc w tej samej sieci.

- **M5 Task 2 krok 4 - uprawnienie All Files Access na telefonie.** Sprawdz recznie,
  ze przycisk "Przyznaj" w Ustawieniach -> Pobieranie przechodzi przez systemowy ekran
  i wraca ze statusem "Przyznane", oraz ze katalog bazowy da sie utworzyc.

- **M5 Task 8 krok 2 - e2e pobierania na urzadzeniu.** Po podpieciu telefonu:
  `E2E_SERVER=http://<ip-hosta>:8800 ./scripts/e2e_app.sh` uruchomi oba pliki
  `integration_test` (logowanie/biblioteka oraz pobranie + usuniecie gry).

- **M5 Task 9 - checklista na urzadzeniu i realnym NAS.** Szesc scenariuszy, ktorych
  automat nie pokryje (RetroArch, wielogigabajtowe pliki, zrywanie sieci, zabicie
  aplikacji w trakcie pobierania) - spisane w `docs/testing-m5.md`; wypelnij kolumne
  Wynik. Punkt 5 (usuwanie ROM-ow bez ruszania `saves/`/`states/`) to kluczowe
  kryterium bezpieczenstwa M5.

- **M6 Task 1 krok 4 - ogledziny animacji na telefonie.** Sprawdz, czy przejscie
  grid -> karta gry (Hero na okladce) jest plynne i czy przy okladce z cache nie
  "mruga" placeholder.

- **M6 Task 2 krok 5 - test trybu offline na telefonie.** Wlacz tryb samolotowy:
  biblioteka ma sie otworzyc z banerem "Tryb offline", a przycisk Pobierz ma byc
  nieaktywny; po powrocie sieci i odswiezeniu baner znika.

- **M6 Task 4 krok 4 - ikona i splash na telefonie.** Ikona jest generowana skryptem
  `scripts/make_icon.py` (kropla w akcencie na ciemnym tle) i wygenerowana przez
  `flutter_launcher_icons` jako adaptive icon; splash to jednolity `#0E1116`.
  Sprawdz na launcherze, czy wyglada dobrze - jesli nie, podmien
  `app/assets/icon/icon.png` na wlasny projekt i odpal `dart run flutter_launcher_icons`.

- **M6 Task 5 - tydzien uzywania i runda feedbacku (bramka zamkniecia M6 i MVP).**
  Release APK jest zbudowany (`app/build/app/outputs/flutter-apk/app-release.apk`,
  51 MB). Zainstaluj go, uzywaj przez ~tydzien i notuj uwagi w `docs/feedback-m6.md`.
  Potem przechodzimy liste razem: kazdy punkt to albo naprawa, albo swiadome
  odlozenie z decyzja w tabeli. Bramki automatyczne w chwili wydania buildu:
  backend 117 testow / 100%, backend e2e 12, aplikacja 148 testow / 1002 linie 100%.

- **Redesign Glass — akceptacja na urządzeniu.** `cd app && flutter build apk --debug`,
  wgraj, sprawdź: pasek statusu czytelny na jasnej okładce (Pokémon Crystal), wstecz
  widoczny na karcie gry i w widoku systemu, dolna nawigacja nie zasłania ostatniego
  wiersza list, pull‑to‑refresh na ekranie głównym, e2e:
  `E2E_SERVER=http://<ip>:8800 ./scripts/e2e_app.sh`.
  Sprawdź też: tryb nawigacji trójprzyciskowej (dolne wcięcie systemowe jest
  wtedy najwyższe — listy nie mogą chować ostatniego wiersza pod paskiem), duża
  skala czcionek (Ustawienia → Wyświetlanie → Rozmiar czcionki na maksimum),
  animacja wejścia (push) na przezroczysty scaffold karty gry.
  Status automatyczny: **e2e zielone na emulatorze** (`droplet`, API 35,
  `E2E_SERVER=http://10.0.2.2:8800`, 2026-09-02) — oba pliki `integration_test`
  przechodzą (`All tests passed!`, `+2 -0`). Wizualna akceptacja na fizycznym
  telefonie nadal po Twojej stronie.

- **Emulator Androida jest gotowy** — `droplet` (API 35, arm64) w `~/Library/Android/sdk`.
  Odpalenie: `~/Library/Android/sdk/emulator/emulator -avd droplet &`, potem
  `cd app && flutter run` albo `adb install -r build/app/outputs/flutter-apk/app-release.apk`.
  Z emulatora backend na hoście jest pod `http://10.0.2.2:8000`.
  Uwaga: `MANAGE_EXTERNAL_STORAGE` na emulatorze nadaje sie przez
  `adb shell appops set --uid dev.johniak.droplet MANAGE_EXTERNAL_STORAGE allow`.

## Blokery

(brak)

## Rozjazdy planu z rzeczywistością

- **M7 Task 9 — `setState() during build` z Riverpoda w e2e (naprawione).** Pierwszy
  przebieg e2e po M7 wywalał `download_flow_test` na asercji Riverpoda
  (`setState() or markNeedsBuild() called during build` na
  `UncontrolledProviderScope`). Powtórzone na commicie `6f48d9b` (Task 7), więc
  regresja przyszła z indeksu urządzenia, nie z Taska 8. Dwie przyczyny:
  (1) `DeviceIndexController` **oglądał** (`watch`) bibliotekę i ustawienia, więc
  zmiana katalogu ROMów unieważniała cały indeks; unieważniony provider
  przebudowywał się leniwie — przy wznowieniu subskrypcji zakładki (`TickerMode`),
  czyli w fazie layoutu. Teraz `listen` + `refresh()`, provider nigdy nie jest
  „brudny". (2) `homeShelvesProvider`/`systemGamesProvider` oglądały
  `installedIdsProvider`, więc w łańcuchu provider→provider→provider brudne
  ogniwo w środku unieważniało się w środku budowania. Teraz zbiory liczą się
  w tych providerach wprost z indeksu (`installedFrom`/`updatableFrom`), a
  `installedIdsProvider`/`updatableIdsProvider` zostają dla widgetów.
  Po naprawie oba pliki `integration_test` przechodzą (`All tests passed!`, `+2`).
- **M7 Task 9 — `pumpAndSettle` nie czeka na sieć (naprawione w testach).**
  `pumpAndSettle()` wraca, gdy nie ma zaplanowanych klatek, a zapytanie HTTP
  w locie żadnej nie planuje — karta gry potrafiła być jeszcze szkieletem, gdy
  test szukał „Aktualizacja"/„Pobierz ·". Oba pliki `integration_test` mają teraz
  helper `pumpUntil`, który dopompowuje realnym czasem (do 20 s).

- **Task 13 — overflow w `HomeSkeleton` na realnym ekranie (naprawione).** Pierwszy
  przebieg e2e (`E2E_SERVER=http://10.0.2.2:8800 ./scripts/e2e_app.sh` na emulatorze
  `droplet`, API 35) łapał realny bug aplikacji, nie problem testu: `RenderFlex
  overflowed by 29 pixels on the right` w `Row` z
  `app/lib/features/home/home_screen.dart:257` (skeleton ładowania — 4×
  `PulseBox(width: 96)` w sztywnym `Row` bez scrolla, łącznie 424 dp, więcej niż
  szerokość ekranu emulatora ~395 dp), wywalający obie testy integracyjne mimo
  poprawnych asercji nawigacji/pobierania. Naprawione: `Row` zamieniony na
  `ListView(scrollDirection: Axis.horizontal, physics:
  NeverScrollableScrollPhysics(), ...)` w tym samym `SizedBox(height: 154)` — ten
  sam wygląd, ale content jest przycinany zamiast przepełniać layout. Dodany test
  regresyjny `test/features/home_screen_test.dart` („skeleton does not overflow on
  a narrow phone screen", `setSurfaceSize(360, 800)` + `takeException()` == null).
  Po fixie e2e na emulatorze zielone (`All tests passed!`, `+2 -0`).
- **Task 13 — `scripts/e2e_app.sh` sprzątanie kontenerów (naprawione).** `trap
  cleanup EXIT` wołał `$COMPOSE down -v` już po `cd app`, więc ścieżki
  `docker-compose*.yml` były względne do złego katalogu i czyszczenie faktycznie
  się nie wykonywało (`open .../app/docker-compose.yml: no such file or
  directory`) — kontenery `droplet-web-1`/`droplet-worker-1` zostawały. Naprawione:
  skrypt zapamiętuje `ROOT="$(cd "$(dirname "$0")/.." && pwd)"` na starcie,
  `cleanup()` robi `cd "$ROOT"` przed `down -v`, a krok `flutter test` jest w
  podshellu `(cd app && ...)`, więc `cd` w nim nie zmienia cwd głównego skryptu.
  Zweryfikowane: po przebiegu `docker compose ... ps` / `docker ps` puste.

- **M0 Task 1 — backend Tasks**: `django-tasks` 0.12+ nie zawiera już backendu DB
  (`django_tasks.backends.database` zostało wydzielone do pakietu `django-tasks-db`),
  a Django 6.0 ma wbudowany `django.tasks`. Rozwiązanie minimalne: w
  `requirements.txt` jest `django-tasks-db>=0.13` zamiast `django-tasks`,
  w `INSTALLED_APPS` jest `django_tasks_db`, `TASKS.default.BACKEND` =
  `django_tasks_db.DatabaseBackend`, a w testach
  `django.tasks.backends.immediate.ImmediateBackend`. Taski definiujemy przez
  `from django.tasks import task`. Komenda workera `manage.py db_worker` pochodzi
  z `django-tasks-db` (bez zmian względem planu).
- **M0 Task 1 — bramka pokrycia**: żeby `--cov-fail-under=100` przechodziło już przy
  zamknięciu Task 1, `core/views.py` (pusty stub Django) usunięto (Task 2 tworzy go
  od nowa), a do `core/tests/test_settings.py` dopisano smoke test ładowania
  `ROOT_URLCONF` (`test_root_urlconf_loads`). Żadnych wyłączeń pokrycia poza
  technicznymi z planu.
- **M0 Task 5 — status wyniku taska**: plan zakłada `result.status.name == "SUCCEEDED"`,
  ale w Django 6 / django-tasks 0.12+ status nazywa się `SUCCESSFUL`
  (`TaskResultStatus.SUCCESSFUL`). Test w `core/tests/test_tasks.py` używa poprawnej
  nazwy. Migracje backendu DB pojawiają się pod etykietą aplikacji
  `django_tasks_database` (pakiet `django_tasks_db`).
- **M0 Task 8 — harness e2e**: `docker-compose.yml` wymaga zmiennych
  (`${DJANGO_SECRET_KEY:?set me}` itd.) już na etapie interpolacji, zanim compose
  scali override, więc `scripts/e2e_backend.sh` eksportuje te zmienne przed
  wywołaniem compose'a (i tak nadpisuje je `docker-compose.e2e.yml`). Dodatkowo
  pytest odpalany jest w subshellu, żeby trap `down -v` widział pliki compose'a
  z korzenia repo.
- **Zasada ogólna (od M1 Task 1)**: gdy fragmenty kodu z planu nie są w całości pokryte
  testami z planu (np. metody `__str__` modeli), dopisuję minimalny, prawdziwy test
  zamiast wyłączenia pokrycia. Puste stuby generowane przez `startapp`
  (`library/views.py`) usuwam, bo tworzą je dopiero późniejsze taski.
- **M1 Task 5 — pomijanie ukrytych plików**: plan sprawdza `p.parts` (całą ścieżkę
  absolutną), przez co katalog ukryty gdziekolwiek wyżej w drzewie (np.
  `/home/x/.local/roms`) wyciąłby całą bibliotekę. W implementacji sprawdzam
  `p.relative_to(library_root).parts` — semantyka „ukryte w bibliotece", zgodna
  z intencją planu.
- **M2 Task 3 — scorer fuzzy**: plan każe użyć `fuzz.token_sort_ratio`, ale wtedy jego
  własny test (`"zelda a link to the past"` → „Legend of Zelda, The - A Link to the
  Past (USA)") dostaje 77.4 i nie przechodzi progu 85. Użyłem `fuzz.WRatio`
  (85.5 dla tego przypadku, 64.1 dla kontrprzykładu „wario land 4" — więc próg
  nadal działa). Koszt: WRatio zawyża wynik przy krótkich podciągach (np. samo
  „mario" → 90 dla „super mario world"); łagodzi to reguła exact-match oraz
  ręczne poprawki dopasowania w adminie (Task 6).
- **M2 Task 7 — blokada sieci a e2e**: autouse fixture `_no_network` z `backend/conftest.py`
  (M2 Task 1) obejmowała także `backend/e2e/`, przez co cała suita e2e wywalała się na
  `RuntimeError: Sieć zablokowana`. Rozwiązane nadpisaniem fixture o tej samej nazwie
  w `backend/e2e/conftest.py` (no-op) — blokada dalej działa w testach jednostkowych.
  Dodatkowo `DROPLET_AUTO_COVERS` doszło do `docker-compose.yml` (default `1`),
  `docker-compose.e2e.yml` (`0`) i tabelki env w `docs/deploy.md`.
- **M2 Task 8 — brak repo Switcha w libretro-thumbnails**: bieg `match_all()` na realnym
  GitHubie pokazał, że `https://api.github.com/repos/libretro-thumbnails/Nintendo_-_Nintendo_Switch`
  zwraca 404 — ta konsola nie ma repo z boxartami. Żeby nie generować błędu przy każdym
  dopasowaniu, `SystemSpec("switch", ...)` ma teraz pusty `thumbnail_repo` (a `match_all`
  i tak pomija systemy bez repo). Okładki Switcha wgrywa się ręcznie w adminie —
  ścieżka przewidziana w spec §3.4.
- **M4 Task 1 - Gradle vs Java 24**: wygenerowany przez `flutter create` wrapper
  (Gradle 8.12 + AGP 8.7.3) nie buduje sie na zainstalowanej Javie 24
  (`java-gradle-incompatibility`). Podbite minimalnie do Gradle 8.14.3 + AGP 8.9.1 -
  `flutter build apk --debug` przechodzi.
- **M4 Task 4 - Riverpod 3 API**: zainstalowany `flutter_riverpod` to 3.3.2, gdzie
  `AsyncValue.valueOrNull` juz nie istnieje (`value` jest nullowalne), a wyjatek
  rzucony w providerze jest opakowany w `ProviderException` (typ nieeksportowany
  z `flutter_riverpod`). Kod uzywa `.value`, a test sprawdza komunikat wyjatku
  zamiast `throwsStateError`.
- **M4 Task 5 - typ `Override`**: `flutter_riverpod` 3.3.2 nie eksportuje typu
  `Override`, wiec helper testowy przyjmuje samo `ApiClientFactory` zamiast listy
  nadpisan.
- **M4 Task 6 - brak `StateProvider` w Riverpod 3**: `selectedSystemProvider`
  i `searchQueryProvider` to `NotifierProvider` z jawnymi metodami (`select`,
  `update`) zamiast `StateProvider` (usunietego z glownego API Riverpoda 3).
- **M4 Task 6 - `GameCard` bez sesji**: karta czyta `apiClientProvider` tylko dla
  gry z okladka (`hasCover`), dzieki czemu test widgetowy z planu (gry bez okladek,
  bez nadpisanej sesji) dziala i nie strzela po HTTP.
- **M5 Task 5 - katalog taska i wersje pluginow**: (1) `background_downloader` trzyma
  `directory` wzglednie wobec `baseDirectory`, wiec zapisany katalog nie ma wiodacego
  `/` (dostawia je `Task.filePath()` przy `BaseDirectory.root`) - test i fake
  odzwierciedlaja to zachowanie zamiast asercji z planu. (2) `permission_handler` 13/14
  wymaga AGP 9 i Kotlina 2.3 (nasz Flutter 3.32.8 ma AGP 8.x) - przypiete `^12.0.0`.
  (3) Do zbudowania APK z nowymi pluginami trzeba bylo podbic `compileSdk` do 36
  i Kotlin Gradle plugin do 2.2.20 oraz zamienic `kotlinOptions` na
  `kotlin { compilerOptions { ... } }`.
- **M5 Task 6 - async dart:io nie dziala w `testWidgets`**: `Directory`/`File` w wersji
  asynchronicznej nigdy nie konczy sie w widget testach (strefa fake-async nie pompuje
  realnej petli zdarzen - potwierdzone eksperymentem: `createTemp()` zawiesza test).
  Dlatego `deleteLocalFiles` i `scanSystemDir` uzywaja IO synchronicznego (kilka plikow
  lokalnie, koszt pomijalny), a testy tworza katalogi przez `createTempSync()`.
  Bez tego badge instalacji na kazdej karcie gry bylby nietestowalny.
- **M5 Task 6 - test z M4 zaktualizowany**: `game_detail_test.dart` mial test
  "download button is not active yet" (przycisk byl wylaczony do M5). Task 6 wlacza
  pobieranie, wiec test usunieto - zachowanie przycisku pokrywa `game_actions_test.dart`.
- **M5 Task 7 - `FileDownloader().updates` to strumien jednorazowy**: drugi
  `DownloadManager` w tym samym isolate (kolejny `ProviderContainer`, np. w testach)
  wywalal sie na `Bad state: Stream has already been listened to`. Adapter trzyma
  teraz jeden `asBroadcastStream()` na poziomie modulu.
- **M6 Task 2 - `.future` errorujacego providera w Riverpod 3**: gdy `FutureProvider`
  rzuci, a nikt go nie sluchа, `provider.future` zostaje wiszacy (timeout w tescie).
  Test sprawdza wiec stan (`container.listen` + `AsyncValue.hasError`) zamiast
  awaitowac future.
- **M6 Task 3 - wolne miejsce bez `disk_space_plus`**: plan proponowal pakiet
  `disk_space_plus`, ale `DownloaderPort.freeBytes` realizuje to bez nowej
  zaleznosci (wywolanie `df -k` w adapterze; blad -> `null`, czyli kontrola
  pomijana). Lista plikow z `coverage:ignore-file` sie nie rozszerzyla.
