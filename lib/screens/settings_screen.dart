import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/hotkey_service.dart';
import '../services/storage_service.dart';
import '../services/speech_service.dart';
import '../services/flow_bar_service.dart';
import '../services/update_service.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/flow_button.dart';
import '../widgets/flow_card.dart';
import '../widgets/flow_section.dart';
import '../widgets/flow_segmented_control.dart';
import '../widgets/flow_toast.dart';
import '../widgets/hotkey_recorder_dialog.dart';
import '../widgets/toolbar_inset.dart';
import '../widgets/update_download_dialog.dart';

class SettingsScreen extends StatefulWidget {
  final HotkeyService? hotkeyService;
  final SpeechService? speechService;
  final FlowBarService? flowBarService;
  final ApiService? apiService;
  final VoidCallback? onLogout;

  const SettingsScreen({
    super.key,
    this.hotkeyService,
    this.speechService,
    this.flowBarService,
    this.apiService,
    this.onLogout,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedTab = 'general';
  late StorageService _storage;
  List<Map<String, String>> _microphones = [];
  String _selectedMic = 'default';

  @override
  void initState() {
    super.initState();
    _storage = StorageService.instance;
    _selectedMic = _storage.selectedMicId;
    _loadMicrophones();
  }

  void _showSaved() {
    FlowToast.success(
      context,
      'Saved',
      duration: const Duration(milliseconds: 1000),
    );
  }

  Future<void> _loadMicrophones() async {
    final mics = await widget.speechService?.listMicrophones() ?? [];
    if (mounted) {
      final seen = <String>{};
      final unique = mics.where((m) => seen.add(m['id'] ?? '')).toList();
      setState(() {
        _microphones = unique;
        if (_selectedMic.isEmpty || !unique.any((m) => m['id'] == _selectedMic)) {
          // Prefer the system-default input (Swift marked it with
          // isDefault=true and floated it to the top). Falls back to
          // the first entry only when no device identifies itself as
          // the default — rare, but happens on headless machines.
          final defaultMic = unique.firstWhere(
            (m) => m['isDefault'] == 'true',
            orElse: () => unique.isNotEmpty ? unique.first : const {},
          );
          _selectedMic = defaultMic['id'] ?? 'default';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final leftInset = ToolbarInset.leftOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            FlowTokens.space20 + leftInset,
            FlowTokens.space12,
            FlowTokens.space20,
            FlowTokens.space12,
          ),
          child: Row(
            children: [
              Text('Settings', style: FlowType.title),
              const SizedBox(width: FlowTokens.space16),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FlowSegmentedControl<String>(
                    selected: _selectedTab,
                    segments: const [
                      FlowSegment(value: 'general', label: 'General'),
                      FlowSegment(value: 'system', label: 'System'),
                      FlowSegment(value: 'privacy', label: 'Privacy'),
                    ],
                    onChanged: (t) => setState(() => _selectedTab = t),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              vertical: FlowTokens.space20,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FlowTokens.space24,
                  ),
                  child: _selectedTab == 'general'
                      ? _buildGeneral()
                      : _selectedTab == 'system'
                          ? _buildSystem()
                          : _buildPrivacy(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── General ─────────────────────────────────────────────

  Widget _buildGeneral() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlowSection(
          title: 'Appearance',
          rows: const [_AppearanceRow()],
        ),
        const SizedBox(height: FlowTokens.space24),
        FlowSection(
          title: 'Shortcut',
          footer: 'Hold-to-talk disables silence auto-stop while the key is pressed.',
          rows: [
            _HotkeyRadioRow(
              title: 'Hold ^ Ctrl',
              subtitle: 'Push-to-talk — record while pressed',
              isSelected: widget.hotkeyService?.mode == HotkeyMode.holdCtrl,
              onTap: () {
                widget.hotkeyService?.setMode(HotkeyMode.holdCtrl);
                _storage.setHotkeyMode('hold_ctrl');
                setState(() {});
              },
            ),
            _HotkeyRadioRow(
              title: 'Custom',
              subtitle: _storage.customHotkeyDisplay.isNotEmpty
                  ? _storage.customHotkeyDisplay
                  : 'Click to record your own shortcut',
              isSelected: widget.hotkeyService?.mode == HotkeyMode.custom,
              onTap: () async {
                if (widget.hotkeyService == null) return;
                final result = await showDialog<Map<String, dynamic>>(
                  context: context,
                  // Same scrim the rest of the app's dialogs use
                  // (see `FlowDialog` / `showFlowDialog`) — matches
                  // the lighter "dimmed translucent" backdrop instead
                  // of Flutter's default `Colors.black54`, which was
                  // reading darker than other modals in the app.
                  barrierColor: FlowTokens.scrim,
                  builder: (_) => HotkeyRecorderDialog(
                    hotkeyService: widget.hotkeyService!,
                  ),
                );
                if (result != null && mounted) {
                  final display = result['display'] as String;
                  final keyCode = result['keyCode'] as int;
                  final modifiers = result['modifiers'] as int;
                  _storage.setCustomHotkey(display, keyCode, modifiers);
                  _storage.setHotkeyMode('custom');
                  widget.hotkeyService?.setCustomHotkey(keyCode, modifiers, display);
                  setState(() {});
                  if (mounted) {
                    FlowToast.success(context, 'Shortcut saved: $display');
                  }
                }
              },
            ),
          ],
        ),
        const SizedBox(height: FlowTokens.space24),

        FlowSection(
          title: 'Dictation',
          rows: [
            _SilenceTimeoutRow(
              value: _storage.silenceTimeoutSeconds,
              onChanged: (v) async {
                await _storage.setSilenceTimeoutSeconds(v);
                await widget.speechService?.setSilenceTimeout(v);
                if (mounted) setState(() {});
              },
              onChangeEnd: (_) => _showSaved(),
            ),
          ],
        ),
        const SizedBox(height: FlowTokens.space24),

        FlowSection(
          title: 'Language',
          rows: [
            _LanguageRow(
              selected: _storage.language,
              onChanged: (lang) {
                _storage.setLanguage(lang);
                setState(() {});
                _showSaved();
              },
            ),
          ],
        ),
        const SizedBox(height: FlowTokens.space24),

        FlowSection(
          title: 'Translation',
          rows: [
            // Keys are load-bearing — when `translationMode` flips to
            // "auto" we inject a `_LanguageRow` between Auto-translate
            // and Voice trigger, which shifts the position of Voice
            // trigger in the column. Without a key, Flutter matches
            // rows by (position, type) and accidentally reuses one
            // row's State (including its `_hover` flag) for a
            // different row — that's the "second row flickers on
            // hover" bug.
            _HotkeyRadioRow(
              key: const ValueKey('translation:off'),
              title: 'Off',
              subtitle: 'Dictate as-is, no translation',
              isSelected: _storage.translationMode == 'off',
              onTap: () {
                _storage.setTranslationMode('off');
                setState(() {});
                _showSaved();
              },
            ),
            _HotkeyRadioRow(
              key: const ValueKey('translation:auto'),
              title: 'Auto-translate',
              subtitle: 'Always translate to the target language',
              isSelected: _storage.translationMode == 'auto',
              onTap: () {
                _storage.setTranslationMode('auto');
                setState(() {});
                _showSaved();
              },
            ),
            if (_storage.translationMode == 'auto')
              _LanguageRow(
                key: const ValueKey('translation:auto:lang'),
                selected: _storage.translateTo,
                onChanged: (lang) {
                  if (lang.isEmpty) return;
                  _storage.setTranslateTo(lang);
                  setState(() {});
                  _showSaved();
                },
              ),
            _HotkeyRadioRow(
              key: const ValueKey('translation:voice_trigger'),
              title: 'Voice trigger',
              subtitle:
                  'Say "Translate to English" or "Переведи на русский"',
              isSelected: _storage.translationMode == 'voice_trigger',
              onTap: () {
                _storage.setTranslationMode('voice_trigger');
                setState(() {});
                _showSaved();
              },
            ),
          ],
        ),
        if (_storage.translationMode == 'voice_trigger') ...[
          const SizedBox(height: FlowTokens.space12),
          _VoiceTriggerHint(),
        ],
        const SizedBox(height: FlowTokens.space24),

        FlowSection(
          title: 'Microphone',
          footer: 'The device Flow uses when listening.',
          rows: [
            _MicrophoneRow(
              microphones: _microphones,
              selected: _selectedMic,
              onSelect: (id) {
                setState(() => _selectedMic = id);
                _storage.setSelectedMicId(id);
                _showSaved();
              },
            ),
          ],
        ),
        const SizedBox(height: FlowTokens.space24),

        const _AboutSection(),
      ],
    );
  }

  // ── System ──────────────────────────────────────────────

  Widget _buildSystem() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlowSection(
          title: 'Application',
          rows: [
            _toggleRow(
              icon: Icons.rocket_launch_rounded,
              iconBg: FlowTokens.systemBlue,
              title: 'Launch at login',
              subtitle: 'Open Flow automatically when your Mac starts',
              value: _storage.launchAtLogin,
              onChanged: (v) {
                _storage.setLaunchAtLogin(v);
                widget.speechService?.setLaunchAtLogin(v);
                setState(() {});
                _showSaved();
              },
            ),
            _toggleRow(
              icon: Icons.graphic_eq_rounded,
              iconBg: FlowTokens.accent,
              title: 'Always show Flow bar',
              subtitle: 'Keep the floating dictation bar visible',
              value: _storage.showFlowBar,
              onChanged: (v) {
                _storage.setShowFlowBar(v);
                if (v) {
                  widget.flowBarService?.show();
                } else {
                  widget.flowBarService?.hide();
                }
                setState(() {});
                _showSaved();
              },
            ),
            _toggleRow(
              icon: Icons.tips_and_updates_rounded,
              iconBg: FlowTokens.systemOrange,
              title: 'Dictation reminder',
              subtitle: 'Occasionally remind you of the shortcut',
              value: _storage.dictationReminder,
              onChanged: (v) {
                _storage.setDictationReminder(v);
                setState(() {});
                _showSaved();
              },
            ),
            _toggleRow(
              icon: Icons.desktop_mac_rounded,
              iconBg: FlowTokens.textTertiary,
              title: 'Show in Dock',
              subtitle: 'Display the Flow icon in the macOS Dock',
              value: _storage.showInDock,
              onChanged: (v) {
                _storage.setShowInDock(v);
                widget.speechService?.setDockVisibility(v);
                setState(() {});
                _showSaved();
              },
            ),
          ],
        ),
        const SizedBox(height: FlowTokens.space24),

        FlowSection(
          title: 'Sound',
          rows: [
            _toggleRow(
              icon: Icons.volume_up_rounded,
              iconBg: FlowTokens.systemGreen,
              title: 'Dictation sounds',
              subtitle: 'Play a chime when recording starts or stops',
              value: _storage.dictationSounds,
              onChanged: (v) {
                _storage.setDictationSounds(v);
                if (v) widget.speechService?.playSound('start');
                setState(() {});
                _showSaved();
              },
            ),
            _toggleRow(
              icon: Icons.music_off_rounded,
              iconBg: FlowTokens.textTertiary,
              title: 'Mute music while dictating',
              subtitle: 'Lower system media playback during dictation',
              value: _storage.muteMusicWhileDictating,
              onChanged: (v) {
                _storage.setMuteMusicWhileDictating(v);
                setState(() {});
                _showSaved();
              },
            ),
          ],
        ),
        const SizedBox(height: FlowTokens.space24),

        FlowSection(
          title: 'Intelligence',
          rows: [
            _toggleRow(
              icon: Icons.book_rounded,
              iconBg: FlowTokens.systemBlue,
              title: 'Auto-add to dictionary',
              subtitle: 'Automatically save corrected words',
              value: _storage.autoAddToDictionary,
              onChanged: (v) {
                _storage.setAutoAddToDictionary(v);
                setState(() {});
                _showSaved();
              },
            ),
            _toggleRow(
              icon: Icons.auto_fix_high_rounded,
              iconBg: FlowTokens.accent,
              title: 'Smart formatting',
              subtitle: 'Apply punctuation and capitalization automatically',
              value: _storage.smartFormatting,
              onChanged: (v) {
                _storage.setSmartFormatting(v);
                setState(() {});
                _showSaved();
              },
            ),
            _toggleRow(
              icon: Icons.spellcheck_rounded,
              iconBg: FlowTokens.systemOrange,
              title: 'Grammar correction',
              subtitle: 'Fix word endings, punctuation and typos',
              value: _storage.grammarCorrection,
              onChanged: (v) {
                _storage.setGrammarCorrection(v);
                setState(() {});
                _showSaved();
              },
            ),
            _toggleRow(
              icon: Icons.broadcast_on_personal_rounded,
              iconBg: FlowTokens.systemGreen,
              title: 'Live dictation',
              subtitle: 'Stream text as you speak (via Gemini Live)',
              value: _storage.liveDictationEnabled,
              onChanged: (v) {
                _storage.setLiveDictationEnabled(v);
                setState(() {});
                _showSaved();
              },
            ),
          ],
        ),
      ],
    );
  }

  // ── Privacy ─────────────────────────────────────────────

  Widget _buildPrivacy() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlowSection(
          title: 'Data & Privacy',
          rows: [
            FlowSettingRow(
              leadingIcon: Icons.shield_rounded,
              leadingIconBackground: FlowTokens.systemGreen,
              title: 'Privacy Mode',
              subtitle: 'Zero data retention for dictation data',
              trailing: const Icon(
                Icons.check_circle_rounded,
                color: FlowTokens.systemGreen,
                size: 20,
              ),
            ),
            FlowSettingRow(
              leadingIcon: Icons.model_training_rounded,
              leadingIconBackground: FlowTokens.systemBlue,
              title: 'Help improve the model',
              subtitle:
                  'Dictation audio kept 30 days, corrections up to 180 days. Off by default.',
              trailing: Switch(
                value: _storage.helpImproveModel,
                onChanged: (v) async {
                  await _storage.setHelpImproveModel(v);
                  if (mounted) setState(() {});
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: FlowTokens.space24),

        FlowSection(
          title: 'Actions',
          rows: [
            FlowSettingRow(
              leadingIcon: Icons.delete_outline_rounded,
              leadingIconBackground: FlowTokens.systemOrange,
              title: 'Delete history',
              subtitle: 'Remove all saved dictations',
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: FlowTokens.textTertiary,
                size: 18,
              ),
              onTap: () => _confirmAction(
                title: 'Delete all dictation history?',
                body:
                    'This will permanently remove every dictation from the server. This cannot be undone.',
                confirmLabel: 'Delete',
                destructive: true,
                onConfirm: () async {
                  // Actually call the backend — the previous revision
                  // only flashed a "History deleted" snackbar without
                  // touching the server, which was a silent data-loss
                  // lie. On failure we keep the user informed so they
                  // can retry rather than assume their data is gone.
                  final api = widget.apiService;
                  if (api == null) {
                    if (!mounted) return;
                    FlowToast.error(context, 'Unavailable offline');
                    return;
                  }
                  final ok = await api.deleteAllDictations();
                  if (!mounted) return;
                  if (ok) {
                    FlowToast.success(context, 'History deleted');
                  } else {
                    FlowToast.error(context, 'Delete failed — try again');
                  }
                },
              ),
            ),
            FlowSettingRow(
              leadingIcon: Icons.restart_alt_rounded,
              leadingIconBackground: FlowTokens.systemRed,
              title: 'Reset app',
              subtitle: 'Sign out and clear local preferences',
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: FlowTokens.textTertiary,
                size: 18,
              ),
              onTap: () => _confirmAction(
                title: 'Reset all settings and sign out?',
                body:
                    'Your local preferences will be cleared and you will be signed out. Your dictations on the server are not deleted.',
                confirmLabel: 'Reset',
                destructive: true,
                onConfirm: () async {
                  await _storage.resetAll();
                  widget.onLogout?.call();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: FlowTokens.space24),

        _DiagnosticsCard(
          storage: _storage,
          backendConnected: widget.speechService != null,
          onCopy: () {
            // Assemble a human-readable payload for bug reports. All
            // fields are config/metadata — no transcript content, no
            // tokens, no email — so it is safe to paste into a support
            // channel.
            final diag = [
              'App: Flow Desktop v1.0.0',
              'Language: ${_storage.language.isEmpty ? "auto" : _storage.language}',
              'Grammar: ${_storage.grammarCorrection ? "on" : "off"}',
              'Translation: ${_storage.translationMode}',
              'Hotkey: ${_storage.hotkeyMode}',
              'Mic: ${_storage.selectedMicId.isNotEmpty ? _storage.selectedMicId : "default"}',
              'Live dictation: ${_storage.liveDictationEnabled ? "on" : "off"}',
              if (_storage.lastProvider.isNotEmpty)
                'Last provider: ${_storage.lastProvider}',
            ].join('\n');
            Clipboard.setData(ClipboardData(text: diag));
            FlowToast.success(context, 'Diagnostics copied');
          },
        ),
      ],
    );
  }

  // ── Helpers ─────────────────────────────────────────────

  FlowSettingRow _toggleRow({
    required IconData icon,
    required Color iconBg,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return FlowSettingRow(
      leadingIcon: icon,
      leadingIconBackground: iconBg,
      title: title,
      subtitle: subtitle,
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }

  Future<void> _confirmAction({
    required String title,
    required String body,
    required String confirmLabel,
    required VoidCallback onConfirm,
    bool destructive = false,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: FlowType.headline),
        content: Text(body, style: FlowType.body),
        actions: [
          FlowButton(
            label: 'Cancel',
            variant: FlowButtonVariant.ghost,
            size: FlowButtonSize.md,
            onPressed: () => Navigator.pop(ctx),
          ),
          FlowButton(
            label: confirmLabel,
            variant: destructive
                ? FlowButtonVariant.destructive
                : FlowButtonVariant.filled,
            size: FlowButtonSize.md,
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
          ),
        ],
      ),
    );
  }
}

// ── Segmented tabs (Apple-style pill segmented control) ─────

// ── Radio-style selectable row ──────────────────────────────

class _HotkeyRadioRow extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _HotkeyRadioRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_HotkeyRadioRow> createState() => _HotkeyRadioRowState();
}

class _HotkeyRadioRowState extends State<_HotkeyRadioRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isSel = widget.isSelected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        // Plain Container, NOT AnimatedContainer: the hover background
        // must flip instantly when the cursor crosses a row boundary.
        // With a fade-in/out it's possible for two adjacent rows to be
        // simultaneously mid-animation during a fast mouse transit —
        // which reads as "both highlighted" flicker. Instant swap =
        // zero overlap window.
        child: Container(
          color: _hover ? FlowTokens.bgElevatedHover : Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: FlowTokens.space16,
            vertical: FlowTokens.space12,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: FlowTokens.durFast,
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: isSel ? FlowTokens.accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSel
                        ? FlowTokens.accent
                        : FlowTokens.strokeDivider,
                    width: isSel ? 2 : 1.2,
                  ),
                ),
                child: isSel
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: FlowTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.title, style: FlowType.body),
                    const SizedBox(height: 2),
                    Text(widget.subtitle, style: FlowType.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Silence timeout slider row ──────────────────────────────

class _SilenceTimeoutRow extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SilenceTimeoutRow({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FlowTokens.space16,
        vertical: FlowTokens.space12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Silence auto-stop', style: FlowType.body),
                    const SizedBox(height: 2),
                    Text(
                      'Hold-to-talk ignores this; applies to toggle/custom modes.',
                      style: FlowType.caption,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: FlowTokens.space8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: FlowTokens.accentSubtle,
                  borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
                ),
                child: Text(
                  '${value.toStringAsFixed(1)} s',
                  style: FlowType.mono.copyWith(
                    fontSize: 12,
                    color: FlowTokens.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: FlowTokens.space4),
          Slider(
            min: 0.5,
            max: 5.0,
            divisions: 45,
            value: value.clamp(0.5, 5.0),
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}

// ── Language selector row ───────────────────────────────────

class _LanguageRow extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _LanguageRow({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static const _languages = [
    ('ru', 'Русский'),
    ('en', 'English'),
    ('uk', 'Українська'),
    ('de', 'Deutsch'),
    ('fr', 'Français'),
    ('es', 'Español'),
    ('it', 'Italiano'),
    ('pt', 'Português'),
    ('pl', 'Polski'),
    ('nl', 'Nederlands'),
    ('tr', 'Türkçe'),
    ('ar', 'العربية'),
    ('zh', '中文'),
    ('ja', '日本語'),
    ('ko', '한국어'),
    ('hi', 'हिन्दी'),
    ('hy', 'Հայերեն'),
    ('ka', 'ქართული'),
    ('he', 'עברית'),
    ('sv', 'Svenska'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(FlowTokens.space12),
      child: Wrap(
        spacing: FlowTokens.space6,
        runSpacing: FlowTokens.space6,
        children: _languages.map((l) {
          final isActive = selected == l.$1;
          return _LangChip(
            label: l.$2,
            isActive: isActive,
            onTap: () => onChanged(l.$1),
          );
        }).toList(),
      ),
    );
  }
}

class _LangChip extends StatefulWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const _LangChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_LangChip> createState() => _LangChipState();
}

class _LangChipState extends State<_LangChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isSel = widget.isActive;
    final bg = isSel
        ? FlowTokens.accentSubtle
        : _hover
            ? FlowTokens.bgElevatedHover
            : FlowTokens.bgSurface;
    final fg = isSel ? FlowTokens.accent : FlowTokens.textSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: FlowTokens.durFast,
          padding: const EdgeInsets.symmetric(
            horizontal: FlowTokens.space10,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(FlowTokens.radiusFull),
            border: Border.all(
              color: isSel
                  ? FlowTokens.accent.withValues(alpha: 0.4)
                  : FlowTokens.strokeSubtle,
              width: 0.5,
            ),
          ),
          child: Text(
            widget.label,
            style: FlowType.footnote.copyWith(color: fg),
          ),
        ),
      ),
    );
  }
}

// ── Microphone row ──────────────────────────────────────────

class _MicrophoneRow extends StatelessWidget {
  final List<Map<String, String>> microphones;
  final String selected;
  final ValueChanged<String> onSelect;

  const _MicrophoneRow({
    required this.microphones,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (microphones.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(FlowTokens.space16),
        child: Text('Loading devices…', style: FlowType.caption),
      );
    }
    // Horizontal padding matches `_HotkeyRadioRow` (space16) so the
    // leading edge of the first chip aligns with the radio button
    // above. Vertical padding stays tighter so a block of chips doesn't
    // feel overly tall compared to the radio-row section.
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FlowTokens.space16,
        vertical: FlowTokens.space12,
      ),
      child: Wrap(
        spacing: FlowTokens.space6,
        runSpacing: FlowTokens.space6,
        children: microphones.map((m) {
          final id = m['id'] ?? '';
          final name = m['name'] ?? 'Unknown';
          return _LangChip(
            label: name,
            isActive: selected == id,
            onTap: () => onSelect(id),
          );
        }).toList(),
      ),
    );
  }
}

// ── Voice trigger hint ──────────────────────────────────────

class _VoiceTriggerHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FlowCard(
      padding: const EdgeInsets.all(FlowTokens.space16),
      interactive: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.record_voice_over_rounded,
                size: 14,
                color: FlowTokens.systemBlue,
              ),
              const SizedBox(width: 6),
              Text(
                'Voice commands',
                style: FlowType.bodyStrong.copyWith(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: FlowTokens.space6),
          Text('• "Translate to English: your text"', style: FlowType.caption),
          Text('• "Переведи на русский: ваш текст"', style: FlowType.caption),
          Text('• "Translate to German: Ihr Text"', style: FlowType.caption),
        ],
      ),
    );
  }
}

// ── Diagnostics card ────────────────────────────────────────

class _DiagnosticsCard extends StatelessWidget {
  final StorageService storage;
  final bool backendConnected;
  final VoidCallback onCopy;

  const _DiagnosticsCard({
    required this.storage,
    required this.backendConnected,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('App version', '1.0.0'),
      ('Backend', backendConnected ? 'Connected' : 'Offline'),
      ('Microphone',
          storage.selectedMicId.isNotEmpty ? storage.selectedMicId : 'Default'),
      ('Language', storage.language.isEmpty ? 'Auto' : storage.language),
      ('Grammar', storage.grammarCorrection ? 'On' : 'Off'),
      ('Translation', storage.translationMode),
      ('Hotkey mode', storage.hotkeyMode),
      ('Live dictation', storage.liveDictationEnabled ? 'On' : 'Off'),
      if (storage.lastProvider.isNotEmpty)
        ('Last provider', storage.lastProvider),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: FlowTokens.space8,
            bottom: FlowTokens.space8,
          ),
          child: Text(
            'DIAGNOSTICS',
            style: FlowType.footnote.copyWith(
              color: FlowTokens.textTertiary,
              letterSpacing: 0.6,
            ),
          ),
        ),
        FlowCard(
          interactive: false,
          padding: const EdgeInsets.all(FlowTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...rows.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: FlowTokens.space6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(r.$1, style: FlowType.caption),
                      ),
                      Expanded(
                        child: Text(
                          r.$2,
                          style: FlowType.body.copyWith(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: FlowTokens.space8),
              FlowButton(
                label: 'Copy diagnostics',
                variant: FlowButtonVariant.tinted,
                size: FlowButtonSize.sm,
                leadingIcon: Icons.copy_rounded,
                fullWidth: true,
                onPressed: onCopy,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Appearance row (theme mode selector) ──────────────────────────

class _AppearanceRow extends StatefulWidget {
  const _AppearanceRow();

  @override
  State<_AppearanceRow> createState() => _AppearanceRowState();
}

class _AppearanceRowState extends State<_AppearanceRow> {
  static const _segments = <FlowSegment<FlowThemeMode>>[
    FlowSegment(value: FlowThemeMode.system, label: 'System'),
    FlowSegment(value: FlowThemeMode.light, label: 'Light'),
    FlowSegment(value: FlowThemeMode.dark, label: 'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = FlowThemeController.instance;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return FlowSettingRow(
          leadingIcon: Icons.color_lens_rounded,
          leadingIconBackground: FlowTokens.systemBlue,
          title: 'Theme',
          subtitle: switch (controller.mode) {
            FlowThemeMode.system => 'Follow system appearance',
            FlowThemeMode.light => 'Always light',
            FlowThemeMode.dark => 'Always dark',
          },
          trailing: FlowSegmentedControl<FlowThemeMode>(
            selected: controller.mode,
            segments: _segments,
            onChanged: controller.setMode,
            size: FlowSegmentSize.sm,
          ),
        );
      },
    );
  }
}

// ── About section ───────────────────────────────────────────
//
// Bottom-of-General card exposing the running version and a manual
// "Check for updates" button. The button mirrors the native Flow →
// Check for Updates… menu command so users who never think to click
// a macOS menu bar can still trigger a probe.
//
// State-wise we lean on the existing UpdateService singleton: version
// comes from its PackageInfo snapshot, freshness is reflected via
// ListenableBuilder on the service itself.

class _AboutSection extends StatefulWidget {
  const _AboutSection();

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  bool _checking = false;
  UpdateService? _service;

  @override
  void initState() {
    super.initState();
    _service = UpdateService.current;
    _service?.addListener(_onExternalChange);
    // FlowTokens.* are static getters driven by FlowThemeController.
    // Navigator inside MaterialApp keeps our subtree alive across
    // theme flips, so without a direct listener the cached palette
    // values stick and About renders in the previous brightness.
    FlowThemeController.instance.addListener(_onExternalChange);
  }

  @override
  void dispose() {
    _service?.removeListener(_onExternalChange);
    FlowThemeController.instance.removeListener(_onExternalChange);
    super.dispose();
  }

  void _onExternalChange() {
    if (mounted) setState(() {});
  }

  Future<void> _checkNow() async {
    final service = UpdateService.current;
    if (service == null || _checking) return;

    setState(() => _checking = true);
    final wasAvailable = service.available != null;
    try {
      await service.checkNow();
    } finally {
      if (mounted) setState(() => _checking = false);
    }

    // If the probe didn't surface a newer build, the banner path can't
    // speak for us — drop a toast so the user sees something moved.
    if (!mounted) return;
    if (service.available == null) {
      FlowToast.success(context, 'You\u2019re up to date');
    } else if (!wasAvailable) {
      // New banner just appeared; don't double up with a toast.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Grabbing the singleton inside build() means a late-starting
    // service (login after the widget mounted) still gets picked up on
    // the next parent rebuild.
    final service = _service ?? UpdateService.current;
    final version = service?.currentVersion ?? '';
    final build = service?.currentBuild ?? 0;
    final available = service?.available;

    final versionLine = version.isEmpty
        ? 'Flow'
        : build > 0
            ? 'Flow $version (build $build)'
            : 'Flow $version';

    final subtitle = available != null
        ? 'Update available: ${available.version}'
        : 'You\u2019re on the latest version';

    return FlowSection(
      title: 'About',
      footer: 'Made by George Moses',
      rows: [
        FlowSettingRow(
          leadingIcon: Icons.graphic_eq,
          leadingIconBackground: FlowTokens.accent,
          title: versionLine,
          subtitle: subtitle,
          trailing: FlowButton(
            label: _checking
                ? 'Checking\u2026'
                : available != null
                    ? 'Update'
                    : 'Check for updates',
            variant: available != null
                ? FlowButtonVariant.filled
                : FlowButtonVariant.ghost,
            size: FlowButtonSize.sm,
            onPressed: _checking
                ? null
                : available != null
                    ? () {
                        if (service == null) return;
                        showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => UpdateDownloadDialog(
                            service: service,
                            info: available,
                          ),
                        );
                      }
                    : _checkNow,
          ),
        ),
      ],
    );
  }
}
