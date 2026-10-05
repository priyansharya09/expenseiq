import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  // ─── Base URL Configuration ──────────────────────────────────────
  // Production default: AWS backend over HTTPS.
  // Local dev override: pass --dart-define=API_HOST=192.168.x.x to hit a
  // local Django server over http://HOST:8000.
  static const String _envApiHost = String.fromEnvironment('API_HOST');
  static const String _envApiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://expenseiq.duckdns.org/api',
  );

  static String get baseUrl {
    // 1. Local dev override: --dart-define=API_HOST=<lan-ip>
    if (_envApiHost.isNotEmpty) {
      return 'http://$_envApiHost:8000/api';
    }

    // 2. Default: cloud backend (HTTPS). Overridable with --dart-define=API_URL=...
    return _envApiUrl;
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

  Future<Map<String, dynamic>> register(
    String username,
    String email,
    String password, {
    String phone = '',
  }) async {
    final response = await dio.post('/auth/register/', data: {
      'username': username,
      'email': email,
      'password': password,
      if (phone.trim().isNotEmpty) 'phone': phone.trim(),
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

  Future<Map<String, dynamic>> getSummary({
    int? month,
    int? year,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final params = <String, dynamic>{};
    if (startDate != null && endDate != null) {
      params['start_date'] = _fmtDate(startDate);
      params['end_date'] = _fmtDate(endDate);
    } else {
      if (month != null) params['month'] = month;
      if (year != null) params['year'] = year;
    }
    final response = await dio.get('/transactions/summary/', queryParameters: params);
    return response.data;
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Learned category + payment mode for a transaction name the user typed before.
  /// Returns an empty map when nothing has been learned yet.
  Future<Map<String, dynamic>> suggestForName(String name, {String? type}) async {
    if (name.trim().isEmpty) return {};
    try {
      final response = await dio.get('/transactions/suggest/', queryParameters: {
        'name': name.trim(),
        if (type != null) 'type': type,
      });
      return Map<String, dynamic>.from(response.data ?? {});
    } catch (_) {
      return {};
    }
  }

  /// Distinct past transaction names starting with [query], for autocomplete.
  Future<List<String>> getNameSuggestions(String query) async {
    try {
      final response = await dio.get(
        '/transactions/name-suggestions/',
        queryParameters: {'q': query},
      );
      return List<String>.from(response.data ?? []);
    } catch (_) {
      return [];
    }
  }

  Future<List<dynamic>> getMonthlyTrend() async {
    final response = await dio.get('/transactions/monthly_trend/');
    return response.data;
  }

  /// Categories, optionally narrowed to the ones valid for [kind]
  /// ('income' or 'expense'). Categories marked 'both' always come back.
  Future<List<dynamic>> getCategories({String? kind}) async {
    final response = await dio.get(
      '/categories/',
      queryParameters: {if (kind != null) 'kind': kind},
    );
    // DRF pagination wraps results in {count, next, previous, results}
    if (response.data is Map && response.data.containsKey('results')) {
      return response.data['results'];
    }
    return response.data;
  }

  Future<Map<String, dynamic>> createCategory(Map<String, dynamic> data) async {
    final response = await dio.post('/categories/', data: data);
    return response.data;
  }

  Future<Map<String, dynamic>> updateCategory(int id, Map<String, dynamic> data) async {
    final response = await dio.patch('/categories/$id/', data: data);
    return response.data;
  }

  Future<void> deleteCategory(int id) async {
    await dio.delete('/categories/$id/');
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

  // ── Split Groups ──
  /// All groups owned by the current user (each includes members, balances, totals).
  Future<List<dynamic>> getGroups() async {
    final response = await dio.get('/groups/');
    if (response.data is Map && response.data.containsKey('results')) {
      return response.data['results'];
    }
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getGroup(int id) async {
    final response = await dio.get('/groups/$id/');
    return Map<String, dynamic>.from(response.data);
  }

  /// Create a group. [members] = [{'name':..,'phone':..}, ...] (owner auto-added).
  Future<Map<String, dynamic>> createGroup(String name, List<Map<String, String>> members) async {
    final response = await dio.post('/groups/', data: {'name': name, 'members': members});
    return Map<String, dynamic>.from(response.data);
  }

  Future<void> deleteGroup(int id) async {
    await dio.delete('/groups/$id/');
  }

  Future<Map<String, dynamic>> addGroupMember(int groupId, String name, String phone) async {
    final response = await dio.post('/groups/$groupId/members/', data: {'name': name, 'phone': phone});
    return Map<String, dynamic>.from(response.data);
  }

  Future<void> removeGroupMember(int groupId, int memberId) async {
    await dio.delete('/groups/$groupId/members/$memberId/');
  }

  /// Expenses for one group.
  Future<List<dynamic>> getGroupExpenses(int groupId) async {
    final response = await dio.get('/group-expenses/', queryParameters: {'group': groupId});
    if (response.data is Map && response.data.containsKey('results')) {
      return response.data['results'];
    }
    return response.data as List<dynamic>;
  }

  /// Log a group expense. [shares] = [{'member':id,'amount':'12.50'}, ...].
  Future<Map<String, dynamic>> createGroupExpense(Map<String, dynamic> data) async {
    final response = await dio.post('/group-expenses/', data: data);
    return Map<String, dynamic>.from(response.data);
  }

  Future<void> deleteGroupExpense(int id) async {
    await dio.delete('/group-expenses/$id/');
  }

  // ── Budgets ──
  /// Budgets for a period, each carrying spent/remaining/pct computed server-side.
  Future<List<dynamic>> getBudgetStatus({int? month, int? year}) async {
    final response = await dio.get('/budgets/status/', queryParameters: {
      if (month != null) 'month': month,
      if (year != null) 'year': year,
    });
    if (response.data is Map && response.data.containsKey('results')) {
      return response.data['results'];
    }
    return response.data;
  }

  Future<Map<String, dynamic>> createBudget(Map<String, dynamic> data) async {
    final response = await dio.post('/budgets/', data: data);
    return response.data;
  }

  Future<Map<String, dynamic>> updateBudget(int id, Map<String, dynamic> data) async {
    final response = await dio.patch('/budgets/$id/', data: data);
    return response.data;
  }

  Future<void> deleteBudget(int id) async {
    await dio.delete('/budgets/$id/');
  }

  // ── Recurring transactions ──
  Future<List<dynamic>> getRecurring() async {
    final response = await dio.get('/recurring/');
    if (response.data is Map && response.data.containsKey('results')) {
      return response.data['results'];
    }
    return response.data;
  }

  Future<Map<String, dynamic>> createRecurring(Map<String, dynamic> data) async {
    final response = await dio.post('/recurring/', data: data);
    return response.data;
  }

  Future<Map<String, dynamic>> updateRecurring(int id, Map<String, dynamic> data) async {
    final response = await dio.patch('/recurring/$id/', data: data);
    return response.data;
  }

  Future<void> deleteRecurring(int id) async {
    await dio.delete('/recurring/$id/');
  }

  /// Posts any recurring rules that have come due. Safe to call on app open —
  /// the server only materializes rules whose next_run has passed.
  Future<int> runDueRecurring() async {
    try {
      final response = await dio.post('/recurring/run-due/');
      return response.data['posted'] ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ── Export ──
  /// Raw CSV text of the filtered transactions, for sharing or saving.
  Future<String> exportTransactionsCsv({
    int? month, int? year, String? type, String? category, String? search,
  }) async {
    final response = await dio.get(
      '/transactions/export/',
      queryParameters: {
        if (month != null) 'month': month,
        if (year != null) 'year': year,
        if (type != null) 'type': type,
        if (category != null) 'category': category,
        if (search != null) 'search': search,
      },
      options: Options(responseType: ResponseType.plain),
    );
    return response.data.toString();
  }
}

