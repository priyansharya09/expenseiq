// lib/services/api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static const String baseUrl = 'http://10.0.2.2:8000/api'; // Android emulator
  // Use 'http://localhost:8000/api' for iOS simulator or Flutter web

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio dio;
  final _storage = const FlutterSecureStorage();

  ApiService._internal() {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final refreshed = await _refreshToken();
          if (refreshed) {
            final token = await _storage.read(key: 'access_token');
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            final response = await dio.fetch(error.requestOptions);
            return handler.resolve(response);
          }
        }
        return handler.next(error);
      },
    ));
  }

  Future<bool> _refreshToken() async {
    try {
      final refresh = await _storage.read(key: 'refresh_token');
      if (refresh == null) return false;
      final res = await Dio().post('$baseUrl/auth/refresh/', data: {'refresh': refresh});
      await _storage.write(key: 'access_token', value: res.data['access']);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── Auth ───────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> register(String username, String email, String password) async {
    final res = await dio.post('/auth/register/',
        data: {'username': username, 'email': email, 'password': password});
    await _saveTokens(res.data);
    return res.data;
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await dio.post('/auth/login/',
        data: {'username': username, 'password': password});
    await _saveTokens(res.data);
    return res.data;
  }

  Future<void> logout() async {
    final refresh = await _storage.read(key: 'refresh_token');
    try {
      await dio.post('/auth/logout/', data: {'refresh': refresh});
    } catch (_) {}
    await _storage.deleteAll();
  }

  Future<void> _saveTokens(Map data) async {
    await _storage.write(key: 'access_token', value: data['access']);
    await _storage.write(key: 'refresh_token', value: data['refresh']);
  }

  Future<bool> isLoggedIn() async {
    return await _storage.read(key: 'access_token') != null;
  }

  // ─── Transactions ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getTransactions({
    int? month, int? year, String? type, String? category, String? search, int page = 1,
  }) async {
    final params = <String, dynamic>{'page': page};
    if (month != null) params['month'] = month;
    if (year != null) params['year'] = year;
    if (type != null) params['type'] = type;
    if (category != null) params['category'] = category;
    if (search != null && search.isNotEmpty) params['search'] = search;
    final res = await dio.get('/transactions/', queryParameters: params);
    return res.data;
  }

  Future<Map<String, dynamic>> getSummary({required int month, required int year}) async {
    final res = await dio.get('/transactions/summary/', queryParameters: {'month': month, 'year': year});
    return res.data;
  }

  Future<List> getMonthlyTrend() async {
    final res = await dio.get('/transactions/monthly_trend/');
    return res.data as List;
  }

  Future<Map<String, dynamic>> createTransaction(Map<String, dynamic> data) async {
    final res = await dio.post('/transactions/', data: data);
    return res.data;
  }

  Future<Map<String, dynamic>> updateTransaction(int id, Map<String, dynamic> data) async {
    final res = await dio.patch('/transactions/$id/', data: data);
    return res.data;
  }

  Future<void> deleteTransaction(int id) async {
    await dio.delete('/transactions/$id/');
  }

  Future<Map<String, dynamic>> bulkUpload(String filePath) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final res = await dio.post('/transactions/bulk-upload/', data: formData);
    return res.data;
  }

  // ─── Categories ──────────────────────────────────────────────────────────────

  Future<List> getCategories() async {
    final res = await dio.get('/categories/');
    return res.data['results'] as List;
  }
}
