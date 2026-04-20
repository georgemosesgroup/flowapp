import 'package:flutter/services.dart';

class FlowBarService {
  static const _channel = MethodChannel('com.voiceassistant/flowbar');

  VoidCallback? onDismissed;

  /// Called when the user clicks "Undo" in the FlowBar's `done`-state
  /// tooltip (the "Inserted | Undo" pill rendered natively by
  /// `FlowBarUndoButton` in FlowBarWindow.swift). AppShell sets this to
  /// its `undoLastInsertion()` method so both surfaces — the FlowBar
  /// tooltip and the HomeScreen banner — share one undo path.
  VoidCallback? onUndo;

  /// Called when the user clicks the Stop button in the listening-state
  /// hover tooltip. AppShell wires this to `_stopAndTranscribe()`.
  VoidCallback? onStopClicked;

  FlowBarService() {
    _channel.setMethodCallHandler(_handleMethod);
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    if (call.method == 'onFlowBarDismissed') {
      onDismissed?.call();
    } else if (call.method == 'onFlowBarUndo') {
      onUndo?.call();
    } else if (call.method == 'onFlowBarStop') {
      onStopClicked?.call();
    }
  }

  Future<void> show({String state = 'idle', String? text, String? shortcutLabel}) async {
    await _channel.invokeMethod('show', {
      'state': state,
      'text': ?text,
      'shortcutLabel': ?shortcutLabel,
    });
  }

  Future<void> setShortcutLabel(String label) async {
    await _channel.invokeMethod('setShortcutLabel', {'label': label});
  }

  Future<void> hide() async {
    await _channel.invokeMethod('hide');
  }

  Future<void> updateState({required String state, String? text}) async {
    await _channel.invokeMethod('updateState', {
      'state': state,
      'text': ?text,
    });
  }

  Future<void> updateAudioLevel(double level, double urgency) async {
    try {
      await _channel.invokeMethod('updateAudioLevel', {
        'level': level,
        'urgency': urgency,
      });
    } catch (_) {}
  }
}
