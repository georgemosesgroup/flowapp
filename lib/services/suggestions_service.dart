import 'package:flutter/services.dart';
import 'api_service.dart';
import 'speech_service.dart';

class SuggestionsService {
  static const _channel = MethodChannel('com.voiceassistant/suggestions');
  ApiService? _apiService;

  SuggestionsService() {
    _channel.setMethodCallHandler(_handleMethod);
  }

  void setApiService(ApiService api) => _apiService = api;

  Future<dynamic> _handleMethod(MethodCall call) async {
    if (call.method == 'onWordAdded') {
      final args = call.arguments as Map;
      final word = args['word'] as String;
      final replacement = args['replacement'] as String;
      // Save to backend
      await _apiService?.addDictionaryEntry(
        word: word,
        replacement: replacement.isNotEmpty ? replacement : null,
      );
    }
  }

  Future<void> showSuggestions(List<SuggestedWord> words) async {
    if (words.isEmpty) return;
    await _channel.invokeMethod('show', {
      'suggestions': words.map((w) => {
        'word': w.word,
        'replacement': w.replacement,
        'reason': w.reason,
      }).toList(),
    });
  }

  Future<void> hide() async {
    await _channel.invokeMethod('hide');
  }
}
