import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import 'local_storage_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(ref.read(localStorageServiceProvider));
});

class ApiService {
  late final Dio _dio;
  final LocalStorageService _storage;

  ApiService(this._storage) {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.getAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (DioException error, handler) async {
          if (error.response?.statusCode == 401) {
            final refreshed = await _tryRefreshToken();
            if (refreshed) {
              final token = await _storage.getAccessToken();
              error.requestOptions.headers['Authorization'] = 'Bearer $token';
              final response = await _dio.fetch(error.requestOptions);
              return handler.resolve(response);
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  Future<bool> _tryRefreshToken() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null) return false;
    try {
      final response = await _dio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(headers: {}),
      );
      final data = response.data as Map<String, dynamic>;
      await _storage.saveTokens(data['access_token'], data['refresh_token']);
      return true;
    } catch (_) {
      await _storage.clearAll();
      return false;
    }
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? params}) async {
    final response = await _dio.get(path, queryParameters: params);
    return response.data as Map<String, dynamic>;
  }

  Future<dynamic> getList(String path, {Map<String, dynamic>? params}) async {
    final response = await _dio.get(path, queryParameters: params);
    return response.data;
  }

  Future<Map<String, dynamic>> post(String path, {dynamic data}) async {
    final response = await _dio.post(path, data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> put(String path, {dynamic data}) async {
    final response = await _dio.put(path, data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> patch(String path, {dynamic data}) async {
    final response = await _dio.patch(path, data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<void> delete(String path, {dynamic data}) async {
    await _dio.delete(path, data: data);
  }

  Future<Map<String, dynamic>> postMultipart(
    String path,
    FormData formData,
  ) async {
    final response = await _dio.post(
      path,
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> postNoAuth(String path, {dynamic data}) async {
    final response = await _dio.post(
      path,
      data: data,
      options: Options(headers: {'Authorization': null}),
    );
    return response.data as Map<String, dynamic>;
  }
}
