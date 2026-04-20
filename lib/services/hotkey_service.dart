import 'package:flutter/services.dart';

enum HotkeyMode { doubleCtrl, holdCtrl, custom }

class HotkeyService {
  static const _channel = MethodChannel('com.voiceassistant/hotkey');

  VoidCallback? onToggle;
  VoidCallback? onHoldStart;
  VoidCallback? onHoldEnd;
  void Function(String displayName, int keyCode, int modifiers)? onRecorded;
  void Function(String displayName)? onRecordingUpdate;

  HotkeyMode _mode = HotkeyMode.holdCtrl;
  String _displayName = 'Hold ^ Ctrl';
  int? _customKeyCode;
  int? _customModifiers;

  HotkeyMode get mode => _mode;
  String get displayName => _displayName;

  /// Restore mode without calling native (for init before start())
  void restoreMode(HotkeyMode mode) {
    _mode = mode;
    switch (mode) {
      case HotkeyMode.holdCtrl:
        _displayName = 'Hold ^ Ctrl';
        break;
      case HotkeyMode.doubleCtrl:
        _displayName = 'Double-tap ^ Ctrl';
        break;
      case HotkeyMode.custom:
        break;
    }
  }

  /// Restore custom hotkey params without calling native
  void restoreCustom(int keyCode, int modifiers, String displayName) {
    _mode = HotkeyMode.custom;
    _customKeyCode = keyCode;
    _customModifiers = modifiers;
    _displayName = displayName.isNotEmpty ? displayName : 'Custom';
  }

  HotkeyService() {
    _channel.setMethodCallHandler(_handleMethod);
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'onHotkeyPressed':
        onToggle?.call();
        break;
      case 'onHotkeyDown':
        onHoldStart?.call();
        break;
      case 'onHotkeyUp':
        onHoldEnd?.call();
        break;
      case 'onHotkeyRecorded':
        final args = call.arguments as Map;
        final display = args['displayName'] as String;
        final keyCode = args['keyCode'] as int;
        final modifiers = args['modifiers'] as int;
        onRecorded?.call(display, keyCode, modifiers);
        break;
      case 'onHotkeyRecordingUpdate':
        final args = call.arguments as Map;
        final display = args['displayName'] as String;
        onRecordingUpdate?.call(display);
        break;
    }
  }

  Future<void> start({
    required VoidCallback onToggle,
    VoidCallback? onHoldStart,
    VoidCallback? onHoldEnd,
  }) async {
    this.onToggle = onToggle;
    this.onHoldStart = onHoldStart;
    this.onHoldEnd = onHoldEnd;

    String modeStr;
    switch (_mode) {
      case HotkeyMode.doubleCtrl:
        modeStr = 'double_ctrl';
        break;
      case HotkeyMode.holdCtrl:
        modeStr = 'hold_ctrl';
        break;
      case HotkeyMode.custom:
        modeStr = 'custom';
        break;
    }

    await _channel.invokeMethod('startListening', {
      'mode': modeStr,
      if (_customKeyCode != null) 'keyCode': _customKeyCode,
      if (_customModifiers != null) 'modifiers': _customModifiers,
    });
  }

  Future<void> setMode(HotkeyMode mode) async {
    _mode = mode;
    switch (mode) {
      case HotkeyMode.doubleCtrl:
        _displayName = 'Double-tap ^ Ctrl';
        break;
      case HotkeyMode.holdCtrl:
        _displayName = 'Hold ^ Ctrl';
        break;
      case HotkeyMode.custom:
        break;
    }
    await _channel.invokeMethod('setMode', {
      'mode': mode == HotkeyMode.doubleCtrl
          ? 'double_ctrl'
          : mode == HotkeyMode.holdCtrl
              ? 'hold_ctrl'
              : 'custom',
    });
  }

  Future<void> setCustomHotkey(int keyCode, int modifiers, String displayName) async {
    _mode = HotkeyMode.custom;
    _customKeyCode = keyCode;
    _customModifiers = modifiers;
    _displayName = displayName;
    // Restart native listener with new custom params
    await _channel.invokeMethod('startListening', {
      'mode': 'custom',
      'keyCode': keyCode,
      'modifiers': modifiers,
    });
  }

  Future<void> startRecording({
    required void Function(String displayName, int keyCode, int modifiers) onRecorded,
    void Function(String displayName)? onUpdate,
  }) async {
    this.onRecorded = onRecorded;
    onRecordingUpdate = onUpdate;
    await _channel.invokeMethod('startRecording');
  }

  Future<void> stopRecording() async {
    await _channel.invokeMethod('stopRecording');
    onRecorded = null;
  }

  Future<void> stop() async {
    await _channel.invokeMethod('stopListening');
  }

  Future<void> dispose() async {
    await stop();
  }
}
