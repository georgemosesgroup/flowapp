import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/speech_service.dart';
import '../services/hotkey_service.dart';
import '../services/storage_service.dart';
import '../services/flow_bar_service.dart';
import '../services/text_insertion_service.dart';
import '../services/api_service.dart';
import '../services/realtime_dictate_service.dart';
import '../services/update_service.dart';
import '../theme/tokens.dart';
import '../widgets/sidebar.dart';
import '../widgets/toolbar_inset.dart';
import '../widgets/update_banner.dart';
import '../widgets/update_download_dialog.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'account_screen.dart';
import 'dictionary_screen.dart';
import 'snippets_screen.dart';
import 'style_screen.dart';
import 'scratchpad_screen.dart';
import '../services/suggestions_service.dart';

/// Maps a raw transcribe-API / realtime error string to a short user-facing
/// message. The mapper is a top-level pure function so HomeScreen, error
/// banners, and any future surface can reuse it without reaching into the
/// AppShell State. Logging code continues to show the raw error untouched —
/// only the UI substitutes the friendly copy.
///
/// Keep the set small and intentional. Each new branch should be motivated
/// by a real error string we've seen in production; generic catch-alls
/// ("Transcription failed") cover the long tail.
String mapTranscribeError(String? raw) {
  if (raw == null || raw.isEmpty) return 'Something went wrong';
  final e = raw.toLowerCase();
  if (e.contains('unsupported audio')) return 'Audio format not supported';
  if (e.contains('not configured')) return 'Service temporarily unavailable';
  if (e.contains('rate_limit') || e.contains('rate limit') || e.contains('429')) {
    return 'Too many requests — wait a moment and try again';
  }
  if (e.contains('quota') || e.contains('word limit')) {
    return 'You\'ve hit your plan\'s word limit';
  }
  if (e.contains('timeout') || e.contains('deadline')) {
    return 'Transcription is taking too long — check your connection';
  }
  if (e.contains('unauthorized') || e.contains('401')) {
    return 'Session expired — please sign in again';
  }
  if (e.contains('no internet') || e.contains('network')) return 'No connection';
  return 'Transcription failed';
}

class AppShell extends StatefulWidget {
  final AuthService authService;
  final SpeechService speechService;
  final VoidCallback onLogout;

  const AppShell({
    super.key,
    required this.authService,
    required this.speechService,
    required this.onLogout,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  NavItem _selectedNav = NavItem.home;
  bool _showAccount = false;
  bool _sidebarCollapsed = false;
  final HotkeyService _hotkeyService = HotkeyService();
  final FlowBarService _flowBarService = FlowBarService();
  final TextInsertionService _textInsertionService = TextInsertionService();
  late final ApiService _apiService;
  late final RealtimeDictateService _realtimeService;
  StreamSubscription<RealtimeDictateEvent>? _realtimeSub;
  final SuggestionsService _suggestionsService = SuggestionsService();
  late final UpdateService _updateService;

  bool _isRecording = false;
  bool _isTranscribing = false;
  /// True when the current recording went through the realtime WS path.
  /// We track it so `_stopAndTranscribe` (batch logic) knows to skip — the
  /// realtime event stream already emitted the final text + inserted it.
  bool _isRealtimeSession = false;
  /// Live running transcript from the realtime path; displayed in FlowBar
  /// while the user is still speaking.
  String _realtimeLiveText = '';

  /// Timestamp of the most recent successful insertion. Drives the Undo
  /// banner in HomeScreen: we only offer Undo while the insertion is fresh
  /// (within `_undoWindow`), because simulating ⌘Z afterwards would
  /// undo whatever the user did in the target app since.
  DateTime? _lastInsertionTimestamp;
  static const Duration _undoWindow = Duration(seconds: 10);
  /// Ticks forward when an insertion happens so widgets watching the undo
  /// state (the HomeScreen banner) can refresh without polling. Not exposed
  /// externally — HomeScreen pulls `canUndoInsertion` from its callback.
  int _insertionCounter = 0;

  // Snippets cache for text expansion
  List<Map<String, dynamic>> _snippets = [];

  StreamSubscription<AudioLevelFrame>? _audioLevelSub;

  static const _channel = MethodChannel('com.voiceassistant/speech');

  @override
  void initState() {
    super.initState();
    _apiService = ApiService(widget.authService);
    _realtimeService = RealtimeDictateService(widget.authService);
    _realtimeSub = _realtimeService.events.listen(_handleRealtimeEvent);
    // Wire the native FlowBar "Undo" tooltip button to the same undo path
    // HomeScreen's in-window banner uses. Both surfaces end up calling
    // `TextInsertionService.undoInsertion()` → simulated ⌘Z.
    _flowBarService.onUndo = () {
      undoLastInsertion();
    };
    _flowBarService.onStopClicked = () {
      if (_isRecording) _stopAndTranscribe();
    };
    _suggestionsService.setApiService(_apiService);
    _channel.setMethodCallHandler(_handleNativeCall);
    _initHotkey();
    _loadSnippets();
    // Fire off the first update check. UpdateService.start() is async
    // but self-contained — we don't await it so a slow network doesn't
    // delay the app landing on Home. The ListenableBuilder wrapping
    // UpdateBanner will rebuild as soon as the first poll resolves.
    _updateService = UpdateService(widget.authService);
    // ignore: discarded_futures
    _updateService.start();
  }

  Future<void> _loadSnippets() async {
    _snippets = await _apiService.getSnippets();
  }

  String _applySnippets(String text) {
    if (_snippets.isEmpty) return text;
    var result = text;
    for (final s in _snippets) {
      final trigger = s['trigger_phrase'] as String? ?? '';
      final expansion = s['expansion'] as String? ?? '';
      if (trigger.isNotEmpty && expansion.isNotEmpty) {
        // Case-insensitive replacement
        result = result.replaceAll(RegExp(RegExp.escape(trigger), caseSensitive: false), expansion);
      }
    }
    return result;
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'navigateTo':
        final target = call.arguments as String?;
        if (target == 'settings') {
          setState(() {
            _selectedNav = NavItem.settings;
            _showAccount = false;
          });
        }
        break;
      case 'selectMicrophone':
        final micId = call.arguments as String?;
        if (micId != null) {
          await StorageService.instance.setSelectedMicId(micId);
        }
        break;
      case 'selectLanguage':
        final lang = call.arguments as String?;
        if (lang != null) {
          await StorageService.instance.setLanguage(lang);
        }
        break;
      case 'selectTranslationMode':
        final mode = call.arguments as String?;
        if (mode != null) {
          await StorageService.instance.setTranslationMode(mode);
        }
        break;
      case 'onSilenceDetected':
        // VAD detected prolonged silence — auto-stop recording
        if (_isRecording) {
          widget.speechService.log('AppShell: silence detected, auto-stopping');
          _stopAndTranscribe();
        }
        break;
      case 'onAudioLevel':
        final args = call.arguments as Map?;
        final level = (args?['level'] as num?)?.toDouble() ?? 0.0;
        final urgency = (args?['urgency'] as num?)?.toDouble() ?? 0.0;
        widget.speechService.pushAudioLevel(level, urgency);
        break;
      case 'onMicDisconnected':
        // Microphone disconnected during recording
        widget.speechService.log('AppShell: mic disconnected');
        _stopAudioLevelForwarding();
        if (_isRecording) {
          await widget.speechService.cancelRecording();
          if (mounted) {
            setState(() {
              _isRecording = false;
              _isTranscribing = false;
            });
          }
          await _flowBarService.updateState(state: 'error', text: 'Mic disconnected');
        }
        if (_isRealtimeSession) {
          await _realtimeService.stop();
        }
        break;
      case 'onAudioFrame':
        // Realtime streaming tap → forward to the realtime service.
        //
        // We route BOTH during `isConnecting` (WS handshake in flight)
        // and `isActive` (post-ready). Forwarding during connect lets
        // RealtimeDictateService queue those frames into its pre-ready
        // buffer so the user's first syllable isn't eaten by the
        // ~600-1000 ms handshake. The service itself decides whether
        // to queue or send-now based on its own state.
        if (_isRealtimeSession &&
            (_realtimeService.isActive || _realtimeService.isConnecting)) {
          final args = call.arguments as Map?;
          final data = args?['data'] as String?;
          if (data != null && data.isNotEmpty) {
            _realtimeService.forwardAudioFrame(data);
          }
        }
        break;
    }
  }

  /// Handle events from the realtime dictation WebSocket session.
  ///
  /// Mirrors the batch flow's UX contract — flip `_isTranscribing`, update
  /// FlowBar state, insert the final text, save to backend. The key
  /// difference is that text is known incrementally: each `partial` updates
  /// the live FlowBar label, and only the `final` commits via
  /// TextInsertionService. If Gemini never fires a `final` (e.g. the WS
  /// errors out), we fall back to the accumulated partial so the user
  /// doesn't lose their dictation.
  Future<void> _handleRealtimeEvent(RealtimeDictateEvent ev) async {
    if (!mounted) return;
    switch (ev) {
      case RealtimeReady():
        widget.speechService.log('AppShell: realtime ready');
        setState(() {
          _isRecording = true;
          _realtimeLiveText = '';
        });
        await _flowBarService.updateState(state: 'listening');
      case RealtimePartial(text: final t):
        // Keep the last partial around so that if Gemini dies before `final`
        // we still have SOMETHING to insert for the user. Also drives the
        // visible transcript in FlowBar.
        setState(() => _realtimeLiveText = t);
        final preview = t.length > 60 ? '…${t.substring(t.length - 60)}' : t;
        await _flowBarService.updateState(state: 'listening', text: preview);
      case RealtimeFinalText(text: final t):
        widget.speechService.log('AppShell: realtime final length=${t.length}');
        await _commitRealtimeTranscript(t);
      case RealtimeUsage(:final audioTokens):
        // Not user-visible for now; structured log for later billing debug.
        widget.speechService.log('AppShell: realtime usage audio_tokens=$audioTokens');
      case RealtimeError(message: final m):
        widget.speechService.log('AppShell: realtime error: $m');
        // If we already have partial text, commit it — the user said the
        // words, we heard them, losing them to a late error is worse than
        // inserting a slightly-short transcript.
        if (_realtimeLiveText.isNotEmpty) {
          await _commitRealtimeTranscript(_realtimeLiveText);
        } else {
          if (mounted) {
            setState(() {
              _isRecording = false;
              _isTranscribing = false;
              _isRealtimeSession = false;
            });
          }
          await _flowBarService.updateState(state: 'error', text: _mapError(m));
        }
    }
  }

  /// Insert the realtime transcript into the focused app and save a
  /// dictation row. Factored out so both the clean `final` path and the
  /// error-salvage path share the same behaviour.
  Future<void> _commitRealtimeTranscript(String text) async {
    final cleaned = text.trim();
    _stopAudioLevelForwarding();
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isTranscribing = false;
      _isRealtimeSession = false;
      _realtimeLiveText = '';
    });

    if (cleaned.isEmpty) {
      await _flowBarService.updateState(state: 'idle');
      return;
    }

    // Apply snippet expansion the same way the batch path does so users
    // get consistent behaviour across modes.
    _loadSnippets();
    final textToInsert = _applySnippets(cleaned);

    _onDictationComplete?.call(textToInsert);

    // Fire-and-forget save — we don't want to block insertion on a
    // round-trip, and the realtime path has no translation metadata yet.
    _apiService.saveDictation(
      text: cleaned,
      language: StorageService.instance.language.isNotEmpty
          ? StorageService.instance.language
          : null,
      wordCount: textToInsert.split(RegExp(r'\s+')).length,
    );

    try {
      final insertResult = await _textInsertionService
          .insertText(textToInsert)
          .timeout(const Duration(seconds: 5));
      if (insertResult.inserted) {
        _markInsertion(textToInsert);
        await _flowBarService.updateState(state: 'done', text: 'Inserted');
      } else {
        await _flowBarService.updateState(state: 'clipboard', text: '⌘V to paste');
      }
    } catch (e) {
      widget.speechService.log('AppShell: realtime insert error: $e');
      await _flowBarService.updateState(state: 'clipboard', text: '⌘V to paste');
    }
  }

  /// Remember this insertion so the HomeScreen's Undo banner can light up
  /// for `_undoWindow` seconds. Called on successful paste from both the
  /// batch and realtime insertion paths. The text argument is kept in the
  /// signature for future surfaces (e.g. "Undo 'hello world…'") but isn't
  /// stored — ⌘Z doesn't need it.
  void _markInsertion(String _) {
    if (!mounted) return;
    setState(() {
      _lastInsertionTimestamp = DateTime.now();
      _insertionCounter++;
    });
  }

  /// Simulate ⌘Z in the frontmost app to revert the most recent insertion,
  /// provided we're still within the 10-second safety window. Outside the
  /// window we refuse: any ⌘Z we fire might undo something the user typed
  /// *after* our insertion, which is a data-loss bug, not an undo.
  Future<bool> undoLastInsertion() async {
    final ts = _lastInsertionTimestamp;
    if (ts == null) return false;
    if (DateTime.now().difference(ts) > _undoWindow) return false;
    final ok = await _textInsertionService.undoInsertion();
    if (!mounted) return ok;
    if (ok) {
      setState(() {
        _lastInsertionTimestamp = null;
        _insertionCounter++;
      });
    }
    return ok;
  }

  /// True when there's an insertion fresh enough to safely undo. HomeScreen
  /// polls this (cheap — just two field reads) to decide whether to render
  /// the Undo banner.
  bool get canUndoInsertion {
    final ts = _lastInsertionTimestamp;
    if (ts == null) return false;
    return DateTime.now().difference(ts) <= _undoWindow;
  }

  Future<void> _initHotkey() async {
    // Restore saved mode (set internal state only, don't start native yet)
    final storage = StorageService.instance;

    // Push the user's silence-timeout preference to the native VAD. Safe to
    // call before any recording starts — Swift just updates the field.
    try {
      await widget.speechService.setSilenceTimeout(storage.silenceTimeoutSeconds);
    } catch (_) {}

    final mode = storage.hotkeyMode;
    switch (mode) {
      case 'hold_ctrl':
        _hotkeyService.restoreMode(HotkeyMode.holdCtrl);
        break;
      case 'double_ctrl':
        _hotkeyService.restoreMode(HotkeyMode.doubleCtrl);
        break;
      case 'custom':
        final code = storage.customHotkeyCode;
        final mods = storage.customHotkeyModifiers;
        final display = storage.customHotkeyDisplay;
        _hotkeyService.restoreCustom(code, mods, display);
        break;
    }

    // Show Flow Bar
    await _flowBarService.show(shortcutLabel: _hotkeyService.displayName);

    // Start listening (single call — uses restored mode)
    await _hotkeyService.start(
      onToggle: _toggleRecording,
      onHoldStart: _startRecording,
      onHoldEnd: () {
        if (_isRecording) _stopAndTranscribe();
      },
      onCancel: _cancelInFlight,
    );
  }

  /// Esc pressed anywhere on the system → abort whatever dictation is
  /// in flight without transcribing / inserting. Covers the recording
  /// window, the post-recording transcribe window, and the realtime
  /// WebSocket session.
  Future<void> _cancelInFlight() async {
    if (!_isRecording && !_isTranscribing && !_isRealtimeSession) return;

    widget.speechService.log('AppShell: Escape pressed, cancelling');
    _stopAudioLevelForwarding();

    if (_isRecording) {
      try {
        await widget.speechService.cancelRecording();
      } catch (_) {}
    }
    if (_isRealtimeSession) {
      try {
        await _realtimeService.stop();
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isTranscribing = false;
      _isRealtimeSession = false;
    });
    await _flowBarService.hide();
  }

  void _startAudioLevelForwarding() {
    _audioLevelSub?.cancel();
    _audioLevelSub = widget.speechService.audioLevelStream.listen((frame) {
      _flowBarService.updateAudioLevel(frame.level, frame.urgency);
    });
  }

  void _stopAudioLevelForwarding() {
    _audioLevelSub?.cancel();
    _audioLevelSub = null;
    _flowBarService.updateAudioLevel(0.0, 0.0);
  }

  void _toggleRecording() {
    if (_isRecording) {
      _stopAndTranscribe();
    } else {
      _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording || _isTranscribing) return;

    // Realtime branch. UX-critical invariant: the user must see the
    // microphone as *already listening* the instant they press the
    // hotkey, with zero "Connecting…" interstitial. The WebSocket
    // handshake and Gemini Live setup (~600-1000 ms) happen in the
    // background while the native Swift tap buffers audio locally;
    // once the session is ready, RealtimeDictateService drains that
    // buffer to the backend.
    //
    // Fallback path on any failure → batch HTTP so a flaky network
    // or an expired JWT can't strand the user mid-hotkey.
    if (StorageService.instance.liveDictationEnabled) {
      final storage = StorageService.instance;
      final lang = storage.language.isNotEmpty ? storage.language : 'ru';

      // Flip visible state and arm the mic IMMEDIATELY — before the
      // WS handshake. No "Connecting" spinner. Frames captured during
      // the handshake window get buffered by RealtimeDictateService
      // and flushed as soon as the backend emits `ready`.
      setState(() {
        _isRealtimeSession = true;
        _isRecording = true;
      });
      await _flowBarService.updateState(state: 'listening');
      _startAudioLevelForwarding();
      if (storage.dictationSounds) widget.speechService.playSound('start');

      // Start the native mic tap now. SpeechRecognizer.swift's
      // startRealtimeRecording attaches a 200 ms PCM16LE @ 16 kHz
      // tap on the input node and begins invoking onAudioFrame
      // immediately. Those frames land in _handleNativeCall, which
      // calls _realtimeService.forwardAudioFrame — which in turn
      // either queues them or sends them to the WS depending on
      // whether the session is ready yet.
      try {
        await const MethodChannel('com.voiceassistant/speech')
            .invokeMethod('startRealtimeRecording');
      } catch (e) {
        widget.speechService.log('AppShell: native mic start failed: $e');
      }

      // Now connect. If it fails we fall through to the batch path
      // and tear down the tap we just armed.
      try {
        await _realtimeService.start(language: lang);
        return;
      } on RealtimeUnavailable catch (e) {
        widget.speechService.log('AppShell: realtime unavailable, fallback: $e');
      } catch (e) {
        widget.speechService.log('AppShell: realtime start error, fallback: $e');
      }
      // Fall through to batch — roll back optimistic state + mic tap.
      try {
        await const MethodChannel('com.voiceassistant/speech')
            .invokeMethod('stopRealtimeRecording');
      } catch (_) {}
      _stopAudioLevelForwarding();
      setState(() {
        _isRealtimeSession = false;
        _isRecording = false;
      });
    }

    // Batch path (unchanged).
    // In hold-to-talk mode, suppress silence auto-stop — the user controls
    // recording duration via hotkey release. In toggle/custom modes the
    // silence detector remains the primary stop trigger.
    if (_hotkeyService.mode == HotkeyMode.holdCtrl) {
      await widget.speechService.setSilenceDetection(false);
    } else {
      await widget.speechService.setSilenceDetection(true);
    }

    final ok = await widget.speechService.startRecording();
    if (!ok) {
      await _flowBarService.updateState(state: 'error', text: 'Mic error');
      return;
    }
    setState(() => _isRecording = true);
    await _flowBarService.updateState(state: 'listening');
    _startAudioLevelForwarding();
    if (StorageService.instance.dictationSounds) {
      widget.speechService.playSound('start');
    }
  }

  Future<void> _stopAndTranscribe() async {
    _stopAudioLevelForwarding();
    // Re-enable silence detection for any future non-hold-to-talk session.
    // The disable is scoped to hold-to-talk recordings only.
    await widget.speechService.setSilenceDetection(true);
    // Realtime session owns its own teardown + final/insert flow via the
    // event stream handler above. Calling stop() kicks off the WS stop
    // message; the `final` event emission handles the rest.
    if (_isRealtimeSession) {
      if (StorageService.instance.dictationSounds) {
        widget.speechService.playSound('stop');
      }
      await _flowBarService.updateState(state: 'transcribing');
      await _realtimeService.stop();
      return;
    }

    // Refresh snippets before applying
    _loadSnippets();

    String? filePath;
    try {
      filePath = await widget.speechService.stopRecording()
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      widget.speechService.log('AppShell: stopRecording error: $e');
    }

    if (mounted) {
      setState(() {
        _isRecording = false;
        _isTranscribing = true;
      });
    }
    await _flowBarService.updateState(state: 'transcribing');
    if (StorageService.instance.dictationSounds) {
      widget.speechService.playSound('stop');
    }

    if (filePath == null) {
      if (mounted) setState(() => _isTranscribing = false);
      await _flowBarService.updateState(state: 'error', text: 'No audio');
      return;
    }

    // Skip very short/silent recordings (< 5KB = likely silence/noise)
    try {
      final fileSize = await File(filePath).length();
      if (fileSize < 5000) {
        if (mounted) setState(() => _isTranscribing = false);
        await _flowBarService.updateState(state: 'idle');
        try { await File(filePath).delete(); } catch (_) {}
        return;
      }
    } catch (_) {}

    try {
      final storage = StorageService.instance;
      final lang = storage.language;
      final translateTo = storage.translationMode == 'auto' ? storage.translateTo : null;
      final style = storage.dictationStyle;

      final result = await widget.speechService.transcribeWithTranslation(
        filePath,
        language: lang.isNotEmpty ? lang : 'ru',
        translateTo: translateTo,
        style: style,
        grammar: storage.grammarCorrection,
      ).timeout(const Duration(seconds: 180));

      widget.speechService.log('AppShell: transcribe done, has_result=${result != null}');
      if (mounted) setState(() => _isTranscribing = false);

      if (result != null) {
        final rawText = result.translatedText ?? result.text;
        final textToInsert = _applySnippets(rawText);
        widget.speechService.log('AppShell: textToInsert_length=${textToInsert.length}');

        if (textToInsert.isEmpty) {
          await _flowBarService.updateState(state: 'idle');
          return;
        }

        widget.speechService.log('AppShell: calling _onDictationComplete...');
        _onDictationComplete?.call(textToInsert);

        // Save to backend
        widget.speechService.log('AppShell: calling saveDictation...');
        _apiService.saveDictation(
          text: result.text,
          language: result.language,
          translatedText: result.translatedText,
          translatedTo: result.translatedTo,
          wordCount: textToInsert.split(RegExp(r'\s+')).length,
          grammarApplied: result.grammarApplied,
        );
        // Remember the most recent provider + latency for the Settings →
        // Privacy → Diagnostics card. In-memory only — nothing is
        // persisted and transcript text never leaves this layer.
        if (result.provider != null && result.provider!.isNotEmpty) {
          StorageService.instance.setLastProvider(result.provider!);
        }

        widget.speechService.log('AppShell: calling insertText...');
        try {
          final insertResult = await _textInsertionService.insertText(textToInsert)
              .timeout(const Duration(seconds: 5));
          widget.speechService.log('AppShell: insertResult=${insertResult.inserted} ${insertResult.reason}');

          if (insertResult.inserted) {
            _markInsertion(textToInsert);
            final label = result.translatedTo != null ? 'Translated' : 'Inserted';
            await _flowBarService.updateState(state: 'done', text: label);
          } else {
            await _flowBarService.updateState(state: 'clipboard', text: '⌘V to paste');
          }
        } catch (e) {
          widget.speechService.log('AppShell: insertText error/timeout: $e');
          await _flowBarService.updateState(state: 'clipboard', text: '⌘V to paste');
        }

        // Show dictionary suggestions via native popup
        if (result.suggestedWords.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 500), () {
            _suggestionsService.showSuggestions(result.suggestedWords);
          });
        }
      } else {
        widget.speechService.log('AppShell: result is null');
        await _flowBarService.updateState(state: 'error', text: 'Not recognized');
      }
    } catch (e) {
      widget.speechService.log('AppShell: _stopAndTranscribe error: $e');
      if (mounted) setState(() => _isTranscribing = false);
      await _flowBarService.updateState(state: 'error', text: _mapError(e.toString()));
    }
  }

  String _mapError(String error) => mapTranscribeError(error);

  // Callback for HomeScreen to receive dictation results
  void Function(String text)? _onDictationComplete;

  @override
  void dispose() {
    _audioLevelSub?.cancel();
    _realtimeSub?.cancel();
    _realtimeService.dispose();
    _updateService.dispose();
    _hotkeyService.dispose();
    super.dispose();
  }

  /// Kick the user into the in-app download dialog for the given
  /// release. Shared between the `UpdateBanner` CTA and any other
  /// surface (Settings → About) that wants the same flow.
  Future<bool> _showUpdateDialog(UpdateInfo info) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDownloadDialog(
        service: _updateService,
        info: info,
      ),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final sidebarWidth = _sidebarCollapsed ? 88.0 : 220.0;
    return SidebarMetrics(
      sidebarWidth: sidebarWidth,
      child: Scaffold(
      body: Row(
        children: [
          // Sidebar: 220 px expanded (labels) or 88 px compact
          // (icon-only). The compact width was bumped from 78 to 88 so
          // the native traffic-lights (pinned at window-x 20/40/60 —
          // rightmost ends at x≈72) sit with a ~12 px visual gap on
          // BOTH sides of the pane, matching the 12 px gap on the
          // left. At 78 px the rightmost light kissed the pane edge
          // (~6 px gap), which read as asymmetric.
          //
          // AnimatedContainer (not AnimatedSize) is required here:
          // AnimatedSize passes *unbounded* constraints to its child,
          // which makes the Sidebar's `Spacer()` try to take infinite
          // height. AnimatedContainer keeps the child's constraints
          // bounded and produces the same smooth width tween.
          AnimatedContainer(
            duration: FlowTokens.durSidebar,
            curve: FlowTokens.easeSidebar,
            width: sidebarWidth,
            child: Sidebar(
              selected: _selectedNav,
              onSelect: (item) {
                setState(() {
                  _selectedNav = item;
                  _showAccount = false;
                  if (item != NavItem.home) {
                    _onDictationComplete = null;
                  }
                });
              },
              userName: widget.authService.userName,
              plan: 'Basic',
              collapsed: _sidebarCollapsed,
              onAccountTap: () {
                setState(() => _showAccount = !_showAccount);
              },
              onCollapse: () => setState(
                () => _sidebarCollapsed = !_sidebarCollapsed,
              ),
            ),
          ),
          Expanded(
            child: ToolbarInset(
              leftInset: 0,
              // Stack lets the floating UpdateBanner sit above the
              // screen content without pushing the layout. The old
              // layout was a Column with a full-width strip at the top,
              // which read as a Material banner — visually loud and
              // not on-brand for a Liquid-Glass shell.
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _showAccount
                        ? AccountScreen(
                            authService: widget.authService,
                            apiService: _apiService,
                            onLogout: widget.onLogout,
                            onClose: () =>
                                setState(() => _showAccount = false),
                          )
                        : _buildContent(),
                  ),
                  // Floating "new version available" pill. Anchors
                  // bottom-center of the content area so it doesn't
                  // collide with the sidebar and scrolls independently
                  // of list position — always on screen until dismissed
                  // or the update is taken.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 24,
                    child: ListenableBuilder(
                      listenable: _updateService,
                      builder: (context, _) {
                        final info = _updateService.available;
                        return IgnorePointer(
                          ignoring: info == null,
                          child: AnimatedSwitcher(
                            duration: FlowTokens.durBase,
                            switchInCurve: FlowTokens.easeStandard,
                            switchOutCurve: FlowTokens.easeStandard,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.3),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: info == null
                                ? const SizedBox.shrink(
                                    key: ValueKey('no-update'))
                                : Padding(
                                    key: ValueKey('update-${info.build}'),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: FlowTokens.space24,
                                    ),
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 540,
                                        ),
                                        child: UpdateBanner(
                                          info: info,
                                          forceUpdate:
                                              _updateService.isForceUpdate,
                                          onUpdate: () =>
                                              _showUpdateDialog(info),
                                          onDismiss:
                                              _updateService.isForceUpdate
                                                  ? null
                                                  : _updateService.dismiss,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildContent() {
    switch (_selectedNav) {
      case NavItem.home:
        return HomeScreen(
          authService: widget.authService,
          speechService: widget.speechService,
          apiService: _apiService,
          isRecording: _isRecording,
          isTranscribing: _isTranscribing,
          onDictationCallback: (cb) => _onDictationComplete = cb,
          canUndoInsertion: () => canUndoInsertion,
          onUndoInsertion: undoLastInsertion,
          insertionTick: _insertionCounter,
        );
      case NavItem.settings:
        return SettingsScreen(
          hotkeyService: _hotkeyService,
          speechService: widget.speechService,
          flowBarService: _flowBarService,
          apiService: _apiService,
          onLogout: widget.onLogout,
        );
      case NavItem.dictionary:
        return DictionaryScreen(apiService: _apiService);
      case NavItem.snippets:
        return SnippetsScreen(apiService: _apiService);
      case NavItem.style:
        return const StyleScreen();
      case NavItem.scratchpad:
        return const ScratchpadScreen();
    }
  }
}

