# M4 — Fundament aplikacji Flutter: plan implementacji

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aplikacja Android (Flutter): onboarding (adres serwera + logowanie), ciemna premium biblioteka z okładkami, karta gry z manifestem plików. Bez pobierania (to M5).

**Architecture:** Flutter + Riverpod (stan), go_router (nawigacja z guardem sesji), dio (HTTP, interceptor tokenu, wylogowanie przy 401), flutter_secure_storage (serwer+token), cached_network_image z nagłówkiem auth. Warstwy: `core/` (API, sesja, modele) bez Fluttera w logice → testowalne unitowo; `features/` ekranami.

**Tech Stack:** Flutter (stable), flutter_riverpod, go_router, dio, flutter_secure_storage, cached_network_image; dev: http_mock_adapter, flutter_test.

**Spec:** `docs/superpowers/specs/2026-09-01-droplet-design.md` (§3.7); kontrakt JSON: plan M3, sekcja Global Constraints.

## Global Constraints

- Kontrakt API dokładnie jak w planie M3 (snake_case, endpointy `/api/...`, nagłówek `Authorization: Token <t>`).
- Cel platformy: wyłącznie Android; `minSdkVersion 26`.
- Ruch po HTTP w LAN: w `AndroidManifest.xml` `android:usesCleartextTraffic="true"` (świadoma decyzja — LAN/VPN; HTTPS zapewni reverse proxy użytkownika).
- Kierunek wizualny: ciemny premium (launcher konsolowy). **Przed implementacją motywu i ekranów wykonawca ładuje skill `frontend-design:frontend-design`** i trzyma się jednej spójnej palety zdefiniowanej w `lib/app/theme.dart`.
- Logika (modele, klient API, sesja) bez importów z `package:flutter` — testowalna czystym `dart test` przez `flutter test`.
- **Pokrycie 100%**: `scripts/check_coverage_app.sh` (bramka: 100% linii z lcov). Uwaga: `flutter test --coverage` raportuje **tylko pliki zaimportowane przez jakiś test** — plik bez testów jest niewidoczny, a „100%" puste. Dlatego skrypt najpierw generuje `app/test/all_imports_test.dart` importujący każdy plik z `lib/` (Task 1) i dopiero potem liczy próg. Wyłączenia wyłącznie techniczne, oznaczane w pliku markerem `// coverage:ignore-file` i ograniczone do zamkniętej listy: `*.g.dart`; `lib/core/platform/*_port.dart` (cienkie adaptery pluginów: `permissions_port.dart`, `downloader_port.dart` z M5 — klasy, których jedyną treścią są wywołania pluginu, a cała logika siedzi za interfejsem i jest testowana na fake'ach); funkcja `main()` w `lib/main.dart` (`// coverage:ignore-start` / `// coverage:ignore-end` wokół samej funkcji). `SecureKeyValueStore` NIE jest wyjątkiem — testuje się go przez `FlutterSecureStorage.setMockInitialValues`. Cała logika, provider'y i widgety: 100%. Obowiązuje przy zamykaniu KAŻDEGO zadania.
- Biegi częściowe: w trakcie TDD `flutter test test/<plik>` bez `--coverage`; bramką jest `./scripts/check_coverage_app.sh` na końcu zadania.
- Nawigacja: trasy `/game/:id`, `/settings` (i `/downloads` z M5) są **zagnieżdżone pod `/`** w GoRouter — dzięki temu `context.go('/game/7')` buduje stos `[/, /game/7]` i systemowy „wstecz" wraca do biblioteki zamiast zamykać aplikację (e2e używa `pageBack()`).
- **E2E**: suita `app/integration_test/` (pakiet `integration_test`) uruchamiana na fizycznym urządzeniu/emulatorze przeciwko backendowi e2e z compose (`scripts/e2e_app.sh`); zielone e2e = kryterium zamknięcia milestone'u.
- Commity po każdym zadaniu.

---

### Task 1: Szkielet projektu + motyw + router

**Files:**
- Create: `app/` (via `flutter create`), `app/lib/main.dart`, `app/lib/app/theme.dart`, `app/lib/app/router.dart`, `scripts/check_coverage_app.sh`
- Modify: `app/pubspec.yaml`, `app/android/app/src/main/AndroidManifest.xml`, `app/android/app/build.gradle.kts` (minSdk 26)
- Test: `app/test/smoke_test.dart`

**Interfaces:**
- Produces: `DropletApp` (MaterialApp.router, `themeMode: ThemeMode.dark`); `buildTheme() -> ThemeData` w `theme.dart` (paleta: tło `#0E1116`, powierzchnie `#161B22`, akcent `#3FB6F0`, tekst `#E6EDF3`); router z trasami `/login`, `/` (biblioteka), `/game/:id`, `/settings` — na razie trasy prowadzą do placeholderowych `Scaffold`ów podmienianych w kolejnych taskach.

- [ ] **Step 1: Scaffold**

```bash
flutter create --org dev.johniak --project-name droplet --platforms android app
cd app
flutter pub add flutter_riverpod go_router dio flutter_secure_storage cached_network_image
flutter pub add --dev http_mock_adapter integration_test --sdk-dev integration_test:flutter
```

(jeśli składnia `--sdk-dev` nie zadziała w zainstalowanym Flutterze, dodaj do `pubspec.yaml` ręcznie: `integration_test: {sdk: flutter}` w `dev_dependencies`).

W `AndroidManifest.xml` (application): `android:usesCleartextTraffic="true"`, label `Droplet`. W gradle: `minSdk = 26`.

Utwórz bramkę pokrycia `scripts/check_coverage_app.sh` (korzeń repo):

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../app"

# 1. Plik importujący WSZYSTKIE źródła — bez niego lcov nie widzi plików bez testów
#    i „100%" nic nie znaczy. Generowany, w .gitignore.
python3 - <<'EOF'
import pathlib
files = sorted(
    p for p in pathlib.Path("lib").rglob("*.dart") if not p.name.endswith(".g.dart")
)
lines = [
    "// GENERATED by scripts/check_coverage_app.sh - nie edytowac recznie.",
    "// ignore_for_file: unused_import, directives_ordering",
    "",
]
lines += [f"import 'package:droplet/{p.relative_to('lib').as_posix()}';" for p in files]
lines += ["", "void main() {}", ""]
pathlib.Path("test/all_imports_test.dart").write_text("\n".join(lines))
EOF

# 2. Testy z pokryciem
flutter test --coverage

# 3. Próg 100%. Pomijane: *.g.dart oraz pliki z markerem `// coverage:ignore-file`
#    w pierwszych 5 liniach (lista dozwolonych plików: Global Constraints).
python3 - <<'EOF'
import pathlib, re, sys

ALLOWED_IGNORE = re.compile(r"^lib/core/platform/[a-z_]+_port\.dart$")
covered = total = 0
record_file = ""
skip = False
missing = {}
with open("coverage/lcov.info") as f:
    for line in f:
        if line.startswith("SF:"):
            record_file = line.strip()[3:]
            head = "".join(pathlib.Path(record_file).read_text().splitlines(True)[:5])
            marked = "// coverage:ignore-file" in head
            if marked and not ALLOWED_IGNORE.match(record_file):
                print(f"ERROR: {record_file} ma coverage:ignore-file poza dozwolona lista")
                sys.exit(1)
            skip = record_file.endswith(".g.dart") or marked
            continue
        if skip:
            continue
        m = re.match(r"DA:(\d+),(\d+)", line)
        if m:
            total += 1
            if int(m.group(2)) > 0:
                covered += 1
            else:
                missing.setdefault(record_file, []).append(int(m.group(1)))
pct = 100.0 * covered / total if total else 100.0
print(f"coverage: {covered}/{total} lines = {pct:.2f}%")
for path, lines in missing.items():
    print(f"  MISSING {path}: {lines[:25]}{' ...' if len(lines) > 25 else ''}")
sys.exit(0 if pct >= 100.0 else 1)
EOF
```

`chmod +x scripts/check_coverage_app.sh`; do `/.gitignore` dopisz `app/test/all_imports_test.dart` i `app/coverage/`.

Uwaga do `lib/main.dart`: funkcja `main()` (i tylko ona) w bloku `// coverage:ignore-start` … `// coverage:ignore-end` — jeśli `flutter test --coverage` w zainstalowanej wersji nie respektuje tych markerów, wyciągnij ciało `main()` do `Future<void> bootstrap()` i przetestuj `bootstrap` (nie rozszerzaj listy wyjątków).

- [ ] **Step 2: Failing test**

`app/test/smoke_test.dart`:

```dart
import 'package:droplet/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots to login route', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DropletApp()));
    await tester.pumpAndSettle();
    expect(find.text('Droplet'), findsWidgets);
  });
}
```

- [ ] **Step 3: Implementacja**

`app/lib/app/theme.dart`:

```dart
import 'package:flutter/material.dart';

const kBg = Color(0xFF0E1116);
const kSurface = Color(0xFF161B22);
const kAccent = Color(0xFF3FB6F0);
const kText = Color(0xFFE6EDF3);
const kTextDim = Color(0xFF8B949E);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    colorScheme: base.colorScheme.copyWith(
      primary: kAccent,
      surface: kSurface,
      onSurface: kText,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      foregroundColor: kText,
      elevation: 0,
    ),
  );
}
```

`app/lib/app/router.dart` — `GoRouter` z czterema trasami; na razie ekrany-placeholdery:

```dart
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

GoRouter buildRouter() => GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const _Stub('Droplet')),
        GoRoute(
          path: '/',
          builder: (_, __) => const _Stub('Biblioteka'),
          routes: [
            // zagnieżdżone: go('/game/7') => stos [/, /game/7], „wstecz" działa
            GoRoute(
                path: 'game/:id',
                builder: (_, s) => _Stub('Gra ${s.pathParameters['id']}')),
            GoRoute(
                path: 'settings',
                builder: (_, __) => const _Stub('Ustawienia')),
          ],
        ),
      ],
    );

class _Stub extends StatelessWidget {
  const _Stub(this.title);
  final String title;
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(title)));
}
```

`app/lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';

void main() => runApp(const ProviderScope(child: DropletApp()));

class DropletApp extends StatelessWidget {
  const DropletApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Droplet',
        theme: buildTheme(),
        routerConfig: buildRouter(),
      );
}
```

- [ ] **Step 4: PASS** — `flutter test`, `./scripts/check_coverage_app.sh` (100%) i `flutter run` na urządzeniu (aplikacja startuje na ciemnym stubie).

- [ ] **Step 5: Commit** — `git add app scripts && git commit -m "feat: scaffold Flutter app with dark theme and router"`

---

### Task 2: Modele API

**Files:**
- Create: `app/lib/core/api/models.dart`
- Test: `app/test/core/models_test.dart`

**Interfaces:**
- Produces (odbicie kontraktu z M3):

```dart
enum FileRole { base, update, dlc, disc, support, other }
class SystemModel { int id; String code; String name; int gameCount; }
class GameSummary { int id; String title; String systemCode; bool hasCover; int totalSize; }
class GameFileModel { int id; String name; String relativePath; FileRole role;
                      int? discNumber; String version; int size; }
class GameDetail extends GameSummary { String systemName; List<GameFileModel> files; }
class GamePage { int count; List<GameSummary> results; bool hasNext; }
```

Każda klasa ma `factory ....fromJson(Map<String, dynamic>)`; `FileRole` parsowany z nieznaną wartością → `other`.

- [ ] **Step 1: Failing testy**

`app/test/core/models_test.dart`:

```dart
import 'package:droplet/core/api/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GameDetail parses manifest', () {
    final json = {
      'id': 7,
      'title': 'Hollow Knight',
      'system_code': 'switch',
      'system_name': 'Switch',
      'has_cover': true,
      'total_size': 6,
      'files': [
        {
          'id': 1, 'name': 'hk.nsp', 'relative_path': 'switch/hk.nsp',
          'role': 'base', 'disc_number': null, 'version': '', 'size': 1,
        },
        {
          'id': 2, 'name': 'upd.nsp', 'relative_path': 'switch/upd.nsp',
          'role': 'update', 'disc_number': null, 'version': 'v196608', 'size': 2,
        },
      ],
    };
    final game = GameDetail.fromJson(json);
    expect(game.files[1].role, FileRole.update);
    expect(game.files[1].version, 'v196608');
  });

  test('unknown role maps to other', () {
    final f = GameFileModel.fromJson({
      'id': 1, 'name': 'x', 'relative_path': 'x', 'role': 'weird',
      'disc_number': null, 'version': '', 'size': 0,
    });
    expect(f.role, FileRole.other);
  });

  test('GamePage reads pagination', () {
    final page = GamePage.fromJson({'count': 1, 'next': null, 'results': []});
    expect(page.hasNext, false);
  });
}
```

- [ ] **Step 2: FAIL** — `flutter test test/core/models_test.dart`

- [ ] **Step 3: Implementacja** — `models.dart` z klasami wg Interfaces; wzorzec parsowania:

```dart
enum FileRole { base, update, dlc, disc, support, other }

FileRole roleFrom(String raw) => FileRole.values.firstWhere(
      (r) => r.name == raw,
      orElse: () => FileRole.other,
    );

class GameFileModel {
  const GameFileModel({
    required this.id, required this.name, required this.relativePath,
    required this.role, required this.discNumber, required this.version,
    required this.size,
  });

  final int id;
  final String name;
  final String relativePath;
  final FileRole role;
  final int? discNumber;
  final String version;
  final int size;

  factory GameFileModel.fromJson(Map<String, dynamic> j) => GameFileModel(
        id: j['id'], name: j['name'], relativePath: j['relative_path'],
        role: roleFrom(j['role']), discNumber: j['disc_number'],
        version: j['version'] ?? '', size: j['size'],
      );
}
```

(analogicznie `SystemModel`, `GameSummary`, `GameDetail` — z `system_name` i listą `files` — oraz `GamePage` z `hasNext: j['next'] != null`).

- [ ] **Step 4: PASS**, **Step 5: Commit** — `git commit -m "feat: API models mirroring backend contract"`

---

### Task 3: Klient API (dio)

**Files:**
- Create: `app/lib/core/api/api_client.dart`
- Test: `app/test/core/api_client_test.dart`

**Interfaces:**
- Produces:

```dart
class ApiClient {
  ApiClient({required String baseUrl, String? token, Dio? dio});
  Future<String> login(String username, String password);       // -> token
  Future<List<SystemModel>> fetchSystems();
  Future<GamePage> fetchGames({String? system, String? search, int page = 1});
  Future<GameDetail> fetchGame(int id);
  String coverUrl(int gameId, {String size = 'thumb'});
  Map<String, String> get authHeaders;                          // {'Authorization': 'Token ...'}
}
class UnauthorizedException implements Exception {}
```

Interceptor: dokleja `Authorization` gdy jest token; status 401 → rzuca `UnauthorizedException`.

- [ ] **Step 1: Failing testy**

`app/test/core/api_client_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:droplet/core/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://nas:8000'));
    adapter = DioAdapter(dio: dio);
  });

  test('login returns token', () async {
    adapter.onPost('/api/auth/token/', (s) => s.reply(200, {'token': 'abc'}),
        data: Matchers.any);
    final client = ApiClient(baseUrl: 'http://nas:8000', dio: dio);
    expect(await client.login('jan', 'x'), 'abc');
  });

  test('fetchGames sends token and parses page', () async {
    adapter.onGet('/api/games/', (s) => s.reply(200, {
          'count': 1,
          'next': null,
          'results': [
            {'id': 1, 'title': 'Mario', 'system_code': 'snes',
             'has_cover': true, 'total_size': 5}
          ],
        }),
        queryParameters: {'page': 1, 'system': 'snes'},
        headers: {'Authorization': 'Token abc'});
    final client = ApiClient(baseUrl: 'http://nas:8000', token: 'abc', dio: dio);
    final page = await client.fetchGames(system: 'snes');
    expect(page.results.single.title, 'Mario');
  });

  test('401 throws UnauthorizedException', () async {
    adapter.onGet('/api/systems/', (s) => s.reply(401, {'detail': 'no'}));
    final client = ApiClient(baseUrl: 'http://nas:8000', token: 'zly', dio: dio);
    expect(client.fetchSystems(), throwsA(isA<UnauthorizedException>()));
  });

  test('coverUrl builds absolute url', () {
    final client = ApiClient(baseUrl: 'http://nas:8000', token: 'abc');
    expect(client.coverUrl(7), 'http://nas:8000/api/games/7/cover?size=thumb');
  });
}
```

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Implementacja**

`app/lib/core/api/api_client.dart`:

```dart
import 'package:dio/dio.dart';

import 'models.dart';

class UnauthorizedException implements Exception {}

class ApiClient {
  ApiClient({required this.baseUrl, this.token, Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl)) {
    _dio.options.baseUrl = baseUrl;
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (token != null) options.headers['Authorization'] = 'Token $token';
        handler.next(options);
      },
    ));
  }

  final String baseUrl;
  final String? token;
  final Dio _dio;

  Map<String, String> get authHeaders =>
      token == null ? {} : {'Authorization': 'Token $token'};

  Never _mapError(DioException e) {
    if (e.response?.statusCode == 401) throw UnauthorizedException();
    throw e;
  }

  Future<String> login(String username, String password) async {
    final resp = await _dio.post('/api/auth/token/',
        data: {'username': username, 'password': password});
    return resp.data['token'] as String;
  }

  Future<List<SystemModel>> fetchSystems() async {
    try {
      final resp = await _dio.get('/api/systems/');
      return (resp.data as List)
          .map((j) => SystemModel.fromJson(j))
          .toList();
    } on DioException catch (e) {
      _mapError(e);
    }
  }

  Future<GamePage> fetchGames({String? system, String? search, int page = 1}) async {
    try {
      final resp = await _dio.get('/api/games/', queryParameters: {
        'page': page,
        if (system != null) 'system': system,
        if (search != null && search.isNotEmpty) 'search': search,
      });
      return GamePage.fromJson(resp.data);
    } on DioException catch (e) {
      _mapError(e);
    }
  }

  Future<GameDetail> fetchGame(int id) async {
    try {
      final resp = await _dio.get('/api/games/$id/');
      return GameDetail.fromJson(resp.data);
    } on DioException catch (e) {
      _mapError(e);
    }
  }

  String coverUrl(int gameId, {String size = 'thumb'}) =>
      '$baseUrl/api/games/$gameId/cover?size=$size';
}
```

- [ ] **Step 4: PASS**, **Step 5: Commit** — `git commit -m "feat: dio API client with token auth"`

---

### Task 4: Sesja (secure storage) + provider'y

**Files:**
- Create: `app/lib/core/session/session_repository.dart`, `app/lib/core/session/providers.dart`
- Test: `app/test/core/session_test.dart`

**Interfaces:**
- Produces:

```dart
abstract class KeyValueStore {           // abstrakcja nad secure storage
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}
class SecureKeyValueStore implements KeyValueStore { ... }  // flutter_secure_storage
class MemoryKeyValueStore implements KeyValueStore { ... }  // do testów

class Session { final String serverUrl; final String token; }
class SessionRepository {
  SessionRepository(KeyValueStore store);
  Future<Session?> load();               // null gdy brak kompletu danych
  Future<void> save(Session session);
  Future<void> clear();
}

// providers.dart (Riverpod):
typedef ApiClientFactory = ApiClient Function(String baseUrl, {String? token});
final apiClientFactoryProvider = Provider<ApiClientFactory>(...); // testy podmieniają na fake
final sessionRepositoryProvider = Provider<SessionRepository>(...);
final sessionProvider = AsyncNotifierProvider<SessionController, Session?>(...);
//   SessionController: Future<void> signIn(serverUrl, username, password)  // przez factory
//                      Future<void> signOut()
final apiClientProvider = Provider<ApiClient>(...); // factory + sessionProvider; throw gdy brak sesji
```

- [ ] **Step 1: Failing testy**

`app/test/core/session_test.dart`:

```dart
import 'package:droplet/core/session/session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('save/load roundtrip', () async {
    final repo = SessionRepository(MemoryKeyValueStore());
    await repo.save(const Session(serverUrl: 'http://nas:8000', token: 'abc'));
    final loaded = await repo.load();
    expect(loaded!.serverUrl, 'http://nas:8000');
    expect(loaded.token, 'abc');
  });

  test('load returns null when empty', () async {
    expect(await SessionRepository(MemoryKeyValueStore()).load(), isNull);
  });

  test('clear removes session', () async {
    final repo = SessionRepository(MemoryKeyValueStore());
    await repo.save(const Session(serverUrl: 'x', token: 'y'));
    await repo.clear();
    expect(await repo.load(), isNull);
  });

  test('SecureKeyValueStore roundtrip on mocked plugin', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureKeyValueStore();
    await store.write('k', 'v');
    expect(await store.read('k'), 'v');
    await store.delete('k');
    expect(await store.read('k'), isNull);
  });

  test('default repository provider builds on secure store', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(sessionRepositoryProvider), isA<SessionRepository>());
    expect(container.read(apiClientFactoryProvider)('http://x', token: 't').token, 't');
  });

  test('signIn/signOut drive session and apiClientProvider', () async {
    final repo = SessionRepository(MemoryKeyValueStore());
    final container = ProviderContainer(overrides: [
      sessionRepositoryProvider.overrideWithValue(repo),
      apiClientFactoryProvider.overrideWithValue(
        (baseUrl, {token}) => _FakeApiClient(baseUrl: baseUrl, token: token),
      ),
    ]);
    addTearDown(container.dispose);
    expect(await container.read(sessionProvider.future), isNull);
    expect(() => container.read(apiClientProvider), throwsStateError);

    await container
        .read(sessionProvider.notifier)
        .signIn('http://nas:8000', 'jan', 'x');
    expect(container.read(sessionProvider).value?.token, 'fake-token');
    expect((await repo.load())?.token, 'fake-token');
    expect(container.read(apiClientProvider).baseUrl, 'http://nas:8000');

    await container.read(sessionProvider.notifier).signOut();
    expect(container.read(sessionProvider).value, isNull);
    expect(await repo.load(), isNull);
  });
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient({required super.baseUrl, super.token});
  @override
  Future<String> login(String username, String password) async => 'fake-token';
}
```

(importy: `flutter_secure_storage`, `flutter_riverpod`, `droplet/core/api/api_client.dart`, `droplet/core/session/providers.dart`.)

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Implementacja** — `session_repository.dart` wg Interfaces (klucze: `server_url`, `token`; `MemoryKeyValueStore` na `Map`; `SecureKeyValueStore` na `const FlutterSecureStorage()`). `providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import 'session_repository.dart';

typedef ApiClientFactory = ApiClient Function(String baseUrl, {String? token});

/// Jedyne miejsce tworzenia ApiClient — testy podmieniają na fake bez sieci.
final apiClientFactoryProvider = Provider<ApiClientFactory>(
  (ref) => (baseUrl, {token}) => ApiClient(baseUrl: baseUrl, token: token),
);

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(SecureKeyValueStore()),
);

class SessionController extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() => ref.read(sessionRepositoryProvider).load();

  Future<void> signIn(String serverUrl, String username, String password) async {
    final client = ref.read(apiClientFactoryProvider)(serverUrl);
    final token = await client.login(username, password);
    final session = Session(serverUrl: serverUrl, token: token);
    await ref.read(sessionRepositoryProvider).save(session);
    state = AsyncData(session);
  }

  Future<void> signOut() async {
    await ref.read(sessionRepositoryProvider).clear();
    state = const AsyncData(null);
  }
}

final sessionProvider =
    AsyncNotifierProvider<SessionController, Session?>(SessionController.new);

final apiClientProvider = Provider<ApiClient>((ref) {
  final session = ref.watch(sessionProvider).valueOrNull;
  if (session == null) throw StateError('Brak sesji');
  return ref.watch(apiClientFactoryProvider)(
    session.serverUrl,
    token: session.token,
  );
});
```

- [ ] **Step 4: PASS**, **Step 5: Commit** — `git commit -m "feat: session storage and riverpod session state"`

---

### Task 5: Ekran logowania + guard routera

**Files:**
- Create: `app/lib/features/auth/login_screen.dart`
- Modify: `app/lib/app/router.dart` (redirect wg sesji, podmiana stuba), `app/lib/main.dart` (`DropletApp` jako `ConsumerWidget`), `app/test/smoke_test.dart`
- Test: `app/test/features/login_screen_test.dart`, `app/test/app/router_test.dart`

**Interfaces:**
- Produces: `LoginScreen` — pola: adres serwera (prefill `http://`), login, hasło; przycisk „Zaloguj" woła `sessionProvider.notifier.signIn`; błędy pod formularzem („Nie mogę połączyć z serwerem" / „Błędny login lub hasło" dla `UnauthorizedException`/`DioException` 400). Router jako `routerProvider` z `redirect` — brak sesji → `/login`, jest sesja a wchodzi na `/login` → `/` — i **`refreshListenable`** podpiętym pod `sessionProvider` (bez tego po `signIn` router nie przeliczy redirectu i użytkownik zostanie na ekranie logowania). `DropletApp` pokazuje pusty ciemny `Scaffold`, dopóki `sessionProvider` się ładuje (inaczej `/` zbuduje się bez klienta API).

```dart
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(sessionProvider).valueOrNull != null;
      final onLogin = state.matchedLocation == '/login';
      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/';
      return null;
    },
    routes: [/* jak w Task 1, /login → LoginScreen */],
  );
});
```

`app/test/app/router_test.dart` (dopisz w tym tasku):

```dart
Widget app(KeyValueStore store) => ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(SessionRepository(store)),
      ],
      child: const DropletApp(),
    );

testWidgets('no session -> login screen', (tester) async {
  await tester.pumpWidget(app(MemoryKeyValueStore()));
  await tester.pumpAndSettle();
  expect(find.byType(LoginScreen), findsOneWidget);
});

testWidgets('session -> library', (tester) async {
  final store = MemoryKeyValueStore();
  await SessionRepository(store)
      .save(const Session(serverUrl: 'http://nas:8000', token: 't'));
  await tester.pumpWidget(app(store));
  await tester.pumpAndSettle();
  expect(find.text('Biblioteka'), findsOneWidget); // stub; od Task 6: find.byType(LibraryScreen)
});
```

W `smoke_test.dart` z Task 1 dodaj to samo nadpisanie `sessionRepositoryProvider` (pamięciowy store), żeby test nie dotykał pluginu secure storage.

- [ ] **Step 1: Failing testy**

`app/test/features/login_screen_test.dart`:

```dart
import 'package:droplet/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders three fields and button', (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: LoginScreen())));
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.text('Zaloguj'), findsOneWidget);
  });

  testWidgets('empty submit shows validation', (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: LoginScreen())));
    await tester.tap(find.text('Zaloguj'));
    await tester.pump();
    expect(find.text('Wymagane'), findsWidgets);
  });
}
```

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Implementacja** — `LoginScreen` (ConsumerStatefulWidget): `Form` z trzema `TextFormField` (validator `Wymagane` przy pustym), stan ładowania na przycisku, mapowanie wyjątków na komunikaty; logo/tytuł „Droplet" nad formularzem, całość wycentrowana, max szerokość 420. W `router.dart` dodaj `redirect` czytający `sessionProvider` (router jako provider — `buildRouter(Ref ref)` w `routerProvider`), podmień stub `/login` na `LoginScreen`.

- [ ] **Step 4: PASS** — `flutter test`; ręcznie: logowanie do prawdziwego backendu z telefonu (zły adres → komunikat, dobre dane → przejście do `/`).

- [ ] **Step 5: Commit** — `git commit -m "feat: login screen with session-aware routing"`

---

### Task 6: Biblioteka — pasek systemów, grid okładek, szukajka

**Files:**
- Create: `app/lib/features/library/library_screen.dart`, `app/lib/features/library/providers.dart`, `app/lib/features/library/widgets/cover_image.dart`, `app/lib/features/library/widgets/game_card.dart`
- Modify: `app/lib/app/router.dart`
- Test: `app/test/features/library_screen_test.dart`

**Interfaces:**
- Produces:
  - `providers.dart`: `systemsProvider = FutureProvider<List<SystemModel>>`; `selectedSystemProvider = StateProvider<String?>`; `searchQueryProvider = StateProvider<String>`; `gamesProvider = FutureProvider<List<GameSummary>>` (pobiera KOLEJNE strony aż `hasNext == false` — biblioteka jednego użytkownika zmieści się w pamięci).
  - `CoverImage(gameId, headers, url)` — `CachedNetworkImage` z `httpHeaders`, placeholder: kontener `kSurface` z tytułem gry i subtelnym gradientem.
  - `GameCard(game)` — okładka 3:4, zaokrąglenie 12, tytuł pod spodem, `onTap` → `/game/:id`.
  - `LibraryScreen` — AppBar z szukajką (`SearchBar`), poziomy `ListView` chipów systemów („Wszystkie" + z `systemsProvider`), `GridView` kart (2 kolumny portret), pull-to-refresh (`ref.invalidate(gamesProvider)`), ikona ustawień → `/settings`.

- [ ] **Step 1: Failing testy**

`app/test/features/library_screen_test.dart`:

```dart
import 'package:droplet/core/api/models.dart';
import 'package:droplet/features/library/library_screen.dart';
import 'package:droplet/features/library/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final games = [
    const GameSummary(id: 1, title: 'Super Mario World', systemCode: 'snes',
        hasCover: false, totalSize: 5),
    const GameSummary(id: 2, title: 'Tekken', systemCode: 'psx',
        hasCover: false, totalSize: 9),
  ];
  final systems = [
    const SystemModel(id: 1, code: 'snes', name: 'SNES', gameCount: 1),
    const SystemModel(id: 2, code: 'psx', name: 'PSX', gameCount: 1),
  ];

  Widget build() => ProviderScope(
        overrides: [
          gamesProvider.overrideWith((ref) async => games),
          systemsProvider.overrideWith((ref) async => systems),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      );

  testWidgets('shows games and system chips', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(find.text('Super Mario World'), findsOneWidget);
    expect(find.text('SNES'), findsOneWidget);
    expect(find.text('Wszystkie'), findsOneWidget);
  });
}
```

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Implementacja** — wg Interfaces. `gamesProvider`:

```dart
final gamesProvider = FutureProvider<List<GameSummary>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final system = ref.watch(selectedSystemProvider);
  final search = ref.watch(searchQueryProvider);
  final all = <GameSummary>[];
  var page = 1;
  while (true) {
    final result =
        await client.fetchGames(system: system, search: search, page: page);
    all.addAll(result.results);
    if (!result.hasNext) return all;
    page += 1;
  }
});
```

Placeholder okładki bez sieci w testach: `CoverImage` renderuje `CachedNetworkImage` tylko gdy `hasCover`, inaczej od razu placeholder — dzięki temu widget testy nie strzelają po HTTP.

- [ ] **Step 4: PASS** — `flutter test`; ręcznie na telefonie: przewijanie pełnej biblioteki, filtr systemem, szukajka.

- [ ] **Step 5: Commit** — `git commit -m "feat: library grid with system filter and search"`

---

### Task 7: Karta gry

**Files:**
- Create: `app/lib/features/game/game_detail_screen.dart`, `app/lib/features/game/providers.dart`
- Modify: `app/lib/app/router.dart`
- Test: `app/test/features/game_detail_test.dart`

**Interfaces:**
- Produces: `gameDetailProvider = FutureProvider.family<GameDetail, int>`; `GameDetailScreen(gameId)` — `CustomScrollView`: `SliverAppBar` z okładką `full` jako tło (gradient do `kBg`), tytuł + system, sekcja plików pogrupowana etykietami ról (`Gra`, `Aktualizacja`, `DLC`, `Płyta N`, `Pozostałe`), rozmiary w czytelnym formacie (`formatBytes(int) -> String` w `lib/core/format.dart`: `1.4 GB`), przycisk „Pobierz" — na razie `disabled` z tooltipem „Wkrótce" (aktywacja w M5).

- [ ] **Step 1: Failing testy**

`app/test/features/game_detail_test.dart`:

```dart
import 'package:droplet/core/api/models.dart';
import 'package:droplet/core/format.dart';
import 'package:droplet/features/game/game_detail_screen.dart';
import 'package:droplet/features/game/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatBytes', () {
    expect(formatBytes(500), '500 B');
    expect(formatBytes(2048), '2.0 KB');
    expect(formatBytes(1500000000), '1.4 GB');
  });

  testWidgets('shows role sections', (tester) async {
    const detail = GameDetail(
      id: 7, title: 'Hollow Knight', systemCode: 'switch', systemName: 'Switch',
      hasCover: false, totalSize: 3,
      files: [
        GameFileModel(id: 1, name: 'hk.nsp', relativePath: 'switch/hk.nsp',
            role: FileRole.base, discNumber: null, version: '', size: 1),
        GameFileModel(id: 2, name: 'upd.nsp', relativePath: 'switch/upd.nsp',
            role: FileRole.update, discNumber: null, version: 'v196608', size: 2),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        gameDetailProvider(7).overrideWith((ref) async => detail),
      ],
      child: const MaterialApp(home: GameDetailScreen(gameId: 7)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Hollow Knight'), findsWidgets);
    expect(find.text('Aktualizacja'), findsOneWidget);
    expect(find.textContaining('v196608'), findsOneWidget);
  });
}
```

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Implementacja** — `format.dart`:

```dart
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return unit == 0 ? '$bytes B' : '${value.toStringAsFixed(1)} ${units[unit]}';
}
```

`GameDetailScreen` wg Interfaces; etykiety ról:

```dart
const roleLabels = {
  FileRole.base: 'Gra',
  FileRole.update: 'Aktualizacja',
  FileRole.dlc: 'DLC',
  FileRole.disc: 'Płyta',
  FileRole.support: 'Pozostałe',
  FileRole.other: 'Pozostałe',
};
```

Router: `/game/:id` → `GameDetailScreen(gameId: int.parse(...))`.

- [ ] **Step 4: PASS**, **Step 5: Commit** — `git commit -m "feat: game detail screen with file manifest"`

---

### Task 8: Ustawienia + wylogowanie + odbiór M4

**Files:**
- Create: `app/lib/features/settings/settings_screen.dart`
- Modify: `app/lib/app/router.dart`
- Test: `app/test/features/settings_test.dart`

**Interfaces:**
- Produces: `SettingsScreen` — sekcje: Serwer (adres, tylko odczyt + „Wyloguj" czyszczący sesję i wracający do `/login`), O aplikacji (wersja). Miejsce na ustawienia pobierania dojdzie w M5.

- [ ] **Step 1: Failing test**

`app/test/features/settings_test.dart`:

```dart
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:droplet/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows server url and logout', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionProvider.overrideWith(() => _FakeSession()),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('http://nas:8000'), findsOneWidget);
    expect(find.text('Wyloguj'), findsOneWidget);
  });
}

class _FakeSession extends SessionController {
  @override
  Future<Session?> build() async =>
      const Session(serverUrl: 'http://nas:8000', token: 't');
}
```

- [ ] **Step 2: FAIL**, **Step 3: Implementacja** wg Interfaces, **Step 4: PASS**.

- [ ] **Step 5: Odbiór kryteriów M4 na urządzeniu**

Checklista (fizyczny telefon + backend na NAS):
- logowanie po lokalnym IP działa; restart aplikacji nie wymaga ponownego logowania;
- pełna biblioteka przewija się płynnie z okładkami; filtr i szukajka działają;
- karta gry pokazuje komplet plików z rolami i rozmiarami;
- wylogowanie wraca do logowania.
Pokaż build użytkownikowi — **akceptacja wyglądu jest bramką zamknięcia M4**.

- [ ] **Step 6: Commit** — `git commit -m "feat: settings screen and M4 wrap-up"`

---

### Task 9: E2E integration_test (login → biblioteka → karta gry)

**Files:**
- Create: `app/integration_test/app_flow_test.dart`, `scripts/e2e_app.sh`

**Interfaces:**
- Consumes: backend e2e z compose (M0/M1: port 8800, user `e2e`/`e2e-pass-123`, fixture-library).
- Produces: suita e2e aplikacji na realnym urządzeniu; `scripts/e2e_app.sh` — stawia backend e2e, uruchamia testy z adresem przez `--dart-define=E2E_SERVER`, sprząta.

- [ ] **Step 1: Napisz test e2e**

`app/integration_test/app_flow_test.dart`:

```dart
import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const server = String.fromEnvironment('E2E_SERVER'); // np. http://192.168.1.10:8800

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // seed: skan fixture-library przez API, żeby biblioteka nie była pusta
    final client = ApiClient(baseUrl: server);
    final token = await client.login('e2e', 'e2e-pass-123');
    final authed = ApiClient(baseUrl: server, token: token);
    await authed.triggerScan(); // dodaj metodę POST /api/scan/ do ApiClient w tym tasku
    await Future<void>.delayed(const Duration(seconds: 5));
  });

  testWidgets('login, browse library, open game detail', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DropletApp()));
    await tester.pumpAndSettle();

    // logowanie
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), server);
    await tester.enterText(fields.at(1), 'e2e');
    await tester.enterText(fields.at(2), 'e2e-pass-123');
    await tester.tap(find.text('Zaloguj'));
    await tester.pumpAndSettle(const Duration(seconds: 10));

    // biblioteka z fixture-library
    expect(find.text('Super Mario World'), findsOneWidget);

    // filtr systemem
    await tester.tap(find.text('Nintendo Switch'));
    await tester.pumpAndSettle();
    expect(find.text('Hollow Knight'), findsOneWidget);
    expect(find.text('Super Mario World'), findsNothing);

    // karta gry z rolami
    await tester.tap(find.text('Hollow Knight'));
    await tester.pumpAndSettle();
    expect(find.text('Aktualizacja'), findsOneWidget);

    // powrót i wylogowanie
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wyloguj'));
    await tester.pumpAndSettle();
    expect(find.text('Zaloguj'), findsOneWidget);
  });
}
```

Dopisz do `ApiClient` metodę (z testem unit — mock 202, bramka pokrycia!):

```dart
Future<void> triggerScan() async {
  try {
    await _dio.post('/api/scan/');
  } on DioException catch (e) {
    _mapError(e);
  }
}
```

- [ ] **Step 2: Napisz `scripts/e2e_app.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
E2E_SERVER=${E2E_SERVER:?ustaw np. E2E_SERVER=http://192.168.1.10:8800 (IP hosta widoczne z telefonu)}
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.e2e.yml"
cleanup() { $COMPOSE down -v; }
trap cleanup EXIT
$COMPOSE up -d --build
for i in $(seq 1 60); do curl -sf localhost:8800/api/health/ >/dev/null && break; sleep 1; done
cd app && flutter test integration_test --dart-define=E2E_SERVER="$E2E_SERVER"
```

`chmod +x scripts/e2e_app.sh`.

- [ ] **Step 3: Uruchom na podłączonym urządzeniu**

Run: `E2E_SERVER=http://<ip-hosta>:8800 ./scripts/e2e_app.sh`
Expected: test PASS (telefon i host w tej samej sieci).

- [ ] **Step 4: Bramki końcowe M4** — `./scripts/check_coverage_app.sh` (100%), `flutter test` zielone, e2e app PASS, e2e backendu PASS.

- [ ] **Step 5: Commit** — `git add app scripts && git commit -m "test: app e2e flow with integration_test"`
