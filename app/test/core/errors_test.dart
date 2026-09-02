import 'package:dio/dio.dart';
import 'package:droplet/core/api/api_client.dart';
import 'package:droplet/core/downloads/space.dart';
import 'package:droplet/core/errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unauthorized message', () {
    expect(
      humanizeError(UnauthorizedException()),
      'Sesja wygasła — zaloguj się ponownie',
    );
  });

  test('connection error message', () {
    final err = DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.connectionError,
    );
    expect(humanizeError(err), contains('Nie mogę połączyć'));
  });

  test('a server error is not mistaken for a connection problem', () {
    final err = DioException(
      requestOptions: RequestOptions(path: '/'),
      response: Response(requestOptions: RequestOptions(path: '/'), statusCode: 500),
    );
    expect(humanizeError(err), 'Coś poszło nie tak');
  });

  test('insufficient space keeps its own message', () {
    const err = InsufficientSpaceException(1024, 10);
    expect(humanizeError(err), err.toString());
  });

  test('fallback message', () {
    expect(humanizeError(StateError('x')), 'Coś poszło nie tak');
  });

  test('newGameCount ignores the very first run', () {
    const game = GameIdOnly(1);
    expect(newGameCount(const {}, [game.id]), 0);
    expect(newGameCount(const {1}, [1, 2, 3]), 2);
    expect(newGameCount(const {1, 2}, [1, 2]), 0);
  });
}

/// Tiny holder so the test reads like the real data without pulling models in.
class GameIdOnly {
  const GameIdOnly(this.id);
  final int id;
}
