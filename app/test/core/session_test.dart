import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
    expect(
      container.read(apiClientFactoryProvider)('http://x', token: 't').token,
      't',
    );
  });

  test('signIn/signOut drive session and apiClientProvider', () async {
    final repo = SessionRepository(MemoryKeyValueStore());
    final container = ProviderContainer(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        apiClientFactoryProvider.overrideWithValue(
          (baseUrl, {token}) => _FakeApiClient(baseUrl: baseUrl, token: token),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(await container.read(sessionProvider.future), isNull);
    // Riverpod 3 wraps a provider's exception, so match on the message.
    expect(
      () => container.read(apiClientProvider),
      throwsA(predicate((e) => e.toString().contains('Brak sesji'))),
    );

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
