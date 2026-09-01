import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import 'session_repository.dart';

typedef ApiClientFactory = ApiClient Function(String baseUrl, {String? token});

/// The single place an ApiClient is built — tests swap in a fake, no network.
final apiClientFactoryProvider = Provider<ApiClientFactory>(
  (ref) => (baseUrl, {token}) => ApiClient(baseUrl: baseUrl, token: token),
);

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(const SecureKeyValueStore()),
);

class SessionController extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() => ref.read(sessionRepositoryProvider).load();

  Future<void> signIn(
    String serverUrl,
    String username,
    String password,
  ) async {
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
  final session = ref.watch(sessionProvider).value;
  if (session == null) throw StateError('Brak sesji');
  return ref.watch(apiClientFactoryProvider)(
    session.serverUrl,
    token: session.token,
  );
});
