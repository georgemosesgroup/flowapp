import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'flow_button.dart';
import 'flow_card.dart';

class DictationCard extends StatefulWidget {
  final String id;
  final String text;
  final String? language;
  final String? translatedText;
  final String? translatedTo;
  final bool grammarApplied;
  final int wordCount;
  final String createdAt;
  final VoidCallback? onDelete;
  final VoidCallback? onCopy;

  /// Called when the user saves a correction. The callback is expected to
  /// push the edited text to the backend and update local state on success.
  final Future<bool> Function(String correctedText)? onCorrect;

  const DictationCard({
    super.key,
    required this.id,
    required this.text,
    this.language,
    this.translatedText,
    this.translatedTo,
    this.grammarApplied = false,
    required this.wordCount,
    required this.createdAt,
    this.onDelete,
    this.onCopy,
    this.onCorrect,
  });

  @override
  State<DictationCard> createState() => _DictationCardState();
}

class _DictationCardState extends State<DictationCard> {
  bool _hovering = false;
  bool _copied = false;
  bool _editing = false;
  bool _saving = false;
  bool _correctedBadge = false;
  late TextEditingController _editController;

  String get _displayTime {
    try {
      final dt = DateTime.parse(widget.createdAt).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.text);
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _copyText() {
    final textToCopy = widget.translatedText ?? widget.text;
    Clipboard.setData(ClipboardData(text: textToCopy));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
    widget.onCopy?.call();
  }

  void _beginEdit() {
    _editController.text = widget.text;
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    setState(() => _editing = false);
  }

  Future<void> _saveEdit() async {
    final edited = _editController.text.trim();
    if (edited.isEmpty || edited == widget.text.trim()) {
      setState(() => _editing = false);
      return;
    }
    if (widget.onCorrect == null) {
      setState(() => _editing = false);
      return;
    }
    setState(() => _saving = true);
    final ok = await widget.onCorrect!(edited);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _editing = !ok;
      if (ok) _correctedBadge = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FlowTokens.space10),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: FlowCard(
          interactive: !_editing,
          padding: const EdgeInsets.all(FlowTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: FlowTokens.space10),
              if (_editing)
                _buildEditor()
              else
                Text(
                  widget.text,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: FlowType.body.copyWith(
                    fontSize: 13.5,
                    height: 1.55,
                  ),
                ),
              if (widget.translatedText != null &&
                  widget.translatedText!.isNotEmpty) ...[
                const SizedBox(height: FlowTokens.space10),
                _buildTranslation(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          _displayTime,
          style: FlowType.mono.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: FlowTokens.textTertiary,
          ),
        ),
        const SizedBox(width: FlowTokens.space8),
        if (widget.translatedTo != null)
          _Badge(label: 'Translated', color: FlowTokens.systemBlue)
        else if (widget.grammarApplied)
          _Badge(label: 'Corrected', color: FlowTokens.systemGreen),
        if (widget.language != null && widget.language!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: _Badge(
              label: widget.language!.toUpperCase(),
              color: FlowTokens.textTertiary,
            ),
          ),
        if (_correctedBadge)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: _Badge(
              label: 'Edited',
              color: const Color(0xFFB085F5),
            ),
          ),
        const Spacer(),
        Text(
          '${widget.wordCount} ${widget.wordCount == 1 ? 'word' : 'words'}',
          style: FlowType.footnote.copyWith(color: FlowTokens.textTertiary),
        ),
        // Actions collapse when not hovered so the word-count label sits
        // flush with the right edge instead of floating with empty space.
        if (!_editing)
          AnimatedSize(
            duration: FlowTokens.durFast,
            curve: FlowTokens.easeStandard,
            alignment: Alignment.centerLeft,
            child: _hovering
                ? Padding(
                    padding: const EdgeInsets.only(left: FlowTokens.space8),
                    child: _buildActionRow(),
                  )
                : const SizedBox(width: 0, height: 26),
          ),
      ],
    );
  }

  Widget _buildActionRow() {
    // Parent (AnimatedSize) handles show/hide. Actions stay a plain row.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onCorrect != null)
          _HoverIconButton(
            icon: Icons.edit_rounded,
            tooltip: 'Correct',
            onTap: _beginEdit,
          ),
        _HoverIconButton(
          icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
          tooltip: _copied ? 'Copied' : 'Copy',
          tint: _copied ? FlowTokens.systemGreen : null,
          onTap: _copyText,
        ),
        if (widget.onDelete != null)
          _HoverIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete',
            tint: FlowTokens.systemRed,
            onTap: widget.onDelete,
          ),
      ],
    );
  }

  Widget _buildTranslation() {
    return Container(
      padding: const EdgeInsets.all(FlowTokens.space10),
      decoration: BoxDecoration(
        color: FlowTokens.systemBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(FlowTokens.radiusMd),
        border: Border.all(
          color: FlowTokens.systemBlue.withValues(alpha: 0.18),
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.translate_rounded,
            size: 13,
            color: FlowTokens.systemBlue,
          ),
          const SizedBox(width: FlowTokens.space8),
          Expanded(
            child: Text(
              widget.translatedText!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: FlowType.body.copyWith(
                fontSize: 12.5,
                color: FlowTokens.systemBlue.withValues(alpha: 0.95),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _editController,
          maxLines: 6,
          minLines: 2,
          autofocus: true,
          enabled: !_saving,
          style: FlowType.body.copyWith(fontSize: 13.5, height: 1.55),
          decoration: InputDecoration(
            filled: true,
            fillColor: FlowTokens.bgCanvasOpaque,
            contentPadding: const EdgeInsets.all(FlowTokens.space12),
            border: _editorBorder(FlowTokens.strokeSubtle),
            enabledBorder: _editorBorder(FlowTokens.strokeSubtle),
            focusedBorder: _editorBorder(FlowTokens.accent, width: 1.2),
          ),
        ),
        const SizedBox(height: FlowTokens.space10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FlowButton(
              label: 'Cancel',
              variant: FlowButtonVariant.ghost,
              size: FlowButtonSize.sm,
              onPressed: _saving ? null : _cancelEdit,
            ),
            const SizedBox(width: FlowTokens.space6),
            FlowButton(
              label: _saving ? 'Saving…' : 'Save',
              variant: FlowButtonVariant.filled,
              size: FlowButtonSize.sm,
              onPressed: _saving ? null : _saveEdit,
            ),
          ],
        ),
      ],
    );
  }

  OutlineInputBorder _editorBorder(Color color, {double width = 0.5}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(FlowTokens.radiusMd),
        borderSide: BorderSide(color: color, width: width),
      );
}

// ── Badge (translated/corrected/lang pill) ───────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(FlowTokens.radiusXs),
      ),
      child: Text(
        label,
        style: FlowType.footnote.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Hover icon button ────────────────────────────────────────────────

class _HoverIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final Color? tint;
  final VoidCallback? onTap;

  const _HoverIconButton({
    required this.icon,
    required this.tooltip,
    this.tint,
    this.onTap,
  });

  @override
  State<_HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<_HoverIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.tint ?? FlowTokens.textSecondary;
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
            margin: const EdgeInsets.only(left: 2),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: _hover
                  ? baseColor.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: _hover ? baseColor : baseColor.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}
