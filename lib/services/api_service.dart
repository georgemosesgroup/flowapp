import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class ApiService {
  final AuthService _auth;

  ApiService(this._auth);

  String get _baseUrl => _auth.serverUrl;
  Map<String, String> get _headers => _auth.authHeaders;

  Future<Map<String, dynamic>?> _get(String path) async {
    final resp = await http.get(Uri.parse('$_baseUrl$path'), headers: _headers);
    if (resp.statusCode == 401) {
      if (await _auth.refreshTokens()) {
        return _get(path);
      }
      return null;
    }
    if (resp.statusCode == 200) return jsonDecode(resp.body);
    return null;
  }

  Future<Map<String, dynamic>?> _post(String path, Map<String, dynamic> body) async {
    final resp = await http.post(Uri.parse('$_baseUrl$path'), headers: _headers, body: jsonEncode(body));
    if (resp.statusCode == 401) {
      if (await _auth.refreshTokens()) {
        return _post(path, body);
      }
      return null;
    }
    if (resp.statusCode == 200 || resp.statusCode == 201) return jsonDecode(resp.body);
    return null;
  }

  Future<bool> _delete(String path) async {
    final resp = await http.delete(Uri.parse('$_baseUrl$path'), headers: _headers);
    if (resp.statusCode == 401) {
      if (await _auth.refreshTokens()) {
        return _delete(path);
      }
      return false;
    }
    return resp.statusCode == 200;
  }

  Future<Map<String, dynamic>?> _patch(String path, Map<String, dynamic> body) async {
    final resp = await http.patch(
      Uri.parse('$_baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (resp.statusCode == 401) {
      if (await _auth.refreshTokens()) {
        return _patch(path, body);
      }
      return null;
    }
    if (resp.statusCode == 200) return jsonDecode(resp.body);
    return null;
  }

  // ── Dictations ──
  Future<List<Map<String, dynamic>>> getDictations({int limit = 50, int offset = 0}) async {
    final data = await _get('/api/v1/dictations?limit=$limit&offset=$offset');
    if (data == null) return [];
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  Future<bool> saveDictation({
    required String text,
    String? language,
    String? translatedText,
    String? translatedTo,
    required int wordCount,
    bool grammarApplied = false,
  }) async {
    final body = <String, dynamic>{
      'text': text,
      'word_count': wordCount,
    };
    if (language != null) body['language'] = language;
    if (translatedText != null) body['translated_text'] = translatedText;
    if (translatedTo != null) body['translated_to'] = translatedTo;
    // Only send when true — the backend column defaults to false and
    // older builds never set this, so omitting keeps backwards
    // compat with servers that haven't run migration 023 yet.
    if (grammarApplied) body['grammar_applied'] = true;
    final resp = await _post('/api/v1/dictations', body);
    return resp != null;
  }

  Future<bool> deleteDictation(String id) => _delete('/api/v1/dictations/$id');

  Future<bool> deleteAllDictations() => _delete('/api/v1/dictations');

  /// Save a user correction for a dictation. Returns true on success.
  /// qualityTags (optional) are tags from the canonical vocabulary
  /// (see asr_training_plan/04-templates/reviewer-workflow.md).
  Future<bool> correctDictation({
    required String id,
    required String correctedText,
    List<String>? qualityTags,
  }) async {
    final body = <String, dynamic>{'corrected_transcript': correctedText};
    if (qualityTags != null && qualityTags.isNotEmpty) {
      body['quality_tags'] = qualityTags;
    }
    final resp = await _patch('/api/v1/dictations/$id/correct', body);
    return resp != null;
  }

  /// Summary of training-sample volume for the current tenant.
  /// Returns null when unauthenticated or the backend has training disabled.
  Future<Map<String, dynamic>?> getTrainingStats() => _get('/api/v1/training/stats');

  // ── Dictionary ──
  Future<List<Map<String, dynamic>>> getDictionary() async {
    final data = await _get('/api/v1/dictionary');
    if (data == null) return [];
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  Future<bool> addDictionaryEntry({required String word, String? replacement, bool isShared = false}) async {
    final body = <String, dynamic>{
      'word': word,
      'is_shared': isShared,
    };
    if (replacement != null) body['replacement'] = replacement;
    final resp = await _post('/api/v1/dictionary', body);
    return resp != null;
  }

  Future<bool> deleteDictionaryEntry(String id) => _delete('/api/v1/dictionary/$id');

  // ── Snippets ──
  Future<List<Map<String, dynamic>>> getSnippets() async {
    final data = await _get('/api/v1/snippets');
    if (data == null) return [];
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  Future<bool> addSnippet({required String triggerPhrase, required String expansion, bool isShared = false}) async {
    final body = <String, dynamic>{
      'trigger_phrase': triggerPhrase,
      'expansion': expansion,
      'is_shared': isShared,
    };
    final resp = await _post('/api/v1/snippets', body);
    return resp != null;
  }

  Future<bool> deleteSnippet(String id) => _delete('/api/v1/snippets/$id');

  // ── Flow Usage ──
  Future<Map<String, dynamic>?> getFlowUsage() => _get('/api/v1/flow/usage');

  // ── Account ──
  Future<bool> updateProfile({required String name}) async {
    final resp = await _post('/api/v1/tenant', {'name': name});
    return resp != null;
  }

  Future<String?> changePassword({required String currentPassword, required String newPassword}) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/api/v1/auth/change-password'),
      headers: _headers,
      body: jsonEncode({'current_password': currentPassword, 'new_password': newPassword}),
    );
    if (resp.statusCode == 200) return null; // success
    final data = jsonDecode(resp.body);
    return data['error']?['message'] ?? 'Failed to change password';
  }
}
