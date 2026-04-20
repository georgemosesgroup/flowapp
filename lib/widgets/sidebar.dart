import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'flow_button.dart';

enum NavItem { home, dictionary, snippets, style, scratchpad, settings }

class Sidebar extends StatelessWidget {
  final NavItem selected;
  final ValueChanged<NavItem> onSelect;
  final String userName;
  final String plan;
  final VoidCallback onAccountTap;
  /// Called when the user clicks the collapse/expand chevron.
  /// When null the chevron is hidden.
  final VoidCallback? onCollapse;
  /// When true, sidebar renders in icon-only mini mode (~60 px wide).
  final bool collapsed;

  const Sidebar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.userName,
    required this.plan,
    required this.onAccountTap,
    this.onCollapse,
    this.collapsed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // Floating pane with a thin gap to every edge. The native
      // traffic-lights are repositioned in Swift
      // (MainFlutterWindow.swift) to sit inside this top padding.
      margin: const EdgeInsets.fromLTRB(
        FlowTokens.space8,
        FlowTokens.space8,
        0,
        FlowTokens.space8,
      ),
      width: collapsed ? 78 : 220,
      decoration: BoxDecoration(
        // Glass-pane treatment: a translucent top→bottom gradient plus
        // a bright edge. Sits over the already-dimmed body so the
        // "two glass panes stacked" look reads without needing a real
        // BackdropFilter (no-op on our translucent NSWindow).
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            FlowTokens.sidebarFillTop,
            FlowTokens.sidebarFillBottom,
          ],
        ),
        borderRadius: BorderRadius.circular(FlowTokens.radiusXl),
        border: Border.all(color: FlowTokens.sidebarEdge, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: FlowTokens.sidebarShadow,
            offset: const Offset(0, 6),
            blurRadius: 18,
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FlowTokens.radiusXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag/titlebar strip: leaves room for the native traffic
            // lights that NSWindow renders at (~12, 12) inside this
            // pane, then the brand row below them. Double-click
            // toggles zoom (same as the native macOS titlebar
            // double-click gesture).
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: () {
                const MethodChannel('com.voiceassistant/window')
                    .invokeMethod('zoom');
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top strip: native traffic lights are positioned
                  // inside this row by Swift at x≈20. We right-align a
                  // collapse chevron in the same strip so the window
                  // controls and the sidebar toggle share one clean
                  // horizontal band.
                  // Top strip: native traffic lights are placed by
                  // Swift at x≈20/40/60. In expanded mode we also
                  // right-align a collapse chevron in this same strip
                  // so everything lives on one horizontal band. In
                  // collapsed mode the chevron is drawn outside the
                  // pane by AppShell (no room for it here).
                  SizedBox(
                    height: 38,
                    child: collapsed
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(
                              right: FlowTokens.space10,
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 78),
                                const Spacer(),
                                if (onCollapse != null)
                                  _SidebarIconButton(
                                    icon: Icons.keyboard_tab_rounded,
                                    tooltip: 'Collapse sidebar',
                                    flipHorizontally: true,
                                    onTap: onCollapse!,
                                  ),
                              ],
                            ),
                          ),
                  ),
                  _brand(plan),
                ],
              ),
            ),
            if (collapsed && onCollapse != null) ...[
              const SizedBox(height: FlowTokens.space10),
              // Matches `_SidebarNavButton.compact` treatment so the
              // expand chevron reads as a proper nav tile, not a
              // bolted-on widget above the group.
              _SidebarNavTile(
                icon: Icons.keyboard_tab_rounded,
                tooltip: 'Expand sidebar',
                flipHorizontally: false,
                onTap: onCollapse!,
              ),
              const SizedBox(height: FlowTokens.space6),
            ] else
              const SizedBox(height: FlowTokens.space16),
            _navGroup(),
            const Spacer(),
            // Upgrade card collapses to zero-height when compact. The
            // AnimatedSize + FadeTransition combo slides the nav stack
            // downward smoothly rather than popping.
            AnimatedCrossFade(
              firstChild: const SizedBox(
                height: 0,
                width: double.infinity,
              ),
              secondChild: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _upgradeCard(),
                  const SizedBox(height: FlowTokens.space8),
                ],
              ),
              crossFadeState: collapsed
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: FlowTokens.durBase,
              firstCurve: FlowTokens.easeStandard,
              secondCurve: FlowTokens.easeStandard,
              sizeCurve: FlowTokens.easeStandard,
            ),
            _SidebarNavButton(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              label: 'Settings',
              isSelected: selected == NavItem.settings,
              compact: collapsed,
              onTap: () => onSelect(NavItem.settings),
            ),
            const SizedBox(height: FlowTokens.space4),
            _accountRow(),
            const SizedBox(height: FlowTokens.space10),
          ],
        ),
      ),
    );
  }

  Widget _brand(String plan) {
    final logo = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [FlowTokens.accentHover, FlowTokens.accent],
        ),
        borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
        boxShadow: [
          BoxShadow(
            color: FlowTokens.accent.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(Icons.graphic_eq_rounded,
          color: Colors.white, size: 16),
    );

    // Single tree + AnimatedAlign so the logo glides left↔center as
    // the sidebar collapses. The wordmark + plan badge slide/fade in
    // beside it via AnimatedSize + AnimatedOpacity. No cross-fade, no
    // position snap.
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: FlowTokens.space10),
        Text(
          'Flow',
          style: FlowType.title.copyWith(fontSize: 17),
        ),
        const SizedBox(width: FlowTokens.space12),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: FlowTokens.space6,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: FlowTokens.bgElevated,
            borderRadius: BorderRadius.circular(FlowTokens.radiusXs),
            border: Border.all(color: FlowTokens.strokeSubtle, width: 0.5),
          ),
          child: Text(
            plan.toUpperCase(),
            style: FlowType.footnote.copyWith(
              fontSize: 9,
              color: FlowTokens.textTertiary,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ],
    );

    return AnimatedAlign(
      alignment: collapsed ? Alignment.center : Alignment.centerLeft,
      duration: FlowTokens.durBase,
      curve: FlowTokens.easeStandard,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 0 : FlowTokens.space16,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            logo,
            ClipRect(
              child: AnimatedSize(
                duration: FlowTokens.durBase,
                curve: FlowTokens.easeStandard,
                alignment: Alignment.centerLeft,
                child: AnimatedOpacity(
                  duration: FlowTokens.durBase,
                  curve: FlowTokens.easeStandard,
                  opacity: collapsed ? 0.0 : 1.0,
                  child: collapsed
                      ? const SizedBox(width: 0, height: 28)
                      : trailing,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navGroup() {
    return Column(
      children: [
        _SidebarNavButton(
          icon: Icons.house_outlined,
          activeIcon: Icons.house,
          label: 'Home',
          isSelected: selected == NavItem.home,
          compact: collapsed,
          onTap: () => onSelect(NavItem.home),
        ),
        _SidebarNavButton(
          icon: Icons.menu_book_outlined,
          activeIcon: Icons.menu_book,
          label: 'Dictionary',
          isSelected: selected == NavItem.dictionary,
          compact: collapsed,
          onTap: () => onSelect(NavItem.dictionary),
        ),
        _SidebarNavButton(
          icon: Icons.bolt_outlined,
          activeIcon: Icons.bolt,
          label: 'Snippets',
          isSelected: selected == NavItem.snippets,
          compact: collapsed,
          onTap: () => onSelect(NavItem.snippets),
        ),
        _SidebarNavButton(
          icon: Icons.text_fields_outlined,
          activeIcon: Icons.text_fields,
          label: 'Style',
          isSelected: selected == NavItem.style,
          compact: collapsed,
          onTap: () => onSelect(NavItem.style),
        ),
        _SidebarNavButton(
          icon: Icons.edit_note_outlined,
          activeIcon: Icons.edit_note,
          label: 'Scratchpad',
          isSelected: selected == NavItem.scratchpad,
          compact: collapsed,
          onTap: () => onSelect(NavItem.scratchpad),
        ),
      ],
    );
  }

  Widget _upgradeCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FlowTokens.space10),
      child: Container(
        padding: const EdgeInsets.all(FlowTokens.space10),
        decoration: BoxDecoration(
          color: FlowTokens.hoverSurface, // neutral — no more pink bar
          borderRadius: BorderRadius.circular(FlowTokens.radiusMd),
          border: Border.all(
            color: FlowTokens.strokeSubtle,
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 12,
                  color: FlowTokens.accent,
                ),
                const SizedBox(width: 5),
                Text(
                  'Flow Pro',
                  style: FlowType.bodyStrong.copyWith(
                    fontSize: 11.5,
                    color: FlowTokens.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Unlimited words & Pro features.',
              style: FlowType.footnote.copyWith(
                fontSize: 10.5,
                color: FlowTokens.textTertiary,
              ),
            ),
            const SizedBox(height: FlowTokens.space8),
            FlowButton(
              label: 'Upgrade',
              size: FlowButtonSize.sm,
              fullWidth: true,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountRow() {
    return _SidebarAccountRow(
      name: userName.isEmpty ? 'Sign in' : userName,
      compact: collapsed,
      onTap: onAccountTap,
    );
  }
}

class _SidebarNavButton extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final bool compact;
  final VoidCallback onTap;

  const _SidebarNavButton({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<_SidebarNavButton> createState() => _SidebarNavButtonState();
}

class _SidebarNavButtonState extends State<_SidebarNavButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;

    // Apple-style sidebar: active is a soft neutral tint (NOT accent),
    // hover is faint white overlay. Text stays primary/secondary — no
    // colored labels. This matches Finder, Mail, Notes, Reminders.
    final bg = isSelected
        ? FlowTokens.navActive
        : _hover
            ? FlowTokens.navHover
            : Colors.transparent;

    final fg = isSelected
        ? FlowTokens.textPrimary
        : _hover
            ? FlowTokens.textPrimary
            : FlowTokens.textSecondary;

    final iconWidget = Icon(
      isSelected ? widget.activeIcon : widget.icon,
      size: 18,
      color: fg,
    );

    // One unified tree, no cross-fade. The icon stays as a single
    // widget while the label's box animates from its natural width to
    // zero (AnimatedSize + ClipRect) and the pill slides from
    // centerLeft to center (AnimatedAlign). Net effect: the icon
    // glides left→center smoothly as the sidebar collapses, instead of
    // teleporting between two fixed positions.
    final label = Padding(
      padding: const EdgeInsets.only(
        left: FlowTokens.space10,
        right: 4,
      ),
      child: Text(
        widget.label,
        maxLines: 1,
        overflow: TextOverflow.clip,
        softWrap: false,
        style: FlowType.body.copyWith(
          fontSize: 13,
          color: fg,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );

    Widget pill = AnimatedContainer(
      duration: FlowTokens.durBase,
      curve: FlowTokens.easeStandard,
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 9 : FlowTokens.space10,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget,
          // Label collapses to zero width + zero opacity when compact.
          // ClipRect prevents the shrinking text from bleeding outside
          // the pill during the animation.
          ClipRect(
            child: AnimatedSize(
              duration: FlowTokens.durBase,
              curve: FlowTokens.easeStandard,
              alignment: Alignment.centerLeft,
              child: AnimatedOpacity(
                duration: FlowTokens.durBase,
                curve: FlowTokens.easeStandard,
                opacity: widget.compact ? 0.0 : 1.0,
                child: widget.compact
                    ? const SizedBox(width: 0, height: 18)
                    : label,
              ),
            ),
          ),
        ],
      ),
    );

    // Tooltip only in compact mode — in expanded mode the label is
    // visible so an extra tooltip would be noise.
    if (widget.compact) {
      pill = Tooltip(
        message: widget.label,
        waitDuration: const Duration(milliseconds: 400),
        child: pill,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FlowTokens.space8,
        vertical: 2,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          // AnimatedAlign slides the (now variable-width) pill between
          // the expanded left-align and the compact center-align. This
          // is the key to "icon glides" instead of "icon teleports".
          child: AnimatedAlign(
            alignment: widget.compact
                ? Alignment.center
                : Alignment.centerLeft,
            duration: FlowTokens.durBase,
            curve: FlowTokens.easeStandard,
            child: pill,
          ),
        ),
      ),
    );
  }
}

class _SidebarAccountRow extends StatefulWidget {
  final String name;
  final bool compact;
  final VoidCallback onTap;
  const _SidebarAccountRow({
    required this.name,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<_SidebarAccountRow> createState() => _SidebarAccountRowState();
}

class _SidebarAccountRowState extends State<_SidebarAccountRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            FlowTokens.systemBlue.withValues(alpha: 0.9),
            FlowTokens.accent.withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(FlowTokens.radiusFull),
      ),
      alignment: Alignment.center,
      child: Text(
        widget.name[0].toUpperCase(),
        style: FlowType.bodyStrong.copyWith(fontSize: 12),
      ),
    );

    // Same unified tree + AnimatedAlign pattern as `_SidebarNavButton`:
    // the avatar glides from left to center as the pill shrinks, no
    // double-vision from a cross-fade.
    final trailing = Padding(
      padding: const EdgeInsets.only(left: FlowTokens.space10, right: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              widget.name,
              style: FlowType.body.copyWith(fontSize: 12),
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: FlowTokens.space6),
          Icon(
            Icons.chevron_right,
            size: 14,
            color: FlowTokens.textTertiary,
          ),
        ],
      ),
    );

    Widget pill = AnimatedContainer(
      duration: FlowTokens.durBase,
      curve: FlowTokens.easeStandard,
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 5 : FlowTokens.space8,
        vertical: widget.compact ? 3 : FlowTokens.space8,
      ),
      decoration: BoxDecoration(
        color: _hover
            ? (widget.compact
                ? FlowTokens.navHover
                : FlowTokens.hoverSurface)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          ClipRect(
            child: AnimatedSize(
              duration: FlowTokens.durBase,
              curve: FlowTokens.easeStandard,
              alignment: Alignment.centerLeft,
              child: AnimatedOpacity(
                duration: FlowTokens.durBase,
                curve: FlowTokens.easeStandard,
                opacity: widget.compact ? 0.0 : 1.0,
                child: widget.compact
                    ? const SizedBox(width: 0, height: 26)
                    : trailing,
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.compact) {
      pill = Tooltip(
        message: widget.name,
        waitDuration: const Duration(milliseconds: 400),
        child: pill,
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? FlowTokens.space8 : FlowTokens.space10,
        vertical: 2,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedAlign(
            alignment: widget.compact
                ? Alignment.center
                : Alignment.centerLeft,
            duration: FlowTokens.durBase,
            curve: FlowTokens.easeStandard,
            child: pill,
          ),
        ),
      ),
    );
  }
}

// ── Full-size nav tile used for single-icon affordances in the
//    collapsed sidebar (expand chevron, etc). Visually identical to
//    `_SidebarNavButton.compact` so it stacks cleanly with nav items.

class _SidebarNavTile extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool flipHorizontally;

  const _SidebarNavTile({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.flipHorizontally = false,
  });

  @override
  State<_SidebarNavTile> createState() => _SidebarNavTileState();
}

class _SidebarNavTileState extends State<_SidebarNavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(
      widget.icon,
      size: 18,
      color: _hover ? FlowTokens.textPrimary : FlowTokens.textSecondary,
    );

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Center(
              child: AnimatedContainer(
                duration: FlowTokens.durFast,
                curve: FlowTokens.easeStandard,
                width: 36,
                height: 32,
                decoration: BoxDecoration(
                  color: _hover ? FlowTokens.navHover : Colors.transparent,
                  borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
                ),
                alignment: Alignment.center,
                child: widget.flipHorizontally
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.rotationY(3.14159),
                        child: iconWidget,
                      )
                    : iconWidget,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Small icon button used in the sidebar top-strip ────────────────

class _SidebarIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool flipHorizontally;

  const _SidebarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.flipHorizontally = false,
  });

  @override
  State<_SidebarIconButton> createState() => _SidebarIconButtonState();
}

class _SidebarIconButtonState extends State<_SidebarIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(
      widget.icon,
      size: 14,
      color: _hover ? FlowTokens.textPrimary : FlowTokens.textSecondary,
    );

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
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: _hover
                  ? FlowTokens.hoverSurface
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(FlowTokens.radiusFull),
            ),
            alignment: Alignment.center,
            child: widget.flipHorizontally
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.rotationY(3.14159),
                    child: iconWidget,
                  )
                : iconWidget,
          ),
        ),
      ),
    );
  }
}
