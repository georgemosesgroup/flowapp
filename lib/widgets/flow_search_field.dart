import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Compact auto-expanding search field. Collapses to a 30×30 icon button
/// when empty and unfocused, grows to a full input on click/focus — same
/// interaction as the macOS Finder and Mail toolbars.
///
/// The host screen owns the query (via [onChanged]). This widget is
/// purely presentational — it manages its own focus + controller unless
/// you pass in a [controller].
class FlowSearchField extends StatefulWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String hint;

  /// Width when the field is in its expanded state.
  final double expandedWidth;

  /// When true, the field is always expanded (no collapse behaviour).
  /// Useful when the parent reserves space for a full-width search bar.
  final bool alwaysExpanded;

  const FlowSearchField({
    super.key,
    this.controller,
    this.onChanged,
    this.hint = 'Search',
    this.expandedWidth = 260,
    this.alwaysExpanded = false,
  });

  @override
  State<FlowSearchField> createState() => _FlowSearchFieldState();
}

class _FlowSearchFieldState extends State<FlowSearchField> {
  late TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();
  bool _focused = false;
  bool _hover = false;

  bool get _expanded =>
      widget.alwaysExpanded || _focused || _ctrl.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? TextEditingController();
    _focus.addListener(_onFocus);
    _ctrl.addListener(_onText);
  }

  void _onFocus() {
    if (!mounted) return;
    setState(() => _focused = _focus.hasFocus);
  }

  void _onText() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _ctrl.removeListener(_onText);
    if (widget.controller == null) _ctrl.dispose();
    super.dispose();
  }

  void _clear() {
    _ctrl.clear();
    widget.onChanged?.call('');
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final expanded = _expanded;
    final borderColor = _focused
        ? FlowTokens.accent.withValues(alpha: 0.55)
        : FlowTokens.glassEdge;

    return LayoutBuilder(
      builder: (context, constraints) {
        // If the field is wrapped in a Flexible inside a narrow Row we
        // get a bounded maxWidth. Clamp the expanded width against it
        // so the search shrinks instead of overflowing the toolbar.
        final desired = expanded ? widget.expandedWidth : 30.0;
        final maxFromParent = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : desired;
        final width = desired.clamp(30.0, maxFromParent);

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: AnimatedContainer(
            duration: FlowTokens.durBase,
            curve: FlowTokens.easeStandard,
            width: width,
            height: 30,
        decoration: BoxDecoration(
          color: expanded
              ? FlowTokens.bgPressed
              : _hover
                  ? FlowTokens.bgElevatedHover
                  : FlowTokens.bgElevated,
          borderRadius: BorderRadius.circular(FlowTokens.radiusMd),
          border: Border.all(color: borderColor, width: 0.8),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: FlowTokens.accent.withValues(alpha: 0.22),
                    spreadRadius: 1.5,
                    blurRadius: 0,
                  ),
                ]
              : null,
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _focus.requestFocus(),
          child: Padding(
            // When collapsed the container is only 30px wide — 8px padding
            // on both sides + 15px icon + 1.6px border = 32.6px and we
            // overflow by 2.6px. Drop to 6px each side when collapsed
            // so the icon centers cleanly inside the pill.
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? FlowTokens.space8 : 6,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 15,
                  color: _focused
                      ? FlowTokens.textPrimary
                      : FlowTokens.textSecondary,
                ),
                if (expanded) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      onChanged: widget.onChanged,
                      cursorColor: FlowTokens.accent,
                      cursorHeight: 14,
                      style: FlowType.body.copyWith(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        hintStyle: FlowType.body.copyWith(
                          fontSize: 13,
                          color: FlowTokens.textTertiary,
                        ),
                        isDense: true,
                        isCollapsed: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_ctrl.text.isNotEmpty)
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _clear,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: FlowTokens.glassEdge,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 11,
                            color: FlowTokens.textPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
            ),
          ),
        );
      },
    );
  }
}
