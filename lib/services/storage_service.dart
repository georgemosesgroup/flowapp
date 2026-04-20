import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_account.dart';

class StorageService {
  static StorageService? _instance;
  late SharedPreferences _prefs;
  late FlutterSecureStorage _secure;

  // True when keychain access works. When false, we fall back to SharedPreferences
  // (used in ad-hoc-signed debug builds where keychain access may be denied with
  // errSecMissingEntitlement / -34018).
  bool _secureAvailable = true;

  // In-memory cache for secure token values (sync access)
  String _cachedAccessToken = '';
  String _cachedRefreshToken = '';
  String _cachedUserName = '';
  String _cachedUserEmail = '';

  StorageService._();

  static Future<StorageService> init() async {
    if (_instance != null) return _instance!;
    _instance = StorageService._();
    _instance!._prefs = await SharedPreferences.getInstance();
    _instance!._secure = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      mOptions: MacOsOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );

    // Probe keychain availability; disable if unavailable (ad-hoc debug).
    try {
      await _instance!._secure.read(key: '_keychain_probe');
    } catch (_) {
      _instance!._secureAvailable = false;
    }

    await _instance!._migrateTokens();
    await _instance!._loadSecureCache();
    return _instance!;
  }

  static StorageService get instance => _instance!;

  /// One-time migration from SharedPreferences (plaintext) to Keychain.
  Future<void> _migrateTokens() async {
    final migrated = _prefs.getBool('_tokens_migrated') ?? false;
    if (migrated) return;

    if (!_secureAvailable) {
      // Can't migrate into keychain; leave plaintext values in SharedPreferences.
      await _prefs.setBool('_tokens_migrated', true);
      return;
    }

    try {
      final oldAccess = _prefs.getString('access_token');
      final oldRefresh = _prefs.getString('refresh_token');
      final oldName = _prefs.getString('user_name');
      final oldEmail = _prefs.getString('user_email');

      if (oldAccess != null && oldAccess.isNotEmpty) {
        await _secure.write(key: 'access_token', value: oldAccess);
      }
      if (oldRefresh != null && oldRefresh.isNotEmpty) {
        await _secure.write(key: 'refresh_token', value: oldRefresh);
      }
      if (oldName != null && oldName.isNotEmpty) {
        await _secure.write(key: 'user_name', value: oldName);
      }
      if (oldEmail != null && oldEmail.isNotEmpty) {
        await _secure.write(key: 'user_email', value: oldEmail);
      }

      // Remove plaintext tokens
      await _prefs.remove('access_token');
      await _prefs.remove('refresh_token');
      await _prefs.remove('user_name');
      await _prefs.remove('user_email');
      await _prefs.setBool('_tokens_migrated', true);
    } catch (_) {
      // Migration failed — mark migrated, keep plaintext in prefs as fallback.
      try { await _secure.deleteAll(); } catch (_) {}
      await _prefs.setBool('_tokens_migrated', true);
    }
  }

  /// Load secure values into memory for synchronous access.
  Future<void> _loadSecureCache() async {
    if (_secureAvailable) {
      try {
        _cachedAccessToken = await _secure.read(key: 'access_token') ?? '';
        _cachedRefreshToken = await _secure.read(key: 'refresh_token') ?? '';
        _cachedUserName = await _secure.read(key: 'user_name') ?? '';
        _cachedUserEmail = await _secure.read(key: 'user_email') ?? '';
        return;
      } catch (_) {
        _secureAvailable = false;
      }
    }
    // Fallback: SharedPreferences (debug-only, no encryption).
    _cachedAccessToken = _prefs.getString('access_token') ?? '';
    _cachedRefreshToken = _prefs.getString('refresh_token') ?? '';
    _cachedUserName = _prefs.getString('user_name') ?? '';
    _cachedUserEmail = _prefs.getString('user_email') ?? '';
  }

  // Generic
  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) => _prefs.setString(key, value);

  // Auth (secure storage — synchronous via cache)
  String get accessToken => _cachedAccessToken;
  String get refreshToken => _cachedRefreshToken;
  String get userName => _cachedUserName;
  String get userEmail => _cachedUserEmail;

  Future<void> saveAuth({
    required String accessToken,
    required String refreshToken,
    required String userName,
    required String userEmail,
  }) async {
    _cachedAccessToken = accessToken;
    _cachedRefreshToken = refreshToken;
    _cachedUserName = userName;
    _cachedUserEmail = userEmail;
    if (_secureAvailable) {
      try {
        await _secure.write(key: 'access_token', value: accessToken);
        await _secure.write(key: 'refresh_token', value: refreshToken);
        await _secure.write(key: 'user_name', value: userName);
        await _secure.write(key: 'user_email', value: userEmail);
        return;
      } catch (_) {
        _secureAvailable = false;
      }
    }
    // Fallback — SharedPreferences (dev only).
    await _prefs.setString('access_token', accessToken);
    await _prefs.setString('refresh_token', refreshToken);
    await _prefs.setString('user_name', userName);
    await _prefs.setString('user_email', userEmail);
  }

  Future<void> clearAuth() async {
    _cachedAccessToken = '';
    _cachedRefreshToken = '';
    _cachedUserName = '';
    _cachedUserEmail = '';
    if (_secureAvailable) {
      try {
        await _secure.delete(key: 'access_token');
        await _secure.delete(key: 'refresh_token');
        await _secure.delete(key: 'user_name');
        await _secure.delete(key: 'user_email');
      } catch (_) {}
    }
    await _prefs.remove('access_token');
    await _prefs.remove('refresh_token');
    await _prefs.remove('user_name');
    await _prefs.remove('user_email');
  }

  bool get hasAuth => _cachedAccessToken.isNotEmpty;

  // ───────────────────────── Multi-account ───────────────────────────
  //
  // In addition to the "currently active" token slots above (which
  // point at whichever account is signed in right now), we keep a
  // list of every account the user has previously signed in with.
  // The list lives in SharedPreferences as a JSON array; per-account
  // tokens live in secure storage keyed by email
  // (`access_token:{email}`, `refresh_token:{email}`).
  //
  // The "active" slots are kept in sync on every login/switch so
  // the current single-account API stays drop-in for the parts of
  // the app that don't need the picker (API service, etc.).
  //
  // Removing an account from the list also wipes its keyed tokens.

  static const _savedAccountsKey = 'saved_accounts';
  static const _lastActiveEmailKey = 'last_active_email';

  String _accessTokenKey(String email) => 'access_token:$email';
  String _refreshTokenKey(String email) => 'refresh_token:$email';

  List<SavedAccount> get savedAccounts {
    final raw = _prefs.getString(_savedAccountsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(SavedAccount.fromJson)
          .where((a) => a.email.isNotEmpty)
          .toList()
        ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeSavedAccounts(List<SavedAccount> accounts) async {
    final encoded = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await _prefs.setString(_savedAccountsKey, encoded);
  }

  /// Email of the account we last picked. `null` if the user has
  /// never signed in on this device or explicitly signed out of all.
  String? get lastActiveEmail => _prefs.getString(_lastActiveEmailKey);

  Future<void> setLastActiveEmail(String? email) async {
    if (email == null || email.isEmpty) {
      await _prefs.remove(_lastActiveEmailKey);
    } else {
      await _prefs.setString(_lastActiveEmailKey, email);
    }
  }

  /// Upsert (dedupe by email) and bump `lastUsedAt`. Also writes the
  /// per-email tokens into secure storage for later silent re-auth.
  Future<void> saveAccount({
    required SavedAccount account,
    required String accessToken,
    required String refreshToken,
  }) async {
    final existing = savedAccounts;
    final filtered =
        existing.where((a) => a.email != account.email).toList(growable: true);
    filtered.add(account);
    await _writeSavedAccounts(filtered);

    if (_secureAvailable) {
      try {
        await _secure.write(
          key: _accessTokenKey(account.email),
          value: accessToken,
        );
        await _secure.write(
          key: _refreshTokenKey(account.email),
          value: refreshToken,
        );
      } catch (_) {
        _secureAvailable = false;
      }
    }
    if (!_secureAvailable) {
      await _prefs.setString(_accessTokenKey(account.email), accessToken);
      await _prefs.setString(_refreshTokenKey(account.email), refreshToken);
    }
  }

  /// Read tokens that were stashed for [email] at last login. Returns
  /// empty strings when nothing is stored (e.g. the account was
  /// forgotten, or secure storage was wiped).
  Future<(String access, String refresh)> readAccountTokens(
      String email) async {
    if (_secureAvailable) {
      try {
        final a = await _secure.read(key: _accessTokenKey(email)) ?? '';
        final r = await _secure.read(key: _refreshTokenKey(email)) ?? '';
        return (a, r);
      } catch (_) {
        _secureAvailable = false;
      }
    }
    return (
      _prefs.getString(_accessTokenKey(email)) ?? '',
      _prefs.getString(_refreshTokenKey(email)) ?? '',
    );
  }

  /// Drop a single account from the saved list and wipe its tokens.
  /// Doesn't touch the "active" slots — caller should sign out first
  /// if the account being removed is the current one.
  Future<void> forgetAccount(String email) async {
    final remaining = savedAccounts.where((a) => a.email != email).toList();
    await _writeSavedAccounts(remaining);
    if (_secureAvailable) {
      try {
        await _secure.delete(key: _accessTokenKey(email));
        await _secure.delete(key: _refreshTokenKey(email));
      } catch (_) {}
    }
    await _prefs.remove(_accessTokenKey(email));
    await _prefs.remove(_refreshTokenKey(email));
    if (lastActiveEmail == email) {
      await setLastActiveEmail(null);
    }
  }

  /// Swap the "active" token slots over to an account from the saved
  /// list. Does NOT hit the network — AuthService decides whether the
  /// stashed token is still valid (via a `/tenant` probe).
  Future<bool> activateAccount(String email) async {
    final tokens = await readAccountTokens(email);
    if (tokens.$1.isEmpty || tokens.$2.isEmpty) return false;

    final matches = savedAccounts.where((a) => a.email == email);
    final account = matches.isEmpty ? null : matches.first;
    await saveAuth(
      accessToken: tokens.$1,
      refreshToken: tokens.$2,
      userName: account?.name ?? '',
      userEmail: email,
    );
    await setLastActiveEmail(email);
    return true;
  }

  // Settings - General
  String get hotkeyMode => _prefs.getString('hotkey_mode') ?? 'hold_ctrl';
  String get language => _prefs.getString('language') ?? 'ru';
  String get customHotkeyDisplay => _prefs.getString('custom_hotkey_display') ?? '';
  int get customHotkeyCode => _prefs.getInt('custom_hotkey_code') ?? 0;
  int get customHotkeyModifiers => _prefs.getInt('custom_hotkey_modifiers') ?? 0;

  Future<void> setHotkeyMode(String mode) => _prefs.setString('hotkey_mode', mode);
  Future<void> setLanguage(String lang) => _prefs.setString('language', lang);
  Future<void> setCustomHotkey(String display, int code, int modifiers) async {
    await _prefs.setString('custom_hotkey_display', display);
    await _prefs.setInt('custom_hotkey_code', code);
    await _prefs.setInt('custom_hotkey_modifiers', modifiers);
  }

  // Settings - Microphone
  String get selectedMicId => _prefs.getString('selected_mic_id') ?? '';
  Future<void> setSelectedMicId(String id) => _prefs.setString('selected_mic_id', id);

  // Settings - System
  bool get launchAtLogin => _prefs.getBool('launch_at_login') ?? false;
  bool get showFlowBar => _prefs.getBool('show_flow_bar') ?? true;
  bool get dictationReminder => _prefs.getBool('dictation_reminder') ?? true;
  bool get showInDock => _prefs.getBool('show_in_dock') ?? false;
  bool get dictationSounds => _prefs.getBool('dictation_sounds') ?? true;
  bool get muteMusicWhileDictating => _prefs.getBool('mute_music') ?? false;
  bool get autoAddToDictionary => _prefs.getBool('auto_add_dictionary') ?? true;
  bool get smartFormatting => _prefs.getBool('smart_formatting') ?? true;

  Future<void> setLaunchAtLogin(bool v) => _prefs.setBool('launch_at_login', v);
  Future<void> setShowFlowBar(bool v) => _prefs.setBool('show_flow_bar', v);
  Future<void> setDictationReminder(bool v) => _prefs.setBool('dictation_reminder', v);
  Future<void> setShowInDock(bool v) => _prefs.setBool('show_in_dock', v);
  Future<void> setDictationSounds(bool v) => _prefs.setBool('dictation_sounds', v);
  Future<void> setMuteMusicWhileDictating(bool v) => _prefs.setBool('mute_music', v);
  Future<void> setAutoAddToDictionary(bool v) => _prefs.setBool('auto_add_dictionary', v);
  Future<void> setSmartFormatting(bool v) => _prefs.setBool('smart_formatting', v);

  // Settings - Grammar
  bool get grammarCorrection => _prefs.getBool('grammar_correction') ?? true;
  Future<void> setGrammarCorrection(bool v) => _prefs.setBool('grammar_correction', v);

  // Settings - Realtime dictation. Now ON by default: the end-to-end
  // pipeline is production-ready (gemini-2.5-flash-native-audio proxy,
  // shadow training capture on session end, automatic fallback to the
  // batch HTTP path if the WebSocket can't be opened). Users who want
  // to force the old batch flow can still turn this off in Settings.
  bool get liveDictationEnabled => _prefs.getBool('live_dictation_enabled') ?? true;
  Future<void> setLiveDictationEnabled(bool v) => _prefs.setBool('live_dictation_enabled', v);

  // Seconds of continuous silence before VAD auto-stops non-hold recordings.
  // Only applies in toggle/custom modes — hold-to-talk disables silence
  // detection while the hotkey is pressed so pauses don't cut the user off.
  double get silenceTimeoutSeconds => _prefs.getDouble('silence_timeout_seconds') ?? 1.5;
  Future<void> setSilenceTimeoutSeconds(double v) =>
      _prefs.setDouble('silence_timeout_seconds', v.clamp(0.5, 5.0));

  // Settings - Translation
  // mode: "off", "auto", "voice_trigger"
  String get translationMode => _prefs.getString('translation_mode') ?? 'off';
  String get translateTo => _prefs.getString('translate_to') ?? 'en';
  Future<void> setTranslationMode(String mode) => _prefs.setString('translation_mode', mode);
  Future<void> setTranslateTo(String lang) => _prefs.setString('translate_to', lang);

  // Settings - Style
  String get dictationStyle => _prefs.getString('dictation_style') ?? 'formal';
  Future<void> setDictationStyle(String style) => _prefs.setString('dictation_style', style);

  // Diagnostics — non-sensitive metadata shown in Settings → Privacy →
  // Diagnostics. Populated on every successful transcribe. Transcript text
  // is NEVER stored here; only the provider id (e.g. "gemini-stt",
  // "whisper-hy-modal") so the user can copy-paste when reporting bugs.
  String get lastProvider => _prefs.getString('diag_last_provider') ?? '';
  Future<void> setLastProvider(String provider) =>
      _prefs.setString('diag_last_provider', provider);

  // Settings - Training corpus participation (opt-in, default OFF).
  // When true, the desktop client sends X-Training-Consent: true with each
  // transcribe request so the backend may retain the audio for model
  // improvement. See asr_training_plan/ for the full policy.
  bool get helpImproveModel => _prefs.getBool('help_improve_model') ?? false;
  Future<void> setHelpImproveModel(bool v) => _prefs.setBool('help_improve_model', v);

  // Reset
  Future<void> resetAll() async {
    if (_secureAvailable) {
      try { await _secure.deleteAll(); } catch (_) {}
    }
    _cachedAccessToken = '';
    _cachedRefreshToken = '';
    _cachedUserName = '';
    _cachedUserEmail = '';
    await _prefs.clear();
  }
}
