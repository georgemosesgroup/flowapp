import 'package:flutter/services.dart';

class TextInsertionResult {
  final bool inserted;
  final String reason;

  TextInsertionResult({required this.inserted, required this.reason});
}

class TextInsertionService {
  static const _channel = MethodChannel('com.voiceassistant/speech');

  Future<TextInsertionResult> insertText(String text) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('pasteText', {
      'text': text,
    });

    return TextInsertionResult(
      inserted: result?['inserted'] as bool? ?? false,
      reason: result?['reason'] as String? ?? 'unknown',
    );
  }

  /// Simulates Cmd+Z in the frontmost application to undo the last insertion.
  ///
  /// Returns `true` if the undo keystroke was sent successfully, `false` on
  /// any platform error (e.g. missing Accessibility permission).
  Future<bool> undoInsertion() async {
    try {
      final ok = await _channel.invokeMethod<bool>('simulateUndo');
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }
}
