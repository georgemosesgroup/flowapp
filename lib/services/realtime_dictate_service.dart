import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'auth_service.dart';

// ---------------------------------------------------------------------------
// Events emitted by RealtimeDictateService
// ---------------------------------------------------------------------------

sealed class RealtimeDictateEvent {}

/// Gemini Live session is open and ready to accept audio frames.
/// The native mic tap is NOT started until this event fires, so the very
/// first syllables the user utters reach the model.
class RealtimeReady extends RealtimeDictateEvent {}

/// Growing verbatim transcript. Each emission replaces the previous one
/// (the text is cumulative, not a delta).
class RealtimePartial extends RealtimeDictateEvent {
  final String text;
  RealtimePartial(this.text);
}

/// Final snapshot emitted by the backend right before the session closes.
/// Usually equals the last `partial` but the backend also sends this on
/// clean teardown so the client always has one authoritative "it's done"
/// signal.
class RealtimeFinalText extends RealtimeDictateEvent {
  final String text;
  RealtimeFinalText(this.text);
}

/// Server-side fatal error. After emitting this, the service tears down.
class RealtimeError extends RealtimeDictateEvent {
  final String message;
  RealtimeError(this.message);
}

/// Billing telemetry. Emitted once per session near the end.
class RealtimeUsage extends RealtimeDictateEvent {
  final int audioTokens;
  final int textTokens;
  RealtimeUsage({required this.audioTokens, required this.textTokens});
}

// ---------------------------------------------------------------------------
// Exception thrown when the realtime endpoint is unavailable so the caller
// can fall back to batch transcription without having to parse error text.
// ---------------------------------------------------------------------------

class RealtimeUnavailable implements Exception {
  final String message;
  RealtimeUnavailable(this.message);

  @override
  String toString() => 'RealtimeUnavailable: $message';
}

// ---------------------------------------------------------------------------
// RealtimeDictateService — the client half of the live dictation proxy.
//
// Wire protocol (matched exactly against backend/internal/desktop/realtime.go):
//   URL:  {http_base → ws_base}/api/v1/desktop/realtime/dictate?language=…&prompt=…
//   Auth: Authorization: Bearer <jwt>   (WebSocket upgrade header)
//   Client → Server (JSON text frames):
//     {"type":"audio","data":"<base64 PCM16LE 16kHz mono>"}  (~200 ms per frame)
//     {"type":"stop"}
//   Server → Client:
//     {"type":"ready"}
//     {"type":"partial","text":"…"}
//     {"type":"final","text":"…"}
//     {"type":"usage","audio_tokens":N,"text_tokens":N}
//     {"type":"error","error":"…"}
//
// Why a header (not a message) for auth: the backend's JWT middleware
// validates during the HTTP→WS upgrade, BEFORE any frame is exchanged.
// Sending a {"type":"auth"} post-upgrade would be rejected as 401 and the
// connection would never open.
// ---------------------------------------------------------------------------

class RealtimeDictateService {
  /// Channel to the Swift SpeechRecognizer plugin. We use it only to INVOKE
  /// `startRealtimeRecording` / `stopRealtimeRecording` — never to set a
  /// method-call handler. AppShell owns the handler and dispatches
  /// `onAudioFrame` events to us via [forwardAudioFrame], which keeps us
  /// from stomping on the batch SpeechService's callbacks (onSilenceDetected,
  /// onMicDisconnected).
  static const _speechChannel = MethodChannel('com.voiceassistant/speech');

  /// Hard client-side cap to avoid runaway sessions. Backend enforces the
  /// same 5-minute ceiling server-side; having the client enforce it too
  /// means we show a cleaner UX message instead of a silent WS close.
  static const _maxSessionDuration = Duration(minutes: 5);

  final AuthService _auth;

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _sessionTimer;

  final _controller = StreamController<RealtimeDictateEvent>.broadcast();

  /// `_active` flips true after the WS is open AND `ready` has been
  /// received. The mic tap is only armed once we're active, so early-fire
  /// audio can't race ahead of Gemini's setupComplete.
  bool _active = false;

  /// `_connecting` covers the window between `start()` entry and either
  /// success (_active=true) or failure (_teardown). Used to reject double
  /// starts during the WS handshake.
  bool _connecting = false;

  RealtimeDictateService(this._auth);

  // -- Public API -----------------------------------------------------------

  /// Stream of events from the current (or future) realtime session.
  /// Broadcast — safe to subscribe before `start()` is called or during
  /// an active session.
  Stream<RealtimeDictateEvent> get events => _controller.stream;

  /// True between the moment Gemini emits `ready` and the session teardown.
  /// During WS handshake this is false; use `isConnecting` to gate UI.
  bool get isActive => _active;

  /// True during the WS handshake phase (before `ready` lands).
  bool get isConnecting => _connecting;

  /// In-memory pre-ready frame buffer. When AppShell arms the native mic
  /// tap BEFORE `start()` has finished the WS handshake (the optimistic-UI
  /// path), frames start arriving before we can forward them. Queueing
  /// them here means the user's first spoken syllable isn't eaten by the
  /// ~600-1000 ms handshake window — as soon as `ready` lands the queue
  /// is drained to the backend in order.
  ///
  /// Bounded at 50 frames (10 s @ 200 ms/frame) so a stuck handshake
  /// can't blow memory; anything beyond is dropped with a log line. In
  /// practice the queue never grows past ~5 frames.
  final List<String> _preReadyQueue = <String>[];
  static const int _preReadyQueueMax = 50;

  /// Forward a base64-encoded PCM16LE audio frame from the native mic tap
  /// into the open WebSocket session. Called by AppShell's MethodChannel
  /// handler when `onAudioFrame` arrives.
  ///
  /// Behaviour depends on session phase:
  ///   - `_active` = true  → WS is open and Gemini is ready, frame
  ///     flies straight through.
  ///   - `_connecting` = true → handshake in flight, buffer the frame
  ///     so we don't lose the user's first words.
  ///   - neither → no session, drop the frame.
  void forwardAudioFrame(String base64) {
    if (_active) {
      _wsSend({'type': 'audio', 'data': base64});
      return;
    }
    if (_connecting) {
      if (_preReadyQueue.length < _preReadyQueueMax) {
        _preReadyQueue.add(base64);
      } else {
        _debugLog('pre-ready queue full, dropping frame');
      }
    }
  }

  /// Start a realtime dictation session.
  ///
  /// [language] — BCP-47 hint such as "hy", "en", "ru". Passed to the backend
  /// as a query param; influences Gemini's STT language detection.
  /// [dictPrompt] — optional vocabulary hint (e.g. tenant dictionary concat).
  /// The backend propagates this as a `systemInstruction.parts[].text` on
  /// the Gemini setup frame, biasing spelling for proper nouns.
  ///
  /// Throws [RealtimeUnavailable] when the WebSocket cannot be established,
  /// when the microphone can't be opened, or when the JWT is missing. The
  /// UI layer is expected to catch this and fall back to batch transcription
  /// via SpeechService.
  Future<void> start({String? language, String? dictPrompt}) async {
    if (_active || _connecting) return;

    if (!_auth.isLoggedIn) {
      throw RealtimeUnavailable('Not authenticated');
    }

    _connecting = true;

    // Convert http(s) base URL to ws(s) — same host+port, swap scheme only.
    final httpBase = _auth.serverUrl; // e.g. https://api.flow.mosesdev.com
    final wsBase = httpBase
        .replaceFirst(RegExp(r'^https://'), 'wss://')
        .replaceFirst(RegExp(r'^http://'), 'ws://');

    // Language + prompt go on the URL; backend reads them from r.URL.Query().
    final qp = <String, String>{};
    if (language != null && language.trim().isNotEmpty) {
      qp['language'] = language.trim();
    }
    if (dictPrompt != null && dictPrompt.trim().isNotEmpty) {
      // Truncate client-side too — the backend caps the forwarded prompt
      // at ~600 UTF-8 bytes anyway, but sending a 50 KB URL causes nginx
      // 414 errors before the request even reaches the handler.
      final clipped = dictPrompt.trim();
      qp['prompt'] = clipped.length > 500
          ? clipped.substring(0, 500)
          : clipped;
    }
    final wsUrl = Uri.parse('$wsBase/api/v1/desktop/realtime/dictate')
        .replace(queryParameters: qp.isEmpty ? null : qp);

    // We use IOWebSocketChannel to pass the Authorization header during the
    // upgrade handshake. The plain WebSocketChannel.connect() in
    // package:web_socket_channel does NOT accept custom headers on mobile /
    // desktop — it's HTML-only.
    try {
      final raw = await WebSocket.connect(
        wsUrl.toString(),
        headers: {'Authorization': 'Bearer ${_auth.accessToken}'},
      ).timeout(const Duration(seconds: 10));
      _ws = IOWebSocketChannel(raw);
    } on TimeoutException {
      _connecting = false;
      throw RealtimeUnavailable('WebSocket connect timed out');
    } catch (e) {
      _connecting = false;
      throw RealtimeUnavailable('WebSocket connect failed: $e');
    }

    // Listen for server messages before arming the mic, so we can observe
    // `ready` / early errors without racing.
    _wsSub = _ws!.stream.listen(
      _onWsMessage,
      onError: _onWsError,
      onDone: _onWsDone,
    );

    // Enforce the hard cap from the moment the socket opens. Backend will
    // fire a context timeout at 5 min; we want the client-side message a
    // few hundred ms before that so the UI explains what happened.
    _sessionTimer = Timer(
      _maxSessionDuration - const Duration(seconds: 2),
      () {
        _controller.add(
          RealtimeError('Session reached the 5-minute limit'),
        );
        // Fire-and-forget — stop() handles idempotency.
        // ignore: discarded_futures
        stop();
      },
    );
  }

  /// Stop the current realtime dictation session gracefully.
  ///
  /// Order of operations matters:
  ///   1. Halt the native mic tap — prevents more audio frames from queuing.
  ///   2. Send `{"type":"stop"}` — tells the backend to flush Gemini's tail
  ///      and emit a final partial/usage before closing.
  ///   3. Wait briefly for the backend's close; the WS `onDone` callback
  ///      handles the actual teardown.
  /// Idempotent — safe to call from multiple UI events (hotkey release,
  /// window close, account sign-out, etc.).
  Future<void> stop() async {
    if (!_active && !_connecting) return;

    _debugLog('stop() called');
    // Prevent double-teardown races.
    final wasActive = _active;
    _active = false;
    _connecting = false;

    // Stop the mic FIRST so queued frames don't overshoot the stop signal.
    if (wasActive) {
      try {
        await _speechChannel.invokeMethod('stopRealtimeRecording');
      } catch (_) {
        // If the Swift side is already stopped we don't care; stay quiet
        // to avoid noisy teardown logs during hot-reload.
      }
    }

    _wsSend({'type': 'stop'});

    // Safety net. The normal happy path goes: stop → backend flushes
    // Gemini's tail (up to ~5 s when the session was very short and
    // Gemini never emitted a turn) → writes final+usage → closes the
    // WebSocket → `_onWsDone` fires `_teardown()`. Usually 2–4 s.
    //
    // Worst-case backend bound: 5 s stop-grace + 5 s postCtx for
    // writes = 10 s. The safety timer needs to be strictly longer so a
    // legitimate slow flush doesn't get cut off. 20 s gives plenty of
    // slack without stranding the UI forever on a truly wedged backend.
    //
    // If the timer fires, we emit a timeout error event BEFORE calling
    // _teardown so the UI has a signal to un-stick (otherwise the
    // FlowBar stays on "transcribing" forever while the sink silently
    // closes under it).
    Timer(const Duration(seconds: 20), () {
      if (_ws == null) {
        // Already torn down via onDone — nothing to do.
        return;
      }
      _debugLog('safety timer fired — emitting timeout and tearing down');
      _controller.add(RealtimeError('Transcription timeout'));
      _teardown();
    });
  }

  /// Release all resources. Call when disposing the service.
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  // -- Private --------------------------------------------------------------

  void _wsSend(Map<String, dynamic> msg) {
    try {
      _ws?.sink.add(jsonEncode(msg));
    } catch (_) {
      // Sink closed under us — not worth surfacing; teardown path will
      // report the real error if it was fatal.
    }
  }

  /// Append a diagnostic line to the same file SpeechService.log uses
  /// so a single `tail -F ~/flow_debug.log` shows backend+client+native
  /// breadcrumbs interleaved chronologically. Intentionally very noisy
  /// on the realtime path — a stuck session without UI feedback is a
  /// class of bug we can only diagnose from the frame-by-frame log.
  void _debugLog(String line) {
    try {
      final home = Platform.environment['HOME'];
      if (home == null) return;
      final f = File('$home/flow_debug.log');
      f.writeAsStringSync(
        '${DateTime.now()}: Realtime: $line\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // Never throw from a debug helper — a failing log file should
      // not kill an active dictation session.
    }
  }

  void _onWsMessage(dynamic raw) {
    if (raw is! String) {
      _debugLog('WS got non-string frame: ${raw.runtimeType}');
      return;
    }

    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // Backend only emits JSON text frames; malformed input is a backend
      // bug, not something the UI can act on. Drop it silently rather than
      // surfacing a confusing "invalid JSON" to the user.
      _debugLog('WS got non-JSON frame: ${raw.length > 80 ? "${raw.substring(0, 80)}..." : raw}');
      return;
    }

    final type = msg['type'] as String? ?? '';
    // Breadcrumb for debugging when a session looks stuck — we want
    // to know every server frame the client sees, not just the ones
    // that make it past the switch's default branch.
    _debugLog('WS got type=$type keys=${msg.keys.toList()}');

    switch (type) {
      case 'ready':
        // Flip to active phase. AppShell may have already armed the
        // native mic tap for the optimistic-UI path — in that case
        // _preReadyQueue has any frames captured during handshake and
        // we drain them here, in order, so Gemini sees the audio from
        // the moment the hotkey was pressed, not from the moment the
        // WS finished its setup.
        //
        // If AppShell did NOT pre-arm the tap (future callers that
        // still expect the old behaviour), the queue is empty and this
        // is a no-op; the tap is armed below.
        _active = true;
        _connecting = false;
        if (_preReadyQueue.isNotEmpty) {
          _debugLog('draining pre-ready queue: ${_preReadyQueue.length} frames');
          for (final b64 in _preReadyQueue) {
            _wsSend({'type': 'audio', 'data': b64});
          }
          _preReadyQueue.clear();
        }
        // Start the native tap if AppShell hasn't already. Safe to
        // call twice — the Swift side rejects the second call with
        // an error we swallow.
        _speechChannel.invokeMethod('startRealtimeRecording').catchError((e) {
          // If it's already running (optimistic-UI path), this returns
          // a not-recording error we ignore. Only surface a real start
          // failure where the mic genuinely refused.
          final s = e.toString();
          if (!s.contains('already') && !s.contains('Realtime recording')) {
            _controller.add(RealtimeError('Microphone start failed: $e'));
            // ignore: discarded_futures
            stop();
          }
          return null;
        });
        _controller.add(RealtimeReady());
      case 'partial':
        final text = msg['text'] as String? ?? '';
        _controller.add(RealtimePartial(text));
      case 'final':
        final text = msg['text'] as String? ?? '';
        _controller.add(RealtimeFinalText(text));
      case 'error':
        // Backend uses `error` for the human message (see serverMsg struct),
        // not `message`. Fall back to `message` for defence-in-depth.
        final message =
            msg['error'] as String? ?? msg['message'] as String? ?? 'Unknown server error';
        _controller.add(RealtimeError(message));
        // ignore: discarded_futures
        stop();
      case 'usage':
        _controller.add(RealtimeUsage(
          audioTokens: (msg['audio_tokens'] as num?)?.toInt() ?? 0,
          textTokens: (msg['text_tokens'] as num?)?.toInt() ?? 0,
        ));
      default:
        // Ignore unrecognised types for forward compat — we may add fields
        // like `latency_ms` or `speaker_change` server-side later.
        break;
    }
  }

  void _onWsError(Object error) {
    _debugLog('WS onError: $error');
    _controller.add(RealtimeError('WebSocket error: $error'));
    _teardown();
  }

  void _onWsDone() {
    _debugLog('WS onDone (active=$_active connecting=$_connecting)');
    // Server or network closed the connection. If we were still active
    // this is unexpected — surface it; if we were already tearing down
    // (stop() was called) this is the happy path and we stay quiet.
    if (_active || _connecting) {
      _controller.add(RealtimeError('Connection closed'));
    }
    _teardown();
  }

  void _teardown() {
    _active = false;
    _connecting = false;

    _sessionTimer?.cancel();
    _sessionTimer = null;

    // We do NOT setMethodCallHandler here — AppShell owns the shared
    // speech channel and its handler stays installed for the batch path.
    // Audio frames will simply be ignored by forwardAudioFrame() once
    // _active flips false, above.

    // Fire-and-forget: we don't await either close, because at teardown
    // nobody is waiting for the result and we don't want to block the
    // caller of stop() behind a dead socket.
    // ignore: discarded_futures
    _wsSub?.cancel();
    _wsSub = null;
    try {
      _ws?.sink.close();
    } catch (_) {}
    _ws = null;

    // Best-effort mic stop — if startRealtimeRecording failed we still
    // want to make sure the tap isn't left running.
    _speechChannel.invokeMethod('stopRealtimeRecording').catchError((_) => null);
  }
}
