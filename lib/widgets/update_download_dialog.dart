import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/update_service.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'flow_button.dart';

/// Modal download-and-install flow for a pending Flow update. Replaces
/// the old "click → opens the DMG URL in browser" path with an in-app
/// experience: streaming progress, cancel, and a finish state that
/// reveals the downloaded installer in Finder.
///
/// Still relies on the user to drag Flow into /Applications themselves.
/// Auto-replace + relaunch is gated on Sparkle (+ a real Developer ID),
/// which is a separate follow-up once we notarize.
///
/// Designed to be called via `showDialog()` — callers get the mounted
/// context and a no-op in return.
class UpdateDownloadDialog extends StatefulWidget {
  final UpdateService service;
  final UpdateInfo info;

  const UpdateDownloadDialog({
    super.key,
    required this.service,
    required this.info,
  });

  @override
  State<UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

enum _Stage { downloading, done, cancelled, failed, quitting }

class _UpdateDownloadDialogState extends State<UpdateDownloadDialog> {
  _Stage _stage = _Stage.downloading;
  int _received = 0;
  int _total = -1;
  String? _downloadedPath;
  final Completer<void> _cancelToken = Completer<void>();

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final path = await widget.service.downloadDmg(
      cancelToken: _cancelToken,
      onProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          _received = received;
          _total = total;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      if (_cancelToken.isCompleted) {
        _stage = _Stage.cancelled;
      } else if (path == null) {
        _stage = _Stage.failed;
      } else {
        _stage = _Stage.done;
        _downloadedPath = path;
      }
    });
  }

  void _cancel() {
    if (!_cancelToken.isCompleted) _cancelToken.complete();
  }

  Future<void> _openInstaller() async {
    final path = _downloadedPath;
    if (path == null) return;
    final ok = await widget.service.revealDmgInFinder(path);
    if (!mounted) return;
    if (!ok) {
      setState(() => _stage = _Stage.failed);
      return;
    }

    // DMG is mounted — macOS won't let the user drag-replace
    // /Applications/Flow.app while our process is still running, so
    // quit cleanly here. A short delay lets Finder come to the front
    // and render the mounted DMG window first; otherwise the user sees
    // Flow close without understanding why and has to hunt for the
    // installer in Downloads.
    setState(() => _stage = _Stage.quitting);
    await Future.delayed(const Duration(milliseconds: 600));

    try {
      await const MethodChannel('com.voiceassistant/window')
          .invokeMethod('quit');
    } on PlatformException {
      // Channel missing (older binaries) — fall through to force exit.
    }
    // Belt-and-braces: if NSApp.terminate was vetoed or the channel
    // handler isn't wired, force-exit so the user isn't stuck with a
    // zombie Flow process blocking the drag-replace.
    await Future.delayed(const Duration(milliseconds: 600));
    exit(0);
  }

  double? get _progressFraction {
    if (_total <= 0) return null;
    final frac = _received / _total;
    return frac.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: FlowTokens.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FlowTokens.radiusLg),
        side: BorderSide(color: FlowTokens.strokeSubtle, width: 0.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, minWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(FlowTokens.space20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(variant: _stage, version: widget.info.version),
              const SizedBox(height: FlowTokens.space16),
              _Body(
                stage: _stage,
                received: _received,
                total: _total,
                fraction: _progressFraction,
              ),
              const SizedBox(height: FlowTokens.space20),
              _Actions(
                stage: _stage,
                onCancel: _cancel,
                onClose: () => Navigator.of(context).pop(),
                onOpen: _openInstaller,
                onRetry: () {
                  setState(() {
                    _stage = _Stage.downloading;
                    _received = 0;
                    _total = -1;
                    _downloadedPath = null;
                  });
                  // ignore: discarded_futures
                  _start();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final _Stage variant;
  final String version;
  const _Header({required this.variant, required this.version});

  @override
  Widget build(BuildContext context) {
    final (icon, color, title) = switch (variant) {
      _Stage.downloading => (
          Icons.download_rounded,
          FlowTokens.systemBlue,
          'Updating Flow',
        ),
      _Stage.done => (
          Icons.check_circle_rounded,
          FlowTokens.systemGreen,
          'Download complete',
        ),
      _Stage.cancelled => (
          Icons.cancel_outlined,
          FlowTokens.textSecondary,
          'Update cancelled',
        ),
      _Stage.failed => (
          Icons.error_outline_rounded,
          FlowTokens.systemRed,
          'Update failed',
        ),
      _Stage.quitting => (
          Icons.power_settings_new_rounded,
          FlowTokens.systemBlue,
          'Quitting Flow',
        ),
    };

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: FlowTokens.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: FlowType.headline),
              const SizedBox(height: 2),
              Text('Flow $version', style: FlowType.caption),
            ],
          ),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  final _Stage stage;
  final int received;
  final int total;
  final double? fraction;

  const _Body({
    required this.stage,
    required this.received,
    required this.total,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    switch (stage) {
      case _Stage.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: FlowTokens.strokeSubtle,
                valueColor: AlwaysStoppedAnimation<Color>(FlowTokens.accent),
              ),
            ),
            const SizedBox(height: FlowTokens.space8),
            Text(
              _progressLine(received, total, fraction),
              style: FlowType.caption,
            ),
          ],
        );
      case _Stage.done:
        return Text(
          'Drag Flow into the Applications folder to finish installing, '
          'then relaunch.',
          style: FlowType.body,
        );
      case _Stage.cancelled:
        return Text(
          'The download was cancelled. You can start again whenever '
          'you\u2019re ready.',
          style: FlowType.body,
        );
      case _Stage.failed:
        return Text(
          'Couldn\u2019t finish the download. Check your connection and '
          'retry, or open the release in your browser to download manually.',
          style: FlowType.body,
        );
      case _Stage.quitting:
        return Text(
          'The installer is open. Flow is closing so you can drop the '
          'new version into your Applications folder.',
          style: FlowType.body,
        );
    }
  }

  static String _progressLine(int received, int total, double? fraction) {
    final got = _formatBytes(received);
    if (total > 0 && fraction != null) {
      final pct = (fraction * 100).round();
      return '$got of ${_formatBytes(total)}  \u00b7  $pct%';
    }
    return '$got downloaded';
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var u = 0;
    while (value >= 1024 && u < units.length - 1) {
      value /= 1024;
      u++;
    }
    final formatted = u <= 1 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '$formatted ${units[u]}';
  }
}

class _Actions extends StatelessWidget {
  final _Stage stage;
  final VoidCallback onCancel;
  final VoidCallback onClose;
  final VoidCallback onOpen;
  final VoidCallback onRetry;

  const _Actions({
    required this.stage,
    required this.onCancel,
    required this.onClose,
    required this.onOpen,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    switch (stage) {
      case _Stage.downloading:
        return Align(
          alignment: Alignment.centerRight,
          child: FlowButton(
            label: 'Cancel',
            variant: FlowButtonVariant.ghost,
            size: FlowButtonSize.md,
            onPressed: onCancel,
          ),
        );
      case _Stage.done:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FlowButton(
              label: 'Close',
              variant: FlowButtonVariant.ghost,
              size: FlowButtonSize.md,
              onPressed: onClose,
            ),
            const SizedBox(width: FlowTokens.space8),
            FlowButton(
              label: 'Open installer',
              variant: FlowButtonVariant.filled,
              size: FlowButtonSize.md,
              onPressed: onOpen,
            ),
          ],
        );
      case _Stage.cancelled:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FlowButton(
              label: 'Close',
              variant: FlowButtonVariant.ghost,
              size: FlowButtonSize.md,
              onPressed: onClose,
            ),
            const SizedBox(width: FlowTokens.space8),
            FlowButton(
              label: 'Retry',
              variant: FlowButtonVariant.filled,
              size: FlowButtonSize.md,
              onPressed: onRetry,
            ),
          ],
        );
      case _Stage.failed:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FlowButton(
              label: 'Close',
              variant: FlowButtonVariant.ghost,
              size: FlowButtonSize.md,
              onPressed: onClose,
            ),
            const SizedBox(width: FlowTokens.space8),
            FlowButton(
              label: 'Retry',
              variant: FlowButtonVariant.filled,
              size: FlowButtonSize.md,
              onPressed: onRetry,
            ),
          ],
        );
      case _Stage.quitting:
        // No actions — process is about to go away. Empty row keeps
        // the dialog's vertical layout stable for the ~0.6 s window
        // between "quitting" and terminate().
        return const SizedBox.shrink();
    }
  }
}
