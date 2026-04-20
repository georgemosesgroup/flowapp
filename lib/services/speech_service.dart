import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'storage_service.dart';

enum PermissionStatus { granted, denied, notDetermined }

class AudioLevelFrame {
  final double level;
  final double urgency;
  const AudioLevelFrame({required this.level, required this.urgency});
}

class PermissionsState {
  final PermissionStatus microphone;
  final PermissionStatus accessibility;

  PermissionsState({required this.microphone, required this.accessibility});

  bool get allGranted =>
      microphone == PermissionStatus.granted &&
      accessibility == PermissionStatus.granted;
}

class SuggestedWord {
  final String word;
  final String replacement;
  final String reason;

  SuggestedWord({required this.word, required this.replacement, required this.reason});

  factory SuggestedWord.fromJson(Map<String, dynamic> json) => SuggestedWord(
    word: json['word'] ?? '',
    replacement: json['replacement'] ?? '',
    reason: json['reason'] ?? '',
  );
}

class TranscribeResult {
  final String text;
  final String? language;
  final String? translatedText;
  final String? translatedTo;
  /// True when the backend post-processor applied a grammar/punctuation
  /// rewrite pass (toggle: Settings → Intelligence → Grammar correction).
  /// Threaded through to saveDictation so Home-screen cards can render a
  /// "Corrected" badge without reasking the transcribe pipeline.
  final bool grammarApplied;
  /// Which provider fulfilled the request. Not user-visible for now;
  /// the Settings → Privacy → Diagnostics card surfaces the most recent
  /// value so users can copy it when reporting issues.
  final String? provider;
  final List<SuggestedWord> suggestedWords;

  TranscribeResult({
    required this.text,
    this.language,
    this.translatedText,
    this.translatedTo,
    this.grammarApplied = false,
    this.provider,
    this.suggestedWords = const [],
  });
}

class SpeechService {
  static const _channel = MethodChannel('com.voiceassistant/speech');
  static const _maxRetries = 3;
  static const _requestTimeout = Duration(seconds: 180);
  bool _isRecording = false;
  AuthService? _authService;

  final StreamController<AudioLevelFrame> _audioLevelController =
      StreamController<AudioLevelFrame>.broadcast();
  Stream<AudioLevelFrame> get audioLevelStream => _audioLevelController.stream;

  bool get isRecording => _isRecording;

  void setAuthService(AuthService auth) => _authService = auth;

  static PermissionStatus _parseStatus(String status) {
    switch (status) {
      case 'granted':
        return PermissionStatus.granted;
      case 'denied':
        return PermissionStatus.denied;
      default:
        return PermissionStatus.notDetermined;
    }
  }

  Future<PermissionsState> checkPermissions() async {
    // Web has no native permission model — pretend everything's granted
    // so the app can route to the main screen during browser-based UI
    // debugging. Real permissions only exist on macOS.
    if (kIsWeb) {
      return PermissionsState(
        microphone: PermissionStatus.granted,
        accessibility: PermissionStatus.granted,
      );
    }
    final result =
        await _channel.invokeMapMethod<String, String>('checkPermissions');
    return PermissionsState(
      microphone: _parseStatus(result?['microphone'] ?? ''),
      accessibility: _parseStatus(result?['accessibility'] ?? ''),
    );
  }

  Future<bool> requestMicrophonePermission() async {
    final result =
        await _channel.invokeMethod<bool>('requestMicrophonePermission');
    return result ?? false;
  }

  Future<void> openSystemPreferences(String pane) async {
    await _channel.invokeMethod('openSystemPreferences', {'pane': pane});
  }

  Future<void> openAccessibilitySettings() async {
    await _channel.invokeMethod('openAccessibilitySettings');
  }

  Future<bool> startRecording() async {
    if (_isRecording) return false;
    try {
      final result = await _channel.invokeMethod<bool>('startRecording');
      _isRecording = result ?? false;
      return _isRecording;
    } catch (e) {
      return false;
    }
  }

  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    _isRecording = false;
    try {
      return await _channel.invokeMethod<String>('stopRecording');
    } catch (e) {
      return null;
    }
  }

  Future<void> cancelRecording() async {
    _isRecording = false;
    try {
      await _channel.invokeMethod('cancelRecording');
    } catch (_) {}
  }

  Future<void> setSilenceDetection(bool enabled) async {
    await _channel.invokeMethod('setSilenceDetection', {'enabled': enabled});
  }

  Future<void> setSilenceTimeout(double seconds) async {
    await _channel.invokeMethod('setSilenceTimeout', {'seconds': seconds});
  }

  void pushAudioLevel(double level, double urgency) {
    _audioLevelController.add(AudioLevelFrame(level: level, urgency: urgency));
  }

  void log(String msg) {
    final f = File('${Platform.environment['HOME']}/flow_debug.log');
    f.writeAsStringSync('${DateTime.now()}: $msg\n', mode: FileMode.append);
  }

  Future<TranscribeResult?> transcribeWithTranslation(
    String filePath, {
    String? language,
    String? translateTo,
    String? style,
    bool? grammar,
  }) async {
    log('transcribeWithTranslation start file=$filePath lang=$language translateTo=$translateTo');

    if (_authService == null || !_authService!.isLoggedIn) {
      log('ERROR: not logged in');
      return null;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      log('ERROR: file not found');
      return null;
    }

    final fileSize = await file.length();
    log('file size=$fileSize bytes');

    // Retry loop for transient failures (5xx, timeouts)
    for (var attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${_authService!.serverUrl}/api/v1/transcribe'),
        );

        request.headers['Authorization'] = 'Bearer ${_authService!.accessToken}';
        // Training-consent opt-in. Only set when the user has enabled
        // "Help improve the model" in Settings → Privacy.
        if (StorageService.instance.helpImproveModel) {
          request.headers['X-Training-Consent'] = 'true';
        }

        if (language != null && language.isNotEmpty) {
          request.fields['language'] = language;
        }
        if (translateTo != null && translateTo.isNotEmpty) {
          request.fields['translate_to'] = translateTo;
        }
        if (style != null && style.isNotEmpty && style != 'formal') {
          request.fields['style'] = style;
        }
        if (grammar == true) {
          request.fields['grammar'] = 'true';
        }
        request.fields['auto_detect'] = 'true';

        request.files.add(await http.MultipartFile.fromPath('file', filePath));

        log('sending request (attempt $attempt/$_maxRetries)...');
        final response = await request.send().timeout(_requestTimeout);
        final body = await response.stream.bytesToString();
        log('response status=${response.statusCode} body_length=${body.length}');

        if (response.statusCode == 200) {
          final data = jsonDecode(body);
          final suggestedRaw = data['suggested_words'] as List? ?? [];
          final result = TranscribeResult(
            text: data['text'] as String? ?? '',
            language: data['language'] as String?,
            translatedText: data['translated_text'] as String?,
            translatedTo: data['translated_to'] as String?,
            grammarApplied: data['grammar_applied'] as bool? ?? false,
            provider: data['provider'] as String?,
            suggestedWords: suggestedRaw.map((w) => SuggestedWord.fromJson(Map<String, dynamic>.from(w))).toList(),
          );
          log('SUCCESS text_length=${result.text.length} translated_length=${result.translatedText?.length ?? 0}');
          try { await file.delete(); } catch (_) {}
          return result;
        }

        // Token expired — refresh and retry once
        if (response.statusCode == 401) {
          log('401 — refreshing token');
          final refreshed = await _authService!.refreshTokens();
          if (refreshed) {
            return transcribeWithTranslation(filePath, language: language, translateTo: translateTo, style: style, grammar: grammar);
          }
          break; // refresh failed, stop
        }

        // Server error — retry with backoff
        if (response.statusCode >= 500 && attempt < _maxRetries) {
          log('5xx error (${response.statusCode}), retrying in ${attempt}s...');
          await Future.delayed(Duration(seconds: attempt));
          continue;
        }

        // 4xx or last attempt — give up
        log('ERROR status=${response.statusCode}');
        break;
      } on TimeoutException {
        log('TIMEOUT (attempt $attempt/$_maxRetries)');
        if (attempt < _maxRetries) {
          await Future.delayed(Duration(seconds: attempt));
          continue;
        }
      } catch (e) {
        log('EXCEPTION (attempt $attempt/$_maxRetries): $e');
        if (attempt < _maxRetries) {
          await Future.delayed(Duration(seconds: attempt));
          continue;
        }
      }
    }

    try { await File(filePath).delete(); } catch (_) {}
    return null;
  }

  Future<String?> transcribe(String filePath, {String? language}) async {
    if (_authService == null || !_authService!.isLoggedIn) return null;

    final file = File(filePath);
    if (!await file.exists()) return null;

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${_authService!.serverUrl}/api/v1/transcribe'),
      );

      request.headers['Authorization'] = 'Bearer ${_authService!.accessToken}';

      if (language != null && language.isNotEmpty) {
        request.fields['language'] = language;
      }

      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      final response = await request.send().timeout(_requestTimeout);
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(body);
        return data['text'] as String?;
      }

      if (response.statusCode == 401) {
        final refreshed = await _authService!.refreshTokens();
        if (refreshed) {
          return transcribe(filePath, language: language);
        }
      }

      return null;
    } catch (e) {
      return null;
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  // MARK: - System controls

  Future<void> setLaunchAtLogin(bool enabled) async {
    if (kIsWeb) return;
    await _channel.invokeMethod('setLaunchAtLogin', {'enabled': enabled});
  }

  Future<void> setDockVisibility(bool visible) async {
    if (kIsWeb) return;
    await _channel.invokeMethod('setDockVisibility', {'visible': visible});
  }

  Future<void> setupStatusBar() async {
    if (kIsWeb) return;
    await _channel.invokeMethod('setupStatusBar');
  }

  Future<List<Map<String, String>>> listMicrophones() async {
    final result = await _channel.invokeListMethod<Map>('listMicrophones');
    return result?.map((m) => Map<String, String>.from(m)).toList() ?? [];
  }

  Future<void> playSound(String name) async {
    await _channel.invokeMethod('playSound', {'sound': name});
  }
}
