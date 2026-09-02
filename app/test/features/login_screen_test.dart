import 'package:dio/dio.dart';
import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:droplet/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `Override` is not exported by flutter_riverpod 3, so the helper takes the
/// factory itself instead of a list of overrides.
Widget _wrap({ApiClientFactory? clientFactory}) => ProviderScope(
      overrides: [
        sessionRepositoryProvider
            .overrideWithValue(SessionRepository(MemoryKeyValueStore())),
        if (clientFactory != null)
          apiClientFactoryProvider.overrideWithValue(clientFactory),
      ],
      child: const MaterialApp(home: LoginScreen()),
    );

Future<void> _fillIn(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'http://nas:8000');
  await tester.enterText(fields.at(1), 'jan');
  await tester.enterText(fields.at(2), 'sekret');
}

void main() {
  testWidgets('renders three fields and button', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.text('Zaloguj'), findsOneWidget);
  });

  testWidgets('empty submit shows validation', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zaloguj'));
    await tester.pump();
    expect(find.text('Wymagane'), findsWidgets);
  });

  testWidgets('bad credentials show a login error', (tester) async {
    await tester.pumpWidget(
      _wrap(clientFactory: (baseUrl, {token}) =>
                _ThrowingClient(baseUrl: baseUrl, error: UnauthorizedException())),
    );
    await tester.pumpAndSettle();
    await _fillIn(tester);
    await tester.tap(find.text('Zaloguj'));
    await tester.pumpAndSettle();
    expect(find.text('Błędny login lub hasło'), findsOneWidget);
  });

  testWidgets('a 400 response is also a credentials error', (tester) async {
    await tester.pumpWidget(
      _wrap(clientFactory: (baseUrl, {token}) => _ThrowingClient(
              baseUrl: baseUrl,
              error: DioException(
                requestOptions: RequestOptions(path: '/api/auth/token/'),
                response: Response(
                  requestOptions: RequestOptions(path: '/api/auth/token/'),
                  statusCode: 400,
                ),
              ),
            )),
    );
    await tester.pumpAndSettle();
    await _fillIn(tester);
    await tester.tap(find.text('Zaloguj'));
    await tester.pumpAndSettle();
    expect(find.text('Błędny login lub hasło'), findsOneWidget);
  });

  testWidgets('an unreachable server shows a connection error', (tester) async {
    await tester.pumpWidget(
      _wrap(clientFactory: (baseUrl, {token}) => _ThrowingClient(
              baseUrl: baseUrl,
              error: DioException(
                requestOptions: RequestOptions(path: '/api/auth/token/'),
                type: DioExceptionType.connectionError,
              ),
            )),
    );
    await tester.pumpAndSettle();
    await _fillIn(tester);
    await tester.tap(find.text('Zaloguj'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nie mogę połączyć'), findsOneWidget);
  });
}

class _ThrowingClient extends ApiClient {
  _ThrowingClient({required super.baseUrl, required this.error});

  final Object error;

  @override
  Future<String> login(String username, String password) async => throw error;
}
