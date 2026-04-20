import 'package:flutter/material.dart';
import '../services/hotkey_service.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'flow_button.dart';

class HotkeyRecorderDialog extends StatefulWidget {
  final HotkeyService hotkeyService;

  const HotkeyRecorderDialog({super.key, required this.hotkeyService});

  @override
  State<HotkeyRecorderDialog> createState() => _HotkeyRecorderDialogState();
}

class _HotkeyRecorderDialogState extends State<HotkeyRecorderDialog> {
  String _display = '';
  int _keyCode = 0;
  int _modifiers = 0;
  bool _ready = false;
  String? _error;
  bool _recording = true;

  @override
  void initState() {
    super.initState();
    _startRecording();
  }

  void _startRecording() {
    setState(() {
      _display = '';
      _keyCode = 0;
      _modifiers = 0;
      _ready = false;
      _error = null;
      _recording = true;
    });

    widget.hotkeyService.startRecording(
      onRecorded: (display, keyCode, modifiers) {
        if (!mounted) return;
        setState(() {
          _display = display;
          _keyCode = keyCode;
          _modifiers = modifiers;
          _ready = true;
          _recording = false;
        });
      },
      onUpdate: (display) {
        if (!mounted) return;
        setState(() {
          _display = display;
          _ready = false;
        });
      },
    );
  }

  @override
  void dispose() {
    if (_recording) widget.hotkeyService.stopRecording();
    super.dispose();
  }

  void _save() {
    if (!_ready) return;
    if (_keyCode == 0) {
      setState(() => _error = 'Need modifier + regular key');
      return;
    }
    Navigator.of(context).pop({
      'display': _display,
      'keyCode': _keyCode,
      'modifiers': _modifiers,
    });
  }

  void _retry() {
    widget.hotkeyService.stopRecording();
    _startRecording();
  }

  @override
  Widget build(BuildContext context) {
    // Display-area state: idle (empty) → recording (in progress) →
    // ready (captured). Border tint follows state: accent while
    // recording, green once ready, subtle stroke when idle.
    final displayBorder = _ready
        ? FlowTokens.systemGreen.withValues(alpha: 0.5)
        : _display.isNotEmpty
            ? FlowTokens.accent.withValues(alpha: 0.4)
            : FlowTokens.strokeDivider;

    return Dialog(
      backgroundColor: FlowTokens.bgElevatedOpaque,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FlowTokens.radiusLg),
        side: BorderSide(color: FlowTokens.strokeSubtle, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(FlowTokens.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Record Shortcut',
              style: FlowType.title.copyWith(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _recording ? 'Hold modifier + press a key' : 'Release to confirm',
              style: FlowType.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FlowTokens.space20),

            // Display area — recessed surface with state-tinted border.
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                color: FlowTokens.bgPressed,
                borderRadius: BorderRadius.circular(FlowTokens.radiusMd),
                border: Border.all(color: displayBorder, width: 1.0),
              ),
              child: Center(
                child: _display.isEmpty
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_recording)
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                color: FlowTokens.accent,
                                strokeWidth: 2,
                              ),
                            ),
                          const SizedBox(width: 8),
                          Text(
                            'Waiting for keys…',
                            style: FlowType.body.copyWith(
                              fontSize: 14,
                              color: FlowTokens.textTertiary,
                            ),
                          ),
                        ],
                      )
                    : _buildKeyChips(_display),
              ),
            ),

            if (_ready)
              Padding(
                padding: const EdgeInsets.only(top: FlowTokens.space8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: FlowTokens.systemGreen,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Ready to save',
                      style: FlowType.footnote.copyWith(
                        color: FlowTokens.systemGreen,
                      ),
                    ),
                  ],
                ),
              ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: FlowTokens.space8),
                child: Text(
                  _error!,
                  style: FlowType.footnote.copyWith(
                    color: FlowTokens.systemRed,
                  ),
                ),
              ),

            const SizedBox(height: FlowTokens.space20),

            Row(
              children: [
                Expanded(
                  child: FlowButton(
                    label: 'Cancel',
                    variant: FlowButtonVariant.tinted,
                    size: FlowButtonSize.md,
                    fullWidth: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: FlowTokens.space8),
                Expanded(
                  child: FlowButton(
                    label: 'Retry',
                    variant: FlowButtonVariant.tinted,
                    size: FlowButtonSize.md,
                    fullWidth: true,
                    onPressed: _retry,
                  ),
                ),
                const SizedBox(width: FlowTokens.space8),
                Expanded(
                  child: FlowButton(
                    label: 'Save',
                    variant: FlowButtonVariant.filled,
                    size: FlowButtonSize.md,
                    fullWidth: true,
                    onPressed: _ready ? _save : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyChips(String display) {
    final parts = display.split(' + ');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < parts.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '+',
                style: FlowType.body.copyWith(
                  fontSize: 14,
                  color: FlowTokens.textTertiary,
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: FlowTokens.space12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: FlowTokens.bgElevated,
              borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
              border: Border.all(color: FlowTokens.strokeSubtle, width: 0.5),
            ),
            child: Text(
              parts[i],
              style: FlowType.bodyStrong.copyWith(
                fontSize: 15,
                color: FlowTokens.textPrimary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
