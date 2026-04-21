import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';
import '../theme/tokens.dart';
import 'flow_toast.dart';

/// Wraps [child] with a native macOS menu bar — the `[Apple] Flow /
/// Window / Help` strip along the top of the screen.
///
/// On non-macOS platforms PlatformMenuBar is a no-op and falls through
/// to [child], so it's safe to keep mounted even if we ever ship an
/// iOS / Windows build of the same codebase.
///
/// Pattern notes:
/// - macOS automatically synthesises Edit (Cut/Copy/Paste/Select All)
///   when a text field has focus, so we don't declare an Edit menu
///   and let the OS own the shortcuts.
/// - "Check for Updates…" calls [UpdateService.checkNow] via a static
///   handle on the service; null-safe, no-ops before login.
/// - About dialog renders via [showAboutDialog]; we use the navigator
///   key passed in from [FlowApp] because menu callbacks have no
///   BuildContext of their own.
class FlowMenuBar extends StatelessWidget {
  const FlowMenuBar({
    required this.child,
    required this.navigatorKey,
    super.key,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: <PlatformMenuItem>[
        // ── Flow ────────────────────────────────────────────
        PlatformMenu(
          label: 'Flow',
          menus: [
            PlatformMenuItem(
              label: 'About Flow',
              onSelected: _showAbout,
            ),
            PlatformMenuItem(
              label: 'Check for Updates…',
              onSelected: _checkForUpdates,
            ),
            const PlatformMenuItemGroup(members: [
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.servicesSubmenu,
              ),
            ]),
            const PlatformMenuItemGroup(members: [
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.hide,
              ),
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.hideOtherApplications,
              ),
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.showAllApplications,
              ),
            ]),
            const PlatformMenuItemGroup(members: [
              PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.quit,
              ),
            ]),
          ],
        ),
        // ── Window ──────────────────────────────────────────
        const PlatformMenu(
          label: 'Window',
          menus: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
          ],
        ),
        // ── Help ────────────────────────────────────────────
        PlatformMenu(
          label: 'Help',
          menus: [
            PlatformMenuItem(
              label: 'Flow Website',
              onSelected: () => _open('https://flow.mosesdev.com'),
            ),
            PlatformMenuItem(
              label: 'Send Feedback…',
              onSelected: () => _open(
                'mailto:gevmoses@gmail.com?subject=Flow%20feedback',
              ),
            ),
          ],
        ),
      ],
      child: child,
    );
  }

  Future<void> _checkForUpdates() async {
    final service = UpdateService.current;
    // navigatorKey.currentContext points at the Navigator widget, but
    // our Overlay lives *inside* that Navigator — Overlay.maybeOf from
    // the Navigator's own context returns null and FlowToast silently
    // becomes a no-op. Grab the OverlayState.context instead: it's a
    // descendant of the Overlay, so look-ups resolve correctly.
    final overlayCtx = navigatorKey.currentState?.overlay?.context;
    if (service == null || overlayCtx == null) return;

    FlowToast.info(
      overlayCtx,
      'Checking for updates\u2026',
      duration: const Duration(seconds: 2),
    );

    await service.checkNow();

    final freshCtx = navigatorKey.currentState?.overlay?.context;
    if (freshCtx == null) return;
    // freshCtx is re-fetched after the await from the live Overlay,
    // so it reflects the current tree — the lint can't prove that.
    if (service.available == null) {
      final v = service.currentVersion.isNotEmpty
          ? ' (${service.currentVersion})'
          : '';
      // ignore: use_build_context_synchronously
      FlowToast.success(freshCtx, 'You\u2019re up to date$v');
    } else {
      // Banner also surfaces the prompt; toast just confirms the check
      // landed in case the user's eyes were on the menu bar.
      final msg = 'Flow ${service.available!.version} is available';
      // ignore: use_build_context_synchronously
      FlowToast.info(freshCtx, msg, duration: const Duration(seconds: 3));
    }
  }

  Future<void> _showAbout() async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    String versionLine = 'Flow';
    try {
      final info = await PackageInfo.fromPlatform();
      versionLine = '${info.version} (${info.buildNumber})';
    } catch (_) {
      // Package info failure is cosmetic — fall back to name-only.
    }

    if (!context.mounted) return;
    showAboutDialog(
      context: context,
      applicationName: 'Flow',
      applicationVersion: versionLine,
      applicationIcon: _AboutIcon(),
      applicationLegalese: '© 2026 George Moses',
      children: const [
        Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'macOS dictation app. Press a global hotkey anywhere on '
            'your Mac, speak, release — recognised text lands in the '
            'focused window. Multi-language, local dictionary, '
            'reusable snippets.',
          ),
        ),
      ],
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Silently ignore — the menu item isn't a critical path.
    }
  }
}

/// App icon for the About dialog. Uses the Flow brand mic glyph on
/// the accent background rather than loading the .icns asset — keeps
/// the dialog rendering even in scenarios where the icon file isn't
/// bundled (e.g. web / unit tests).
class _AboutIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: FlowTokens.accent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(
        Icons.graphic_eq,
        color: Colors.white,
        size: 36,
      ),
    );
  }
}
