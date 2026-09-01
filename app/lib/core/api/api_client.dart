import 'package:dio/dio.dart';

import 'models.dart';

class UnauthorizedException implements Exception {}

class ApiClient {
  ApiClient({required this.baseUrl, this.token, Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl)) {
    _dio.options.baseUrl = baseUrl;
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (token != null) options.headers['Authorization'] = 'Token $token';
          handler.next(options);
        },
      ),
    );
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
    final resp = await _dio.post(
      '/api/auth/token/',
      data: {'username': username, 'password': password},
    );
    return resp.data['token'] as String;
  }

  Future<List<SystemModel>> fetchSystems() async {
    try {
      final resp = await _dio.get('/api/systems/');
      return (resp.data as List)
          .map((j) => SystemModel.fromJson(j as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      _mapError(e);
    }
  }

  Future<GamePage> fetchGames({
    String? system,
    String? search,
    int page = 1,
  }) async {
    try {
      final resp = await _dio.get(
        '/api/games/',
        queryParameters: {
          'page': page,
          if (system != null) 'system': system,
          if (search != null && search.isNotEmpty) 'search': search,
        },
      );
      return GamePage.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _mapError(e);
    }
  }

  Future<GameDetail> fetchGame(int id) async {
    try {
      final resp = await _dio.get('/api/games/$id/');
      return GameDetail.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _mapError(e);
    }
  }

  String coverUrl(int gameId, {String size = 'thumb'}) =>
      '$baseUrl/api/games/$gameId/cover?size=$size';
}
