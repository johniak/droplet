import 'package:dio/dio.dart';

import 'api/api_client.dart';
import 'downloads/space.dart';

/// One place that turns exceptions into something a person can act on.
String humanizeError(Object error) {
  if (error is UnauthorizedException) {
    return 'Sesja wygasła — zaloguj się ponownie';
  }
  if (error is InsufficientSpaceException) return error.toString();
  if (error is DioException &&
      const {
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
      }.contains(error.type)) {
    return 'Nie mogę połączyć z serwerem — sprawdź adres i sieć';
  }
  return 'Coś poszło nie tak';
}

/// How many ids are new compared to the previous refresh. An empty [previous]
/// means the first run — then nothing is "new".
int newGameCount(Set<int> previous, List<int> current) {
  if (previous.isEmpty) return 0;
  return current.where((id) => !previous.contains(id)).length;
}
