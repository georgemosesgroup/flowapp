import 'dart:async';
import 'package:flutter/material.dart';
import '../services/speech_service.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/flow_button.dart';
import '../widgets/flow_card.dart';

class PermissionsScreen extends StatefulWidget {
  final VoidCallback onAllGranted;

  const PermissionsScreen({super.key, required this.onAllGranted});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  final SpeechService _speechService = SpeechService();

  PermissionStatus _micStatus = PermissionStatus.notDetermined;
  PermissionStatus _accessStatus = PermissionStatus.notDetermined;
  bool _requesting = false;
  int _currentStep = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    try {
      final state = await _speechService.checkPermissions();
      if (!mounted) return;
      setState(() {
        _micStatus = state.microphone;
        _accessStatus = state.accessibility;
        _updateStep();
      });
      if (state.allGranted) {
        _stopPolling();
        widget.onAllGranted();
        return;
      }
      if (_micStatus == PermissionStatus.granted && _currentStep > 0) {
        _stopPolling();
      }
    } catch (e) {
      debugPrint('Check permissions error: $e');
    }
  }

  void _updateStep() {
    if (_micStatus != PermissionStatus.granted) {
      _currentStep = 0;
    } else if (_accessStatus != PermissionStatus.granted) {
      _currentStep = 1;
    } else {
      _currentStep = 2;
    }
  }

  Future<void> _handleMicrophoneStep() async {
    if (_requesting) return;
    setState(() => _requesting = true);

    if (_micStatus == PermissionStatus.denied) {
      await _speechService.openSystemPreferences('microphone');
      _startPolling();
    } else {
      await _speechService.requestMicrophonePermission();
      await Future.delayed(const Duration(milliseconds: 500));
      await _checkPermissions();
    }
    setState(() => _requesting = false);
  }

  Future<void> _handleAccessibilityStep() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    await _speechService.openAccessibilitySettings();
    _startPolling();
    setState(() => _requesting = false);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _checkPermissions();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: FlowTokens.space24,
            vertical: FlowTokens.space16,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Header(step: _currentStep),
                const SizedBox(height: FlowTokens.space20),
                if (_currentStep == 0) _buildMicrophoneStep(),
                if (_currentStep == 1) _buildAccessibilityStep(),
                if (_currentStep == 2) _buildDoneStep(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMicrophoneStep() {
    final isDenied = _micStatus == PermissionStatus.denied;
    return _StepCard(
      icon: Icons.mic_rounded,
      title: 'Microphone access',
      description: isDenied
          ? 'Access is currently denied. Open System Settings to enable it.'
          : 'Flow records your voice and sends it for AI transcription.',
      instructions: isDenied
          ? const [
              'Click "Open settings"',
              'Find Flow in the list',
              'Toggle the switch on',
              'Return and click "Check"',
            ]
          : const [
              'Click "Allow" below',
              'In the macOS dialog, click "OK"',
            ],
      buttonText: isDenied ? 'Open settings' : 'Allow access',
      buttonIcon: isDenied ? Icons.settings_rounded : Icons.check_rounded,
      onPressed: _requesting ? null : _handleMicrophoneStep,
      showRefresh: isDenied,
      onRefresh: _checkPermissions,
      isLoading: _requesting,
    );
  }

  Widget _buildAccessibilityStep() {
    return Column(
      children: [
        _StepCard(
          icon: Icons.accessibility_new_rounded,
          title: 'Accessibility',
          description:
              'Required to paste transcribed text into any app via ⌘V.',
          instructions: const [
            'Click "Open settings"',
            'Click the lock 🔒 if required',
            'Find Flow and enable it',
            'Return and click "Check"',
          ],
          buttonText: 'Open settings',
          buttonIcon: Icons.settings_rounded,
          onPressed: _requesting ? null : _handleAccessibilityStep,
          showRefresh: true,
          onRefresh: _checkPermissions,
          isLoading: _requesting,
        ),
        const SizedBox(height: FlowTokens.space10),
        FlowButton(
          label: 'Skip for now',
          variant: FlowButtonVariant.ghost,
          size: FlowButtonSize.sm,
          onPressed: widget.onAllGranted,
        ),
      ],
    );
  }

  Widget _buildDoneStep() {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                FlowTokens.systemGreen.withValues(alpha: 0.9),
                FlowTokens.systemGreen.withValues(alpha: 0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(FlowTokens.radiusMd),
            boxShadow: [
              BoxShadow(
                color: FlowTokens.systemGreen.withValues(alpha: 0.32),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 28,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: FlowTokens.space12),
        Text('All set!', style: FlowType.title),
        const SizedBox(height: FlowTokens.space4),
        Text(
          'All permissions granted. Hold ^ Ctrl anywhere to dictate.',
          style: FlowType.caption,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: FlowTokens.space16),
        FlowButton(
          label: 'Get started',
          variant: FlowButtonVariant.filled,
          size: FlowButtonSize.md,
          fullWidth: true,
          onPressed: widget.onAllGranted,
        ),
      ],
    );
  }
}

// ── Header with progress ────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int step;
  const _Header({required this.step});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [FlowTokens.accentHover, FlowTokens.accent],
            ),
            borderRadius: BorderRadius.circular(FlowTokens.radiusMd),
            boxShadow: [
              BoxShadow(
                color: FlowTokens.accent.withValues(alpha: 0.32),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.graphic_eq_rounded,
            size: 24,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: FlowTokens.space12),
        Text(
          'Setup Flow',
          style: FlowType.title.copyWith(fontSize: 19),
        ),
        const SizedBox(height: FlowTokens.space2),
        Text(
          'Step ${step + 1} of 2',
          style: FlowType.footnote,
        ),
        const SizedBox(height: FlowTokens.space10),
        Row(
          children: [
            Expanded(
              child: _ProgressSegment(active: true, complete: step >= 1),
            ),
            const SizedBox(width: FlowTokens.space6),
            Expanded(
              child: _ProgressSegment(active: step >= 1, complete: step >= 2),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProgressSegment extends StatelessWidget {
  final bool active;
  final bool complete;
  const _ProgressSegment({required this.active, required this.complete});

  @override
  Widget build(BuildContext context) {
    final color = complete
        ? FlowTokens.systemGreen
        : active
            ? FlowTokens.accent
            : FlowTokens.bgElevated;
    return AnimatedContainer(
      duration: FlowTokens.durBase,
      height: 4,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// ── Step card ───────────────────────────────────────────────────────

class _StepCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final List<String> instructions;
  final String buttonText;
  final IconData buttonIcon;
  final VoidCallback? onPressed;
  final bool showRefresh;
  final VoidCallback? onRefresh;
  final bool isLoading;

  const _StepCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.instructions,
    required this.buttonText,
    required this.buttonIcon,
    required this.onPressed,
    this.showRefresh = false,
    this.onRefresh,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return FlowCard(
      interactive: false,
      padding: const EdgeInsets.all(FlowTokens.space16),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: FlowTokens.accentSubtle,
                  borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
                ),
                child: Icon(icon, color: FlowTokens.accent, size: 18),
              ),
              const SizedBox(width: FlowTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: FlowType.headline.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: FlowType.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: FlowTokens.space12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              FlowTokens.space12,
              FlowTokens.space10,
              FlowTokens.space12,
              FlowTokens.space10,
            ),
            decoration: BoxDecoration(
              color: FlowTokens.bgPressed,
              borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
              border: Border.all(color: FlowTokens.strokeSubtle, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: instructions.asMap().entries.map((entry) {
                final isLast = entry.key == instructions.length - 1;
                return Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        margin: const EdgeInsets.only(top: 1),
                        decoration: BoxDecoration(
                          color: FlowTokens.accentSubtle,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '${entry.key + 1}',
                            style: FlowType.footnote.copyWith(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: FlowTokens.accent,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: FlowTokens.space8),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: FlowType.body.copyWith(
                            fontSize: 12,
                            height: 1.35,
                            color: FlowTokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: FlowTokens.space12),
          Row(
            children: [
              Expanded(
                child: FlowButton(
                  label: isLoading ? 'Requesting…' : buttonText,
                  leadingIcon: buttonIcon,
                  variant: FlowButtonVariant.filled,
                  size: FlowButtonSize.md,
                  fullWidth: true,
                  onPressed: onPressed,
                ),
              ),
              if (showRefresh) ...[
                const SizedBox(width: FlowTokens.space8),
                FlowButton(
                  label: 'Check',
                  leadingIcon: Icons.refresh_rounded,
                  variant: FlowButtonVariant.ghost,
                  size: FlowButtonSize.md,
                  onPressed: onRefresh,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
