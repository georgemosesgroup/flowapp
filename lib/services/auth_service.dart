import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/saved_account.dart';
import 'storage_service.dart';

class AuthService {
  /// Production backend. Desktop builds point here by default; the
  /// dashboard/admin tools live at the sibling `app.flow.mosesdev.com`
  /// and `admin.flow.mosesdev.com` origins.
  static const _defaultServerUrl = 'https://api.flow.mosesdev.com';

  String _serverUrl = _defaultServerUrl;
  String _accessToken = '';
  String _refreshToken = '';
  String _userName = '';
  String _userEmail = '';
  String? _userWorkspace;
  String? _userRole;

  bool get isLoggedIn => _accessToken.isNotEmpty;
  String get accessToken => _accessToken;
  String get serverUrl => _serverUrl;
  String get userName => _userName;
  String get userEmail => _userEmail;
  String? get userWorkspace => _userWorkspace;
  String? get userRole => _userRole;

  Map<String, String> get authHeaders => {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
      };

  /// Snapshot of the currently-active account as a `SavedAccount`.
  /// Returned shape matches what the account picker consumes.
  SavedAccount? get currentAccount {
    if (_userEmail.isEmpty) return null;
    return SavedAccount(
      email: _userEmail,
      name: _userName,
      workspace: _userWorkspace,
      role: _userRole,
      serverUrl: _serverUrl,
      lastUsedAt: DateTime.now(),
    );
  }

  void setServerUrl(String url) {
    _serverUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Try to restore the last-active session from secure storage.
  /// Returns `true` when the stashed access token was still valid (or
  /// could be refreshed); `false` otherwise. Failure leaves the
  /// active slots cleared but does NOT remove the account from the
  /// saved list — so the UI can still show the picker.
  Future<bool> tryAutoLogin() async {
    final storage = StorageService.instance;
    if (!storage.hasAuth) return false;

    _accessToken = storage.accessToken;
    _refreshToken = storage.refreshToken;
    _userName = storage.userName;
    _userEmail = storage.userEmail;

    return _probeAndRefresh();
  }

  /// Swap the active account over to [email] from the saved list and
  /// validate its token. Same return semantics as `tryAutoLogin`.
  Future<bool> trySilentAuthWith(String email) async {
    final storage = StorageService.instance;
    final activated = await storage.activateAccount(email);
    if (!activated) return false;

    _accessToken = storage.accessToken;
    _refreshToken = storage.refreshToken;
    _userName = storage.userName;
    _userEmail = storage.userEmail;

    // Seed workspace/role from the saved-list entry so the shell has
    // sane defaults before the probe refreshes them.
    final saved = storage.savedAccounts.where((a) => a.email == email);
    if (saved.isNotEmpty) {
      _userWorkspace = saved.first.workspace;
      _userRole = saved.first.role;
    }

    return _probeAndRefresh();
  }

  /// Ping `/api/v1/tenant` with the current access token. On 200 we
  /// refresh the cached profile; on 401 we try to swap the refresh
  /// token. Any other failure drops the active slots (but leaves the
  /// saved list intact).
  Future<bool> _probeAndRefresh() async {
    try {
      final resp = await http.get(
        Uri.parse('$_serverUrl/api/v1/tenant'),
        headers: authHeaders,
      );

      if (resp.statusCode == 200) {
        _hydrateTenant(jsonDecode(resp.body));
        await _persistActive();
        return true;
      }

      if (resp.statusCode == 401) {
        final refreshed = await refreshTokens();
        return refreshed;
      }
    } catch (_) {}

    await StorageService.instance.clearAuth();
    _accessToken = '';
    _refreshToken = '';
    return false;
  }

  Future<LoginResult> login(String email, String password) async {
    try {
      final resp = await http.post(
        Uri.parse('$_serverUrl/api/v1/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final tokens = data['tokens'] ?? data;
        _accessToken = (tokens['access_token'] ?? '').toString();
        _refreshToken = (tokens['refresh_token'] ?? '').toString();
        _hydrateTenant(data['tenant'] as Map<String, dynamic>?);

        await _persistActive();
        await _persistSavedAccount();

        return LoginResult(success: true);
      } else {
        final data = jsonDecode(resp.body);
        final err = data['error'];
        return LoginResult(
          success: false,
          error: err is Map
              ? err['message'] ?? 'Ошибка'
              : err?.toString() ?? 'Ошибка авторизации',
        );
      }
    } catch (_) {
      return LoginResult(success: false, error: 'Нет связи с сервером');
    }
  }

  Future<bool> refreshTokens() async {
    if (_refreshToken.isEmpty) return false;

    try {
      final resp = await http.post(
        Uri.parse('$_serverUrl/api/v1/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': _refreshToken}),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        _accessToken = (data['access_token'] ?? '').toString();
        _refreshToken =
            (data['refresh_token'] ?? _refreshToken).toString();

        await _persistActive();
        await _persistSavedAccount();
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// Sign out of the currently active session. By default keeps the
  /// account in the saved list so the picker can still show it; pass
  /// [forget] to also wipe it from the list and its stashed tokens.
  Future<void> logout({bool forget = false}) async {
    final email = _userEmail;
    _accessToken = '';
    _refreshToken = '';
    _userName = '';
    _userEmail = '';
    _userWorkspace = null;
    _userRole = null;
    await StorageService.instance.clearAuth();
    if (forget && email.isNotEmpty) {
      await StorageService.instance.forgetAccount(email);
    }
  }

  // ── internals ─────────────────────────────────────────────────────

  void _hydrateTenant(Map<String, dynamic>? tenant) {
    if (tenant == null) return;
    _userName = (tenant['name'] ?? _userName).toString();
    _userEmail = (tenant['email'] ?? _userEmail).toString();
    final company = tenant['company'];
    if (company != null) {
      final s = company.toString();
      _userWorkspace = s.isEmpty ? null : s;
    }
    final role = tenant['role'];
    if (role != null) {
      final s = role.toString();
      _userRole = s.isEmpty ? null : s;
    }
  }

  Future<void> _persistActive() async {
    await StorageService.instance.saveAuth(
      accessToken: _accessToken,
      refreshToken: _refreshToken,
      userName: _userName,
      userEmail: _userEmail,
    );
    await StorageService.instance.setLastActiveEmail(_userEmail);
  }

  Future<void> _persistSavedAccount() async {
    if (_userEmail.isEmpty) return;
    final account = SavedAccount(
      email: _userEmail,
      name: _userName,
      workspace: _userWorkspace,
      role: _userRole,
      serverUrl: _serverUrl,
      lastUsedAt: DateTime.now(),
    );
    await StorageService.instance.saveAccount(
      account: account,
      accessToken: _accessToken,
      refreshToken: _refreshToken,
    );
  }
}

class LoginResult {
  final bool success;
  final String? error;

  LoginResult({required this.success, this.error});
}
