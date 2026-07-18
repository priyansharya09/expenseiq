import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  // ─── Base URL Configuration ──────────────────────────────────────
  // Change this IP to your laptop's hotspot/WiFi IP address.
  // Find it by running `ipconfig` (Windows) or `ifconfig` (Mac/Linux).
  static const String _physicalDeviceIp = '192.168.138.211';

  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8000/api';
    }
    if (Platform.isAndroid) {
      // 10.0.2.2 is the Android emulator alias for host localhost.
      // For physical devices, use the laptop's actual IP.
      return 'http://$_physicalDeviceIp:8000/api';
    } else if (Platform.isIOS) {
      return 'http://localhost:8000/api';
    }
    return 'http://$_physicalDeviceIp:8000/api';
  }

  // ─── Dio Instance ────────────────────────────────────────────────
  late final Dio dio = _createDio();

  Dio _createDio() {
    final d = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));

    // JWT Interceptor: auto-attach access token & auto-refresh on 401
    d.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final refreshed = await _refreshToken();
          if (refreshed) {
            // Retry the original request with the new token
            final token = await _storage.read(key: 'access_token');
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            final response = await d.fetch(error.requestOptions);
            return handler.resolve(response);
          }
        }
        handler.next(error);
      },
    ));

    return d;
  }

  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null) return false;

      final response = await Dio(BaseOptions(baseUrl: baseUrl)).post(
        '/auth/refresh/',
        data: {'refresh': refreshToken},
      );

      if (response.statusCode == 200) {
        await _storage.write(key: 'access_token', value: response.data['access']);
        if (response.data['refresh'] != null) {
          await _storage.write(key: 'refresh_token', value: response.data['refresh']);
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ─── Auth Methods ────────────────────────────────────────────────
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await dio.post('/auth/login/', data: {
      'username': username,
      'password': password,
    });
    await _saveTokens(response.data);
    return response.data;
  }

  Future<Map<String, dynamic>> register(String username, String email, String password) async {
    final response = await dio.post('/auth/register/', data: {
      'username': username,
      'email': email,
      'password': password,
    });
    await _saveTokens(response.data);
    return response.data;
  }

  Future<void> logout() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      await dio.post('/auth/logout/', data: {'refresh': refreshToken});
    } catch (_) {}
    await _storage.deleteAll();
  }

  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: 'access_token');
    return token != null;
  }

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    if (data['access'] != null) {
      await _storage.write(key: 'access_token', value: data['access']);
    }
    if (data['refresh'] != null) {
      await _storage.write(key: 'refresh_token', value: data['refresh']);
    }
  }

  // ─── Transaction Methods ─────────────────────────────────────────
  Future<Map<String, dynamic>> getTransactions({
    int? month, int? year, String? type, String? category, String? search, int page = 1,
  }) async {
    final params = <String, dynamic>{'page': page};
    if (month != null) params['month'] = month;
    if (year != null) params['year'] = year;
    if (type != null) params['type'] = type;
    if (category != null) params['category'] = category;
    if (search != null) params['search'] = search;

    final response = await dio.get('/transactions/', queryParameters: params);
    return response.data;
  }

  Future<Map<String, dynamic>> createTransaction(Map<String, dynamic> data) async {
    final response = await dio.post('/transactions/', data: data);
    return response.data;
  }

  Future<Map<String, dynamic>> updateTransaction(int id, Map<String, dynamic> data) async {
    final response = await dio.patch('/transactions/$id/', data: data);
    return response.data;
  }

  Future<void> deleteTransaction(int id) async {
    await dio.delete('/transactions/$id/');
  }

  Future<Map<String, dynamic>> getSummary({int? month, int? year}) async {
    final params = <String, dynamic>{};
    if (month != null) params['month'] = month;
    if (year != null) params['year'] = year;
    final response = await dio.get('/transactions/summary/', queryParameters: params);
    return response.data;
  }

  Future<List<dynamic>> getMonthlyTrend() async {
    final response = await dio.get('/transactions/monthly_trend/');
    return response.data;
  }

  Future<List<dynamic>> getCategories() async {
    final response = await dio.get('/categories/');
    // DRF pagination wraps results in {count, next, previous, results}
    if (response.data is Map && response.data.containsKey('results')) {
      return response.data['results'];
    }
    return response.data;
  }

  Future<Map<String, dynamic>> bulkUpload(String filePath) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final response = await dio.post('/transactions/bulk-upload/', data: formData);
    return response.data;
  }

  // ── Contacts ──
  Future<Response> getContacts() async {
    return await dio.get('/contacts/');
  }

  Future<Response> createContact(Map<String, dynamic> data) async {
    return await dio.post('/contacts/', data: data);
  }

  Future<Response> updateContact(int id, Map<String, dynamic> data) async {
    return await dio.patch('/contacts/$id/', data: data);
  }

  Future<Response> deleteContact(int id) async {
    return await dio.delete('/contacts/$id/');
  }

  Future<Response> getContactBalance(int contactId) async {
    return await dio.get('/contacts/$contactId/balance/');
  }

  // ── Debts ──
  Future<Response> getDebts({int? contactId, bool? settled}) async {
    final params = <String, dynamic>{};
    if (contactId != null) params['contact'] = contactId;
    if (settled != null) params['settled'] = settled.toString();
    return await dio.get('/debts/', queryParameters: params);
  }

  Future<Response> createDebt(Map<String, dynamic> data) async {
    return await dio.post('/debts/', data: data);
  }

  Future<Response> updateDebt(int id, Map<String, dynamic> data) async {
    return await dio.patch('/debts/$id/', data: data);
  }

  Future<Response> deleteDebt(int id) async {
    return await dio.delete('/debts/$id/');
  }

  Future<Response> settleDebt(int id) async {
    return await dio.post('/debts/$id/settle/');
  }

  Future<Response> settleAllDebts(int contactId) async {
    return await dio.post('/debts/settle_all/', data: {'contact_id': contactId});
  }

  Future<Response> getDebtSummary() async {
    return await dio.get('/debts/summary/');
  }
}

