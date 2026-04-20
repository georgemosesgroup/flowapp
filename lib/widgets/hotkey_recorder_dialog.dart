import 'package:flutter/material.dart';
import '../services/hotkey_service.dart';

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
    return Dialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Record Shortcut',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              _recording ? 'Hold modifier + press a key' : 'Release to confirm',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 20),

            // Display area
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _ready
                      ? const Color(0xFF4CAF50).withValues(alpha: 0.5)
                      : _display.isNotEmpty
                          ? const Color(0xFFE94560).withValues(alpha: 0.4)
                          : const Color(0xFF374151),
                ),
              ),
              child: Center(
                child: _display.isEmpty
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_recording)
                            const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(color: Color(0xFFE94560), strokeWidth: 2),
                            ),
                          const SizedBox(width: 8),
                          const Text('Waiting for keys...', style: TextStyle(color: Colors.white24, fontSize: 14)),
                        ],
                      )
                    : _buildKeyChips(_display),
              ),
            ),

            if (_ready)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 14),
                    SizedBox(width: 4),
                    Text('Ready to save', style: TextStyle(color: Color(0xFF4CAF50), fontSize: 11)),
                  ],
                ),
              ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFE94560), fontSize: 11)),
              ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Color(0xFF374151)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _retry,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Color(0xFF374151)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Retry', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _ready ? _save : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE94560),
                      disabledBackgroundColor: const Color(0xFF374151),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Save', style: TextStyle(fontSize: 13)),
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('+', style: TextStyle(color: Colors.white38, fontSize: 14)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF374151)),
            ),
            child: Text(
              parts[i],
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ],
    );
  }
}
