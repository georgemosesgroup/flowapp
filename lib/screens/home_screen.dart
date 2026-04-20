import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/speech_service.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/dictation_card.dart';
import '../widgets/error_banner.dart';
import '../widgets/flow_button.dart';
import '../widgets/flow_card.dart';
import '../widgets/flow_scroll_elevated.dart';
import '../widgets/toolbar_inset.dart';

class HomeScreen extends StatefulWidget {
  final AuthService authService;
  final SpeechService speechService;
  final ApiService apiService;
  final bool isRecording;
  final bool isTranscribing;
  final void Function(void Function(String text) callback) onDictationCallback;

  final bool Function()? canUndoInsertion;
  final Future<bool> Function()? onUndoInsertion;
  final int insertionTick;

  const HomeScreen({
    super.key,
    required this.authService,
    required this.speechService,
    required this.apiService,
    required this.isRecording,
    required this.isTranscribing,
    required this.onDictationCallback,
    this.canUndoInsertion,
    this.onUndoInsertion,
    this.insertionTick = 0,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<_DictationEntry> _history = [];
  int _totalWords = 0;
  final int _streakDays = 0;

  bool _loading = true;
  String? _error;

  /// Selected language filter for the recent-dictations list. `null` means
  /// "All". Matches against [_DictationEntry.language].
  String? _filterLang;

  /// Drives the CustomScrollView so tapping a filter chip can jump
  /// the list back to the top — otherwise the user ends up on a page
  /// of dictations that doesn't exist in the new filter.
  final ScrollController _scrollController = ScrollController();

  /// True while the content area is scrolled past ~4 px from the top —
  /// drives the toolbar's pill/darken transition (FlowScrollElevated).
  bool _headerElevated = false;


  bool _undoAvailable = false;
  int _undoSecondsLeft = 0;
  Timer? _undoTicker;

  /// Frequency-by-language map for the filter chips. Keys are normalized
  /// ISO-639-1 codes ("ru", "en", "hy"…), so records stored with legacy
  /// full-name values ("Russian", "english") collapse into the same chip.
  Map<String, int> get _langCounts {
    final m = <String, int>{};
    for (final e in _history) {
      final code = _normalizeLang(e.language);
      if (code.isEmpty) continue;
      m[code] = (m[code] ?? 0) + 1;
    }
    return m;
  }

  List<_DictationEntry> get _filteredHistory {
    final f = _filterLang;
    if (f == null) return _history;
    return _history.where((e) => _normalizeLang(e.language) == f).toList();
  }

  /// Squash whatever the backend / recognizer stored as a language tag into
  /// the canonical 2-letter ISO-639-1 code. Handles: nullable, casing,
  /// dialect suffixes ("en-US" → "en"), and the full-name form some older
  /// records use ("Russian" → "ru"). Returns empty string if the tag can't
  /// be mapped — the caller skips those so they don't show up as a junk
  /// chip.
  String _normalizeLang(String? raw) {
    if (raw == null) return '';
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return '';
    // Strip locale suffix: en-US → en, pt_br → pt
    final sep = RegExp(r'[-_]');
    if (sep.hasMatch(s)) s = s.split(sep).first;
    // Already a 2-letter code → keep it.
    if (s.length == 2) return s;
    // Map English / endonym full names to codes. Covers whatever the API
    // has historically returned ("Russian", "русский", etc.).
    const nameToCode = {
      'russian': 'ru',
      'русский': 'ru',
      'english': 'en',
      'armenian': 'hy',
      'հայերեն': 'hy',
      'georgian': 'ka',
      'ქართული': 'ka',
      'ukrainian': 'uk',
      'українська': 'uk',
      'german': 'de',
      'deutsch': 'de',
      'french': 'fr',
      'français': 'fr',
      'francais': 'fr',
      'spanish': 'es',
      'español': 'es',
      'espanol': 'es',
      'italian': 'it',
      'italiano': 'it',
      'portuguese': 'pt',
      'português': 'pt',
      'portugues': 'pt',
      'polish': 'pl',
      'polski': 'pl',
      'turkish': 'tr',
      'türkçe': 'tr',
      'turkce': 'tr',
      'chinese': 'zh',
      '中文': 'zh',
      'japanese': 'ja',
      '日本語': 'ja',
      'korean': 'ko',
      '한국어': 'ko',
      'arabic': 'ar',
      'العربية': 'ar',
      'hindi': 'hi',
      'हिन्दी': 'hi',
      'hebrew': 'he',
      'עברית': 'he',
    };
    return nameToCode[s] ?? s;
  }

  @override
  void initState() {
    super.initState();
    widget.onDictationCallback(_onDictationComplete);
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.insertionTick != oldWidget.insertionTick &&
        (widget.canUndoInsertion?.call() ?? false)) {
      _startUndoCountdown();
    }
  }

  void _startUndoCountdown() {
    _undoTicker?.cancel();
    setState(() {
      _undoAvailable = true;
      _undoSecondsLeft = 10;
    });
    _undoTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final stillLive = widget.canUndoInsertion?.call() ?? false;
      setState(() {
        _undoSecondsLeft = _undoSecondsLeft - 1;
        if (!stillLive || _undoSecondsLeft <= 0) {
          _undoAvailable = false;
          _undoSecondsLeft = 0;
          t.cancel();
        }
      });
    });
  }

  Future<void> _handleUndo() async {
    final cb = widget.onUndoInsertion;
    if (cb == null) return;
    final ok = await cb();
    if (!mounted) return;
    if (ok) {
      setState(() {
        if (_history.isNotEmpty && _history.first.id.isEmpty) {
          _totalWords -= _history.first.wordCount;
          _history.removeAt(0);
        }
        _undoAvailable = false;
        _undoSecondsLeft = 0;
      });
      _undoTicker?.cancel();
    }
  }

  @override
  void dispose() {
    _undoTicker?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Flip the filter chip and jump the list back to the top in one
  /// motion. Without the scroll reset a user deep in the list who
  /// taps a new language lands on a window of history that often
  /// doesn't even exist in the filtered set, which reads as "the
  /// chip broke".
  void _setFilter(String? lang) {
    setState(() => _filterLang = lang);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: FlowTokens.durBase,
        curve: FlowTokens.easeStandard,
      );
    }
  }

  Future<void> _loadHistory() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await widget.apiService.getDictations(limit: 50);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _history.clear();
        _totalWords = 0;
        for (final item in items) {
          _history.add(_DictationEntry.fromJson(item));
          _totalWords += (item['word_count'] as int? ?? 0);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load history';
      });
    }
  }

  Future<void> _deleteDictation(String id, int index) async {
    final success = await widget.apiService.deleteDictation(id);
    if (success && mounted) {
      setState(() {
        final entry = _history.removeAt(index);
        _totalWords -= entry.wordCount;
      });
    }
  }

  Future<bool> _correctDictation(String id, int index, String correctedText) async {
    final ok = await widget.apiService.correctDictation(
      id: id,
      correctedText: correctedText,
    );
    if (ok && mounted) {
      setState(() {
        final old = _history[index];
        _history[index] = _DictationEntry(
          id: old.id,
          text: correctedText,
          language: old.language,
          translatedText: old.translatedText,
          translatedTo: old.translatedTo,
          grammarApplied: old.grammarApplied,
          timestamp: old.timestamp,
          wordCount: correctedText.split(RegExp(r'\s+')).length,
        );
      });
    }
    return ok;
  }

  void _onDictationComplete(String text) {
    if (!mounted) return;
    final wordCount = text.split(RegExp(r'\s+')).length;
    setState(() {
      _history.insert(0, _DictationEntry(
        id: '',
        text: text,
        timestamp: DateTime.now(),
        wordCount: wordCount,
      ));
      _totalWords += wordCount;
    });
  }

  @override
  Widget build(BuildContext context) {
    final firstName = widget.authService.userName.split(' ').first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlowScrollElevated(
          elevated: _headerElevated,
          child: _Toolbar(
            title: 'Home',
            status: _StatusPill(
              isRecording: widget.isRecording,
              isTranscribing: widget.isTranscribing,
            ),
            trailing: [
              _InfoPill(
                icon: Icons.language_rounded,
                label: _langName(StorageService.instance.language),
              ),
              const SizedBox(width: FlowTokens.space6),
              _InfoPill(
                icon: Icons.graphic_eq_rounded,
                label: StorageService.instance.liveDictationEnabled
                    ? 'Live on'
                    : 'Live off',
              ),
            ],
            onRefresh: _loading ? null : _loadHistory,
          ),
        ),
        Expanded(
          // 3% dark tint behind the scroll area — barely perceptible to
          // the eye but gives Flutter's `BackdropFilter` in the sticky
          // header something solid to blur. Without this the
          // NSVisualEffectView shines through as raw transparency and
          // backdrop-filter has nothing to sample.
          child: ColoredBox(
            color: FlowTokens.backdropSampleTint,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollUpdateNotification ||
                    n is ScrollEndNotification) {
                  final shouldElevate = n.metrics.pixels > 4;
                  if (shouldElevate != _headerElevated && mounted) {
                    setState(() => _headerElevated = shouldElevate);
                  }
                }
                return false;
              },
              child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // Hero strip — Welcome + metrics + undo banner (if fresh).
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    FlowTokens.space24,
                    FlowTokens.space20,
                    FlowTokens.space24,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back, $firstName',
                          style: FlowType.title.copyWith(fontSize: 20),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Hold Ctrl anywhere to start dictating.',
                          style: FlowType.caption,
                        ),
                        const SizedBox(height: FlowTokens.space20),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _MetricTile(
                                icon: Icons.local_fire_department_rounded,
                                iconColor: FlowTokens.systemOrange,
                                value: '$_streakDays',
                                label: 'day streak',
                              ),
                              const SizedBox(width: FlowTokens.space10),
                              _MetricTile(
                                icon: Icons.auto_awesome_motion,
                                iconColor: FlowTokens.systemBlue,
                                value: _formatWords(_totalWords),
                                label: 'total words',
                              ),
                              const SizedBox(width: FlowTokens.space10),
                              _MetricTile(
                                icon: Icons.bolt_rounded,
                                iconColor: FlowTokens.systemGreen,
                                value: '—',
                                label: 'avg WPM',
                              ),
                            ],
                          ),
                        ),
                        if (_undoAvailable &&
                            widget.onUndoInsertion != null) ...[
                          const SizedBox(height: FlowTokens.space16),
                          _UndoBanner(
                            secondsLeft: _undoSecondsLeft,
                            onUndo: _handleUndo,
                            onDismiss: () {
                              _undoTicker?.cancel();
                              setState(() {
                                _undoAvailable = false;
                                _undoSecondsLeft = 0;
                              });
                            },
                          ),
                        ],
                        const SizedBox(height: FlowTokens.space16),
                      ],
                    ),
                  ),
                ),

                // Section label — sits in the normal scroll flow and
                // disappears behind the sticky chips bar as the user
                // scrolls.
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    FlowTokens.space24,
                    0,
                    FlowTokens.space24,
                    FlowTokens.space8,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Recent dictations',
                      style: FlowType.footnote.copyWith(
                        color: FlowTokens.textTertiary,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                // Sticky chips row. Pins to the top under the toolbar
                // and picks up a blurred translucent backdrop when it
                // overlaps scrolling content — mirrors the toolbar's
                // own elevation treatment.
                if (_history.isNotEmpty && _langCounts.length >= 2)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _RecentStickyHeader(
                      counts: _langCounts,
                      total: _history.length,
                      selected: _filterLang,
                      onSelect: _setFilter,
                      brightness: Theme.of(context).brightness,
                    ),
                  ),

                if (_error != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      FlowTokens.space24,
                      0,
                      FlowTokens.space24,
                      FlowTokens.space12,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: ErrorBanner(
                        message: _error!,
                        onRetry: _loadHistory,
                        onDismiss: () => setState(() => _error = null),
                      ),
                    ),
                  ),

                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsets.all(FlowTokens.space32),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: FlowTokens.accent,
                            strokeWidth: 2.2,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (_history.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(),
                  )
                else if (_filteredHistory.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _FilterEmptyState(
                      lang: _languageName(_filterLang ?? ''),
                      onReset: () => _setFilter(null),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      FlowTokens.space24,
                      0,
                      FlowTokens.space24,
                      FlowTokens.space24,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) {
                          final entry = _filteredHistory[i];
                          final originalIndex = _history.indexOf(entry);
                          return DictationCard(
                            id: entry.id,
                            text: entry.text,
                            language: entry.language,
                            translatedText: entry.translatedText,
                            translatedTo: entry.translatedTo,
                            grammarApplied: entry.grammarApplied,
                            wordCount: entry.wordCount,
                            createdAt: entry.timestamp.toIso8601String(),
                            onCopy: () {},
                            onDelete: entry.id.isNotEmpty
                                ? () =>
                                    _deleteDictation(entry.id, originalIndex)
                                : null,
                            onCorrect: entry.id.isNotEmpty
                                ? (corrected) => _correctDictation(
                                      entry.id,
                                      originalIndex,
                                      corrected,
                                    )
                                : null,
                          );
                        },
                        childCount: _filteredHistory.length,
                      ),
                    ),
                  ),
              ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatWords(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }

  String _langName(String code) {
    if (code.isEmpty) return 'Auto-detect';
    // Reuse the shared English name map so every surface (info pill,
    // filter chips, empty states) shows identical labels for the same
    // language code. Fallback returns the code in uppercase for exotic
    // values the table doesn't know about yet.
    return _languageName(code);
  }
}

// ── Toolbar ────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  final String title;
  final Widget? status;
  final List<Widget> trailing;
  final VoidCallback? onRefresh;

  const _Toolbar({
    required this.title,
    this.status,
    this.trailing = const [],
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final leftInset = ToolbarInset.leftOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        FlowTokens.space20 + leftInset,
        FlowTokens.space12,
        FlowTokens.space16,
        FlowTokens.space12,
      ),
      child: Row(
        children: [
          Text(title, style: FlowType.title),
          const SizedBox(width: FlowTokens.space12),
          // Status pill keeps its intrinsic width. Inside the pill the
          // label itself uses `Flexible` + ellipsis, so when the
          // viewport is narrow the pill shrinks gracefully instead of
          // overflowing the toolbar. Wrapping `status` in an outer
          // `Flexible` alongside a `Spacer` leaves dead space on the
          // right because both claim flex — we don't want that.
          ?status,
          // Greedy expander pushes the trailing cluster to the right
          // edge of the toolbar padding. `Expanded` (instead of
          // `Spacer`) plays nicer with varying status-pill widths and
          // guarantees the trailing group hugs the right edge.
          const Expanded(child: SizedBox.shrink()),
          // Separator before each trailing pill (but not at the end).
          for (var i = 0; i < trailing.length; i++) ...[
            if (i > 0) const SizedBox(width: FlowTokens.space4),
            trailing[i],
          ],
          if (onRefresh != null) ...[
            const SizedBox(width: FlowTokens.space6),
            _IconTapButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Refresh',
              onTap: onRefresh!,
              alwaysBg: true,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Top bar status pill ────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final bool isRecording;
  final bool isTranscribing;
  const _StatusPill({required this.isRecording, required this.isTranscribing});

  @override
  Widget build(BuildContext context) {
    IconData? icon;
    Widget? leading;
    String label;
    Color fg;
    Color bg;

    if (isRecording) {
      leading = _PulsingDot(color: FlowTokens.accent);
      label = 'Recording';
      fg = FlowTokens.accent;
      bg = FlowTokens.accentSubtle;
    } else if (isTranscribing) {
      leading = const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(
          color: FlowTokens.systemOrange,
          strokeWidth: 1.8,
        ),
      );
      label = 'Transcribing';
      fg = FlowTokens.systemOrange;
      bg = FlowTokens.warningSubtle;
    } else {
      icon = Icons.keyboard_command_key_rounded;
      label = 'Hold ^ Ctrl';
      fg = FlowTokens.textSecondary;
      bg = FlowTokens.bgElevated;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FlowTokens.space10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(FlowTokens.radiusFull),
        border: Border.all(color: FlowTokens.strokeSubtle, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?leading,
          if (icon != null) Icon(icon, size: 12, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: FlowType.footnote.copyWith(color: fg),
              overflow: TextOverflow.fade,
              softWrap: false,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.7 + 0.3 * _c.value),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.4 * _c.value),
              blurRadius: 6 * _c.value,
              spreadRadius: 1 * _c.value,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Metric tile ────────────────────────────────────────────────────

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _MetricTile({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FlowCard(
        padding: const EdgeInsets.all(FlowTokens.space12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
                  ),
                  child: Icon(icon, size: 14, color: iconColor),
                ),
              ],
            ),
            const SizedBox(height: FlowTokens.space10),
            Text(
              value,
              style: FlowType.title.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: FlowType.footnote.copyWith(
                color: FlowTokens.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Info pill ──────────────────────────────────────────────────────

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FlowTokens.space10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: FlowTokens.bgElevated,
        borderRadius: BorderRadius.circular(FlowTokens.radiusFull),
        border: Border.all(color: FlowTokens.strokeSubtle, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: FlowTokens.textSecondary),
          const SizedBox(width: 6),
          Text(label, style: FlowType.footnote),
        ],
      ),
    );
  }
}

// ── Undo banner ────────────────────────────────────────────────────

class _UndoBanner extends StatelessWidget {
  final int secondsLeft;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  const _UndoBanner({
    required this.secondsLeft,
    required this.onUndo,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FlowTokens.space12),
      decoration: BoxDecoration(
        color: FlowTokens.infoSubtle,
        borderRadius: BorderRadius.circular(FlowTokens.radiusLg),
        border: Border.all(
          color: FlowTokens.systemBlue.withValues(alpha: 0.35),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: FlowTokens.systemBlue.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
            ),
            child: const Icon(
              Icons.undo_rounded,
              size: 15,
              color: FlowTokens.systemBlue,
            ),
          ),
          const SizedBox(width: FlowTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Undo last insertion',
                    style: FlowType.bodyStrong.copyWith(fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  '⌘Z will be sent to the focused app',
                  style: FlowType.caption,
                ),
              ],
            ),
          ),
          FlowButton(
            label: 'Undo (${secondsLeft}s)',
            size: FlowButtonSize.sm,
            variant: FlowButtonVariant.tinted,
            onPressed: onUndo,
          ),
          const SizedBox(width: FlowTokens.space4),
          _IconTapButton(
            icon: Icons.close_rounded,
            tooltip: 'Dismiss',
            onTap: onDismiss,
          ),
        ],
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FlowCard(
      padding: const EdgeInsets.symmetric(
        horizontal: FlowTokens.space24,
        vertical: FlowTokens.space32,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    FlowTokens.accent.withValues(alpha: 0.18),
                    FlowTokens.systemBlue.withValues(alpha: 0.18),
                  ],
                ),
                borderRadius: BorderRadius.circular(FlowTokens.radiusMd),
              ),
              child: const Icon(
                Icons.graphic_eq_rounded,
                size: 22,
                color: FlowTokens.accent,
              ),
            ),
            const SizedBox(height: FlowTokens.space16),
            Text('No dictations yet', style: FlowType.headline),
            const SizedBox(height: FlowTokens.space4),
            Text(
              'Hold ^ Ctrl anywhere to dictate your first note.',
              style: FlowType.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sticky "Recent dictations" + filter chips ──────────────────────

class _RecentStickyHeader extends SliverPersistentHeaderDelegate {
  final Map<String, int> counts;
  final int total;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final Brightness brightness;

  const _RecentStickyHeader({
    required this.counts,
    required this.total,
    required this.selected,
    required this.onSelect,
    required this.brightness,
  });

  // Chip row is 26 px tall; with 8 px top + 10 px bottom padding
  // the total strip is 44 px — a comfortable toolbar-style band.
  static const double _height = 44;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Two modes:
    //
    //  • At rest (nothing underneath) the row is just the chips — no
    //    blur, no fill, no stroke. They sit flush in the content and
    //    read as part of the list header.
    //
    //  • As soon as the user scrolls past the title and the pinned bar
    //    overlaps scrolling content, we render the chips inside a
    //    floating rounded capsule with its own `BackdropFilter` blur
    //    + translucent fill + hairline — it detaches from the page
    //    and reads as a separate surface, like a macOS toolbar pill.
    final chips = _LangFilterChips(
      counts: counts,
      total: total,
      selected: selected,
      onSelect: onSelect,
    );

    // Full-width frosted-glass strip — same recipe Apple uses for
    // Safari/Music toolbars. Two layers stacked:
    //   [0] BackdropFilter band that blurs dictation cards scrolling
    //       underneath + dark tint + bottom hairline → reads as an
    //       elevated toolbar.
    //   [1] The chips on top, fixed position.
    // The band fades in as soon as `overlapsContent` flips — chips
    // themselves never animate, so their position doesn't shift.
    final isDark = brightness == Brightness.dark;
    // Band tint should look like the top Home-toolbar, which is
    // transparent and composes down to whatever the native vibrancy
    // layer paints (.sidebar material + 62% black in dark /
    // 5% white in light). In dark that composite lands around
    // ~7% brightness — `bgSurfaceOpaque` (0x111114) matches.
    // In light the composite reads as a ~92% light-gray (NOT pure
    // white), so `bgSurfaceOpaque` (0xFFFFFFFF) was popping bright
    // against the grayer header. System gray 5-ish (0xECECEE)
    // lands on the same gray plane as the native composite.
    final bandTint = isDark
        ? FlowTokens.bgSurfaceOpaque // 0xFF111114 in dark
        : const Color(0xFFD1D1D6); // ~82% gray — the native
                                    // .sidebar aqua + 5% white
                                    // composite lands near macOS
                                    // systemGray5 under most
                                    // wallpapers

    // Pinning triggers on any non-zero scroll offset. Using
    // `overlapsContent` was unreliable — it only flipped when a
    // prior sliver geometrically overlapped the pinned header, not
    // when trailing list items scrolled under it.
    final scrolled = shrinkOffset > 0.5;
    // Same hairline token the top Home-toolbar uses via
    // FlowScrollElevated — keeps the two bars visually paired.
    final bandHairline = FlowTokens.strokeSubtle;

    return Stack(
      fit: StackFit.expand,
      children: [
        // — Solid body-color band with hairline on the bottom.
        //   Mirrors how the top Home-toolbar paints itself (opaque
        //   canvas + bottom stroke once scrolling engages). Fades in
        //   only once scroll overlaps the header so the chips sit
        //   flush with the list header at rest. Container (not
        //   DecoratedBox) so the fill stretches to the full Stack
        //   extent instead of collapsing to zero. —
        AnimatedOpacity(
          duration: FlowTokens.durFast,
          opacity: scrolled ? 1.0 : 0.0,
          child: Container(
            decoration: BoxDecoration(
              color: bandTint,
              border: Border(
                bottom: BorderSide(color: bandHairline, width: 0.5),
              ),
            ),
          ),
        ),
        // — Chips (never animate) —
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FlowTokens.space24,
            FlowTokens.space8,
            FlowTokens.space24,
            FlowTokens.space10,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: chips,
          ),
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(covariant _RecentStickyHeader old) {
    return old.counts.length != counts.length ||
        old.total != total ||
        old.selected != selected ||
        old.brightness != brightness;
  }
}

// ── Shared ISO-639-1 → English name mapping ────────────────────────

const Map<String, String> _languageNames = {
  'ru': 'Russian',
  'en': 'English',
  'uk': 'Ukrainian',
  'de': 'German',
  'fr': 'French',
  'es': 'Spanish',
  'it': 'Italian',
  'pt': 'Portuguese',
  'pl': 'Polish',
  'ka': 'Georgian',
  'hy': 'Armenian',
  'zh': 'Chinese',
  'ja': 'Japanese',
  'ko': 'Korean',
  'tr': 'Turkish',
  'ar': 'Arabic',
  'hi': 'Hindi',
  'he': 'Hebrew',
  'nl': 'Dutch',
  'sv': 'Swedish',
  'no': 'Norwegian',
  'fi': 'Finnish',
  'cs': 'Czech',
  'el': 'Greek',
  'ro': 'Romanian',
  'hu': 'Hungarian',
  'bg': 'Bulgarian',
  'sk': 'Slovak',
  'az': 'Azerbaijani',
  'kk': 'Kazakh',
  'uz': 'Uzbek',
  'vi': 'Vietnamese',
  'th': 'Thai',
  'id': 'Indonesian',
};

String _languageName(String code) =>
    _languageNames[code.toLowerCase()] ?? code.toUpperCase();

// ── Language filter chips ──────────────────────────────────────────

class _LangFilterChips extends StatelessWidget {
  final Map<String, int> counts;
  final int total;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _LangFilterChips({
    required this.counts,
    required this.total,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    // Sort by frequency so the most-used language appears first.
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Row(mainAxisSize: min) so the cluster can be wrapped in an
    // Align/ClipRRect and live inside a floating capsule (the
    // sticky-state backdrop) without demanding full width. If the
    // language list ever grows beyond what fits, the parent can clip
    // — we'd rather lose the tail than force an internal scroll bar
    // inside a pinned pill.
    return SizedBox(
      height: 26,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LangChip(
            label: 'All',
            count: total,
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final entry in sorted) ...[
            const SizedBox(width: 6),
            _LangChip(
              label: _langLabel(entry.key),
              count: entry.value,
              selected: selected == entry.key,
              onTap: () => onSelect(entry.key),
            ),
          ],
        ],
      ),
    );
  }

  String _langLabel(String code) => _languageName(code);
}

class _LangChip extends StatefulWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _LangChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_LangChip> createState() => _LangChipState();
}

class _LangChipState extends State<_LangChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    final bg = active
        ? FlowTokens.accentSubtle
        : _hover
            ? FlowTokens.hoverSurface
            : FlowTokens.hoverSubtle;
    final fg = active ? FlowTokens.accent : FlowTokens.textSecondary;
    final border = active
        ? FlowTokens.accent.withValues(alpha: 0.35)
        : FlowTokens.strokeSubtle;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: FlowTokens.durFast,
          curve: FlowTokens.easeStandard,
          padding: const EdgeInsets.symmetric(
            horizontal: FlowTokens.space10,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(FlowTokens.radiusFull),
            border: Border.all(color: border, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: FlowType.footnote.copyWith(
                  fontSize: 11.5,
                  color: fg,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '${widget.count}',
                style: FlowType.footnote.copyWith(
                  fontSize: 10.5,
                  color: active
                      ? FlowTokens.accent.withValues(alpha: 0.75)
                      : FlowTokens.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Filter empty state (when a language has no matches) ─────────────

class _FilterEmptyState extends StatelessWidget {
  final String lang;
  final VoidCallback onReset;
  const _FilterEmptyState({required this.lang, required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FlowTokens.space20),
      child: Center(
        child: Column(
          children: [
            Text(
              'No dictations for $lang',
              style: FlowType.caption,
            ),
            const SizedBox(height: FlowTokens.space8),
            FlowButton(
              label: 'Show all',
              variant: FlowButtonVariant.plain,
              size: FlowButtonSize.sm,
              onPressed: onReset,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Icon-only button ───────────────────────────────────────────────

class _IconTapButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  /// When true, the button always carries a subtle pill background
  /// (matches the surrounding info pills in the toolbar). Off by
  /// default so inline uses stay ghost-like.
  final bool alwaysBg;
  const _IconTapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.alwaysBg = false,
  });

  @override
  State<_IconTapButton> createState() => _IconTapButtonState();
}

class _IconTapButtonState extends State<_IconTapButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.alwaysBg
        ? (_hover ? FlowTokens.bgElevatedHover : FlowTokens.bgElevated)
        : (_hover ? FlowTokens.bgElevatedHover : Colors.transparent);
    final border = widget.alwaysBg ? FlowTokens.strokeSubtle : Colors.transparent;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: FlowTokens.durFast,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: bg,
              borderRadius:
                  BorderRadius.circular(FlowTokens.radiusFull),
              border: Border.all(color: border, width: 0.5),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: _hover
                  ? FlowTokens.textPrimary
                  : FlowTokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Model ──────────────────────────────────────────────────────────

class _DictationEntry {
  final String id;
  final String text;
  final String? language;
  final String? translatedText;
  final String? translatedTo;
  final bool grammarApplied;
  final DateTime timestamp;
  final int wordCount;

  _DictationEntry({
    required this.id,
    required this.text,
    this.language,
    this.translatedText,
    this.translatedTo,
    this.grammarApplied = false,
    required this.timestamp,
    required this.wordCount,
  });

  factory _DictationEntry.fromJson(Map<String, dynamic> json) {
    return _DictationEntry(
      id: json['id']?.toString() ?? '',
      text: json['text'] as String? ?? '',
      language: json['language'] as String?,
      translatedText: json['translated_text'] as String?,
      translatedTo: json['translated_to'] as String?,
      grammarApplied: json['grammar_applied'] as bool? ?? false,
      timestamp: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      wordCount: json['word_count'] as int? ?? 0,
    );
  }
}
