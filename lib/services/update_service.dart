import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart';
import 'storage_service.dart';

/// Release metadata returned by `GET /api/v1/desktop/latest`. A missing
/// field (e.g. `build: 0`, `notes: ''`) is the expected shape on a fresh
/// deploy where ops hasn't filled in that env var yet — callers cope.
@immutable
class UpdateInfo {
  final String version; // marketing, e.g. "1.0.1"
  final int build;       // monotonic int, primary comparison key
  final String url;      // direct DMG / ZIP download
  final String notes;    // short markdown release notes (may be empty)
  final int minBuild;    // if current build < minBuild, no "Later" action

  const UpdateInfo({
    required this.version,
    required this.build,
    required this.url,
    required this.notes,
    required this.minBuild,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        version: (json['version'] ?? '').toString(),
        build: (json['build'] as num?)?.toInt() ?? 0,
        url: (json['url'] ?? '').toString(),
        notes: (json['notes'] ?? '').toString(),
        minBuild: (json['min_build'] as num?)?.toInt() ?? 0,
      );
}

/// Polls the backend for a newer desktop release and exposes the state
/// as a [ChangeNotifier] so the in-app banner can react.
///
/// Design choices:
///
/// - **Comparison key is the build number** (CFBundleVersion / `+N`),
///   not the semver string. Build numbers are required to strictly
///   increase on every notarized release anyway, and an int compare
///   sidesteps the whole "is 1.10 > 1.9?" semver-parsing rabbit hole.
///
/// - **Cadence** — check once on boot, then every 6 h. Light enough to
///   stay off the hot path; often enough that long-running sessions
///   still see an update within a workday.
///
/// - **Dismissal is sticky per build**. If the user clicks ×, we store
///   that build in SharedPreferences. When a *newer* build lands the
///   banner reappears; the user isn't nagged about the same release.
///
/// - **Force-update support** — `min_build` lets ops declare that a
///   release is mandatory (e.g. security fix). When the local build
///   is strictly below it, the banner hides the dismiss button.
///
/// - **Graceful silence on failure**. Offline / backend down / 204 No
///   Content all clear any pending state and leave no banner, no
///   error toast — an update check isn't critical-path UX.
///
/// - **Web-safe**. `package_info_plus` works on web but the whole flow
///   is macOS-specific (the DMG on the other end isn't useful in a
///   browser), so we skip the whole thing under `kIsWeb`.
class UpdateService extends ChangeNotifier {
  UpdateService(this._auth) {
    // Single-instance assumption: app_shell creates this once after
    // login and holds it for the process lifetime. Static handle lets
    // the native menu bar ("Check for Updates…" in the Flow menu)
    // trigger a probe without having to thread the service down
    // through widget callbacks. If we ever legitimately need multiple
    // instances (multi-account, tests), swap this for a proper
    // InheritedWidget / provider lookup.
    current = this;
  }

  /// Global handle for code paths that can't easily receive the
  /// service via widget tree (PlatformMenuBar callbacks, dock menu,
  /// notification-click handlers). `null` before login / after
  /// dispose — callers must null-check.
  static UpdateService? current;

  final AuthService _auth;
  Timer? _timer;
  UpdateInfo? _available;
  int _currentBuild = 0;
  String _currentVersion = '';
  bool _started = false;

  /// Cadence of the periodic check after the initial boot probe.
  /// 6 h is the sweet spot: long-running sessions pick up same-day
  /// releases without burning battery on a tight poll.
  static const Duration _pollInterval = Duration(hours: 6);

  /// Per-call ceiling on the version-check request. A hung connection
  /// can't block the UI — the banner stays hidden and we'll try again
  /// next tick.
  static const Duration _requestTimeout = Duration(seconds: 10);

  /// Current local build. Exposed for diagnostics surfaces ("running
  /// Flow 1.0.0 (1)") rather than for decision logic; update checks
  /// consult this field internally.
  int get currentBuild => _currentBuild;

  /// Current local marketing version (e.g. "1.0.0").
  String get currentVersion => _currentVersion;

  /// The newest available release if one is ready to prompt about,
  /// else null. Null also covers the "user has already dismissed this
  /// build" and "endpoint returned 204 / nothing configured" cases.
  UpdateInfo? get available => _available;

  /// True iff the backend's `min_build` is strictly greater than the
  /// currently installed build — meaning ops has declared this update
  /// mandatory. Banner UIs should hide the "×" when this is true.
  bool get isForceUpdate {
    final info = _available;
    return info != null && info.minBuild > _currentBuild;
  }

  /// Kick off the first check and start the periodic timer. Safe to
  /// call multiple times — idempotent.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Web build of the app is for UI iteration only — the DMG flow
    // doesn't apply there, so don't even bother probing.
    if (kIsWeb) return;

    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
      _currentBuild = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      // If package_info fails (extremely unlikely on macOS) we keep
      // the zero defaults, which means we'll prompt on any published
      // build. That's acceptable: better to over-prompt than to miss
      // a security update.
    }

    await _check();
    _timer = Timer.periodic(_pollInterval, (_) => _check());
  }

  Future<void> _check() async {
    try {
      final resp = await http
          .get(Uri.parse('${_auth.serverUrl}/api/v1/desktop/latest'))
          .timeout(_requestTimeout);

      // 204 = "nothing configured yet". Clear any stale banner so
      // we don't keep prompting after ops pulled a release.
      if (resp.statusCode == 204) {
        _setAvailable(null);
        return;
      }

      if (resp.statusCode != 200) {
        return; // non-fatal; try again on next tick
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) return;
      final info = UpdateInfo.fromJson(decoded);

      // Nothing worth prompting about — remote build is older than or
      // equal to what's already installed. Also covers the "backend
      // returned version but forgot build" shape (build=0 < any real
      // _currentBuild).
      if (info.build <= _currentBuild) {
        _setAvailable(null);
        return;
      }

      // User tapped × on a release >= this one. Skip, UNLESS this is
      // a force-update (min_build beats the user's preference).
      final dismissed = StorageService.instance.skippedUpdateBuild;
      final isForce = info.minBuild > _currentBuild;
      if (!isForce && dismissed >= info.build) {
        _setAvailable(null);
        return;
      }

      _setAvailable(info);
    } catch (_) {
      // Offline, DNS error, TLS hiccup — all non-fatal. Leave the
      // current banner state (if any) alone and retry on the next
      // tick. The banner was never a "must surface" path.
    }
  }

  void _setAvailable(UpdateInfo? info) {
    final wasSame = (_available == null && info == null) ||
        (_available != null &&
            info != null &&
            _available!.build == info.build);
    if (wasSame) return;
    _available = info;
    notifyListeners();
  }

  /// Open the release asset in the user's default browser. No in-app
  /// install flow on ad-hoc builds: Gatekeeper requires the user to
  /// manually drag the new .app into /Applications anyway, so we let
  /// the native "Downloads → open DMG → drag" flow handle it. Sparkle
  /// will replace this once we're notarized.
  Future<bool> openDownload() async {
    final info = _available;
    if (info == null || info.url.isEmpty) return false;
    final uri = Uri.tryParse(info.url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Hide the banner until a build strictly greater than the current
  /// `available.build` ships. No-op when the prompt is a force-update
  /// — callers guard on [isForceUpdate] but we defence-in-depth here
  /// too so a bad caller can't bypass the policy.
  void dismiss() {
    final info = _available;
    if (info == null) return;
    if (isForceUpdate) return;
    // Fire-and-forget persistence — we don't want to block the UI on
    // SharedPreferences. A brief race where the banner flickers back
    // on a concurrent tick is harmless; the next poll will settle it.
    // ignore: discarded_futures
    StorageService.instance.setSkippedUpdateBuild(info.build);
    _setAvailable(null);
  }

  /// Manual trigger — handy if we ever expose a "Check for updates"
  /// button in Settings. Returns when the probe completes.
  Future<void> checkNow() => _check();

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (identical(current, this)) current = null;
    super.dispose();
  }
}
