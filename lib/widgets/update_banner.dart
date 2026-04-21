import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/update_service.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'flow_button.dart';

/// Thin notice bar — lives above the main content area and nudges the
/// user toward a newer Flow release.
///
/// Hooked up via [ListenableBuilder] in `AppShell`: when
/// `UpdateService.available` flips from null → non-null the builder
/// rebuilds and slides this banner into view. Clicking **Update** opens
/// the .dmg URL in the system browser (LaunchMode.externalApplication);
/// clicking **×** stashes the build number in SharedPreferences so we
/// don't keep pestering the user about the same release.
///
/// The dismiss action is hidden when ops has marked the release as
/// mandatory (`min_build > current`) — see UpdateService.isForceUpdate.
class UpdateBanner extends StatefulWidget {
  final UpdateInfo info;
  final bool forceUpdate;
  final Future<bool> Function() onUpdate;
  final VoidCallback? onDismiss;

  const UpdateBanner({
    super.key,
    required this.info,
    required this.forceUpdate,
    required this.onUpdate,
    this.onDismiss,
  });

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  bool _opening = false;

  Future<void> _handleUpdate() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onUpdate();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Accent drives the icon block on the left of the pill. Orange for
    // forced updates (non-dismissable, more urgent vibe), blue for
    // routine updates. The pill body itself stays on bgElevated — a
    // coloured wash would fight with the glass surface.
    final accent =
        widget.forceUpdate ? FlowTokens.systemOrange : FlowTokens.systemBlue;

    final headline = widget.forceUpdate
        ? 'Required update · Flow ${widget.info.version}'
        : 'Flow ${widget.info.version} is available';

    // Optional tail copy. We keep the whole banner single-line, so the
    // release notes only surface when they're short; long ones fall off
    // the end of the row with ellipsis and the user can read the full
    // list after clicking Update and opening the download page.
    final trimmedNotes = widget.info.notes.trim();
    final showNotes = trimmedNotes.isNotEmpty;

    // Floating glass pill anchored at the bottom of the content area
    // by the parent Stack. Rounded, shadowed, blurred — reads as a
    // macOS-native notification, not a Material bar. `tint` is still
    // used for the accent block on the left, not the whole surface.
    return ClipRRect(
      borderRadius: BorderRadius.circular(FlowTokens.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: FlowTokens.bgElevated.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(FlowTokens.radiusLg),
            border: Border.all(color: FlowTokens.strokeSubtle, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: FlowTokens.space16,
            vertical: FlowTokens.space12,
          ),
          child: Row(
            children: [
          // Accent dot + headline — compact like a macOS info bar.
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
            ),
            child: Icon(
              widget.forceUpdate
                  ? Icons.priority_high_rounded
                  : Icons.system_update_alt_rounded,
              size: 15,
              color: accent,
            ),
          ),
          const SizedBox(width: FlowTokens.space10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    headline,
                    style: FlowType.bodyStrong.copyWith(
                      fontSize: 13,
                      color: FlowTokens.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (showNotes) ...[
                  const SizedBox(width: FlowTokens.space8),
                  Flexible(
                    child: Text(
                      trimmedNotes,
                      style: FlowType.caption.copyWith(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: FlowTokens.space12),
          FlowButton(
            label: _opening ? 'Opening…' : 'Update',
            variant: FlowButtonVariant.filled,
            size: FlowButtonSize.sm,
            onPressed: _opening ? null : _handleUpdate,
          ),
          if (widget.onDismiss != null) ...[
            const SizedBox(width: FlowTokens.space4),
            // Skip-for-this-version button. Exactly mirrors ErrorBanner's
            // close affordance so it reads as the same kind of control
            // rather than a second CTA.
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDismiss,
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: FlowTokens.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
        ),
      ),
    );
  }
}
