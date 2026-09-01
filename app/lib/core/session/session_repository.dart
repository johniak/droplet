import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kServerUrl = 'server_url';
const _kToken = 'token';

/// Abstraction over the platform keychain so the logic stays testable.
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureKeyValueStore implements KeyValueStore {
  const SecureKeyValueStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

class Session {
  const Session({required this.serverUrl, required this.token});

  final String serverUrl;
  final String token;
}

class SessionRepository {
  SessionRepository(this._store);

  final KeyValueStore _store;

  Future<Session?> load() async {
    final serverUrl = await _store.read(_kServerUrl);
    final token = await _store.read(_kToken);
    if (serverUrl == null || token == null) return null;
    return Session(serverUrl: serverUrl, token: token);
  }

  Future<void> save(Session session) async {
    await _store.write(_kServerUrl, session.serverUrl);
    await _store.write(_kToken, session.token);
  }

  Future<void> clear() async {
    await _store.delete(_kServerUrl);
    await _store.delete(_kToken);
  }
}
