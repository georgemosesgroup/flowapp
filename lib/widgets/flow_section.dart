import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Grouped list section in the macOS Settings style.
///
/// Produces a header label + a rounded container that holds [rows]
/// separated by hairline dividers. Matches the "insetGrouped" table-view
/// look from iOS/macOS system settings.
class FlowSection extends StatelessWidget {
  final String? title;
  final String? footer;
  final List<Widget> rows;

  const FlowSection({
    super.key,
    this.title,
    this.footer,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(
              left: FlowTokens.space8,
              bottom: FlowTokens.space8,
            ),
            child: Text(
              title!.toUpperCase(),
              style: FlowType.footnote.copyWith(
                // Bump contrast — the old `textTertiary` (50%) washed out
                // almost completely over the Liquid-Glass vibrancy.
                color: FlowTokens.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
        // ClipRRect is load-bearing: without it, row hover colors paint
        // into the outer container's rounded corners and square them off
        // (most visible on the first and last row of a section).
        //
        // `width: double.infinity` is also load-bearing: without it,
        // sections that use shrink-wrapping content (Wrap, small Text,
        // etc.) would render narrower than sections that use Row with
        // Expanded. The result was two adjacent sections visibly
        // different widths — most noticeable between Translation (full
        // width) and Microphone (shrink-wrapped to chip content).
        SizedBox(
          width: double.infinity,
          child: Container(
            decoration: BoxDecoration(
              color: FlowTokens.bgElevated,
              borderRadius: BorderRadius.circular(FlowTokens.radiusLg),
              border: Border.all(color: FlowTokens.strokeSubtle, width: 0.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(FlowTokens.radiusLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    rows[i],
                    if (i < rows.length - 1)
                      Padding(
                        padding: const EdgeInsets.only(
                            left: FlowTokens.space16),
                        child: Divider(
                          height: 0.5,
                          thickness: 0.5,
                          color: FlowTokens.strokeDivider,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.only(
              left: FlowTokens.space8,
              top: FlowTokens.space8,
              right: FlowTokens.space8,
            ),
            child: Text(footer!, style: FlowType.caption),
          ),
      ],
    );
  }
}

/// One row in a [FlowSection]. Title + optional subtitle on the left,
/// trailing control on the right. Whole row is tappable when [onTap]
/// is provided.
class FlowSettingRow extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? leadingIcon;
  final Color? leadingIconBackground;
  final VoidCallback? onTap;

  const FlowSettingRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leadingIcon,
    this.leadingIconBackground,
    this.onTap,
  });

  @override
  State<FlowSettingRow> createState() => _FlowSettingRowState();
}

class _FlowSettingRowState extends State<FlowSettingRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // Plain Container (no animation) so hover flips instantly as the
    // cursor crosses row boundaries. See `_HotkeyRadioRowState.build`
    // for why the fade is the wrong default here.
    final content = Container(
      color: _hover && widget.onTap != null
          ? FlowTokens.bgElevatedHover
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(
        horizontal: FlowTokens.space16,
        vertical: FlowTokens.space12,
      ),
      child: Row(
        children: [
          if (widget.leadingIcon != null) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: widget.leadingIconBackground ?? FlowTokens.accent,
                borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
              ),
              child: Icon(
                widget.leadingIcon,
                size: 15,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: FlowTokens.space12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title, style: FlowType.body),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(widget.subtitle!, style: FlowType.caption),
                ],
              ],
            ),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: FlowTokens.space12),
            widget.trailing!,
          ],
        ],
      ),
    );

    if (widget.onTap == null) return content;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: content,
      ),
    );
  }
}
