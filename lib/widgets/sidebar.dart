import 'dart:ui' show lerpDouble;

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
      //
      // width = double.infinity so the inner pane tracks the outer
      // AnimatedContainer's tween exactly. If this had a hardcoded
      // width (78 or 220), the inner pane would snap instantly to the
      // new value while the outer width was still animating, leaving
      // an empty gap on the right during the transition.
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        FlowTokens.space8,
        FlowTokens.space8,
        0,
        FlowTokens.space8,
      ),
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
                    // Just right-align the collapse chevron — no Row
                    // with a fixed 78 px traffic-light placeholder,
                    // which was the source of "RIGHT OVERFLOWED" while
                    // the sidebar was still tweening wider during the
                    // compact→expanded transition. Swift pins the
                    // native traffic-lights over this strip regardless
                    // of any Flutter widget underneath, so we don't
                    // need to reserve space for them in the layout.
                    child: collapsed
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(
                              right: FlowTokens.space10,
                            ),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: onCollapse != null
                                  ? _SidebarIconButton(
                                      icon: Icons.keyboard_tab_rounded,
                                      tooltip: 'Collapse sidebar',
                                      flipHorizontally: true,
                                      onTap: onCollapse!,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                  ),
                  _brand(plan),
                ],
              ),
            ),
            // Expand chevron only belongs in collapsed mode (the
            // collapse chevron lives in the top strip instead).
            // AnimatedSize smooths the height swap between the taller
            // "space10 + tile + space6" slot and the shorter
            // "space16" spacer so the nav group doesn't pop up/down.
            AnimatedSize(
              duration: FlowTokens.durSidebar,
              curve: FlowTokens.easeSidebar,
              alignment: Alignment.topCenter,
              child: (collapsed && onCollapse != null)
                  ? Column(
                      key: const ValueKey('expand-chevron-slot'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: FlowTokens.space10),
                        _SidebarNavTile(
                          icon: Icons.keyboard_tab_rounded,
                          tooltip: 'Expand sidebar',
                          flipHorizontally: false,
                          onTap: onCollapse!,
                        ),
                        const SizedBox(height: FlowTokens.space6),
                      ],
                    )
                  : const SizedBox(
                      key: ValueKey('expand-chevron-empty'),
                      height: FlowTokens.space16,
                      width: double.infinity,
                    ),
            ),
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
              duration: FlowTokens.durSidebar,
              firstCurve: FlowTokens.easeSidebar,
              secondCurve: FlowTokens.easeSidebar,
              sizeCurve: FlowTokens.easeSidebar,
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
    return _SidebarBrand(plan: plan, collapsed: collapsed);
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

class _SidebarNavButtonState extends State<_SidebarNavButton>
    with SingleTickerProviderStateMixin {
  // One controller drives ALL interpolation for this button. Multiple
  // implicit AnimatedX widgets (AnimatedAlign + AnimatedContainer +
  // AnimatedSize + AnimatedOpacity) each spin up their own ticker, and
  // those tickers can drift by a frame relative to one another — that
  // shows up as visible jerk during collapse/expand. Binding every
  // interpolated property to a single `_t` removes the drift.
  late final AnimationController _ctrl;
  late final Animation<double> _t;
  bool _hover = false;

  // Pill widths are hardcoded to match the sidebar's known widths:
  //   expanded: sidebar 220 − margin-left 8 − outer padding h:8×2 = 196
  //   compact:  fixed 36 (icon-only pill shared with account row + tile)
  static const double _pillWExpanded = 196;
  static const double _pillWCompact = 36;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: FlowTokens.durSidebar,
      value: widget.compact ? 1.0 : 0.0,
    );
    _t = CurvedAnimation(parent: _ctrl, curve: FlowTokens.easeSidebar);
  }

  @override
  void didUpdateWidget(_SidebarNavButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.compact != oldWidget.compact) {
      if (widget.compact) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

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

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FlowTokens.space8,
        vertical: 2,
      ),
      // SizedBox pins the row height so the Align inside the
      // AnimatedBuilder has a bounded vertical constraint. Without
      // this, each tile claims the full parent height (the Column
      // hands out loose 0..parent constraints), which stacks to
      // multiple times the Scaffold height and trips the yellow/black
      // "Infinity PIXELS" overflow indicator at the bottom.
      child: SizedBox(
        height: 32,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedBuilder(
              animation: _t,
              builder: (context, _) {
                final t = _t.value;
                // Opacity fades faster than width so the label reaches 0
                // alpha before the pill gets narrow enough for ghost
                // glyphs to pop out the right edge.
                final labelOpacity = (1.0 - t * 1.6).clamp(0.0, 1.0);
                final pillWidth =
                    lerpDouble(_pillWExpanded, _pillWCompact, t)!;

                Widget pill = Container(
                  width: pillWidth,
                  height: 32,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 8,
                  ),
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius:
                        BorderRadius.circular(FlowTokens.radiusSm),
                  ),
                  child: Row(
                    children: [
                      iconWidget,
                      Expanded(
                        child: Opacity(
                          opacity: labelOpacity,
                          child: label,
                        ),
                      ),
                    ],
                  ),
                );

                if (widget.compact) {
                  pill = Tooltip(
                    message: widget.label,
                    waitDuration: const Duration(milliseconds: 400),
                    child: pill,
                  );
                }

                return Align(
                  alignment: Alignment.lerp(
                    Alignment.centerLeft,
                    Alignment.center,
                    t,
                  )!,
                  child: pill,
                );
              },
            ),
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

class _SidebarAccountRowState extends State<_SidebarAccountRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;
  bool _hover = false;

  // Pill widths — same geometry as `_SidebarNavButton` so the bottom
  // account tile lines up with the nav stack when collapsed.
  static const double _pillWExpanded = 196;
  static const double _pillWCompact = 36;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: FlowTokens.durSidebar,
      value: widget.compact ? 1.0 : 0.0,
    );
    _t = CurvedAnimation(parent: _ctrl, curve: FlowTokens.easeSidebar);
  }

  @override
  void didUpdateWidget(_SidebarAccountRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.compact != oldWidget.compact) {
      if (widget.compact) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

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

    final trailing = Padding(
      padding: const EdgeInsets.only(left: FlowTokens.space10, right: 2),
      child: Row(
        children: [
          Expanded(
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

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FlowTokens.space8,
        vertical: 2,
      ),
      // Bounded-height slot — see `_SidebarNavButtonState.build` for
      // why Align needs a hard ceiling here.
      child: SizedBox(
        height: 36,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedBuilder(
              animation: _t,
              builder: (context, _) {
                final t = _t.value;
                final trailingOpacity = (1.0 - t * 1.6).clamp(0.0, 1.0);
                final pillWidth =
                    lerpDouble(_pillWExpanded, _pillWCompact, t)!;

                Widget pill = Container(
                  width: pillWidth,
                  height: 36,
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 3,
                ),
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: _hover
                      ? FlowTokens.hoverSurface
                      : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(FlowTokens.radiusSm),
                ),
                child: Row(
                  children: [
                    avatar,
                    Expanded(
                      child: Opacity(
                        opacity: trailingOpacity,
                        child: trailing,
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

              return Align(
                alignment: Alignment.lerp(
                  Alignment.centerLeft,
                  Alignment.center,
                  t,
                )!,
                child: pill,
              );
            },
          ),
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

// ── Brand row (logo + "Flow" wordmark + plan badge) ─────────────────
//
// Same single-controller pattern as `_SidebarNavButton`. The logo
// glides from left to center while the wordmark + plan badge shrink
// away in-sync with the sidebar width tween driven by AppShell.

class _SidebarBrand extends StatefulWidget {
  final String plan;
  final bool collapsed;

  const _SidebarBrand({required this.plan, required this.collapsed});

  @override
  State<_SidebarBrand> createState() => _SidebarBrandState();
}

class _SidebarBrandState extends State<_SidebarBrand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;

  // Natural widths of the brand content measured empirically:
  //   expanded ≈ logo 28 + space10 + "Flow" ~48 + space12 + badge ~45
  //             ≈ 145; round up to 160 to avoid clipping the badge
  //             outline on alt fonts.
  //   compact  = just the logo (28×28).
  // The outer Padding(h:space16 ↔ 0) shrinks the available slot
  // alongside this; both tweens are driven by the same `_t`.
  static const double _contentWExpanded = 160;
  static const double _contentWCompact = 28;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: FlowTokens.durSidebar,
      value: widget.collapsed ? 1.0 : 0.0,
    );
    _t = CurvedAnimation(parent: _ctrl, curve: FlowTokens.easeSidebar);
  }

  @override
  void didUpdateWidget(_SidebarBrand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapsed != oldWidget.collapsed) {
      if (widget.collapsed) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      child: const Icon(
        Icons.graphic_eq_rounded,
        color: Colors.white,
        size: 16,
      ),
    );

    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: FlowTokens.space10),
        Text('Flow', style: FlowType.title.copyWith(fontSize: 17)),
        const SizedBox(width: FlowTokens.space12),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: FlowTokens.space6,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: FlowTokens.bgElevated,
            borderRadius: BorderRadius.circular(FlowTokens.radiusXs),
            border: Border.all(
              color: FlowTokens.strokeSubtle,
              width: 0.5,
            ),
          ),
          child: Text(
            widget.plan.toUpperCase(),
            style: FlowType.footnote.copyWith(
              fontSize: 9,
              color: FlowTokens.textTertiary,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ],
    );

    // Height pin — same story as `_SidebarNavButtonState.build`: the
    // inner Align would claim the full Column height otherwise.
    return SizedBox(
      height: 28,
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final t = _t.value;
          final trailingOpacity = (1.0 - t * 1.6).clamp(0.0, 1.0);
          final contentWidth =
              lerpDouble(_contentWExpanded, _contentWCompact, t)!;

          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: lerpDouble(FlowTokens.space16, 0, t)!,
            ),
            child: Align(
              alignment: Alignment.lerp(
                Alignment.centerLeft,
                Alignment.center,
                t,
              )!,
              child: SizedBox(
                width: contentWidth,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    maxWidth: _contentWExpanded,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        logo,
                        Opacity(
                          opacity: trailingOpacity,
                          child: trailing,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
