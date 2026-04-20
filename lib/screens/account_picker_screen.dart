import 'package:flutter/material.dart';

import '../models/saved_account.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The "Welcome back" chooser. Shown when the user has one or more
/// accounts saved locally but no active session (e.g. after the
/// stashed access token has expired, or on first launch after the
/// user explicitly signed out).
///
/// Tapping an account fires [onAccountPicked]; the parent is
/// expected to call [AuthService.trySilentAuthWith] and either route
/// to Home (success) or to the full login screen with the email
/// pre-filled (failure). Tapping "Sign in with another account"
/// fires [onSignInWithOther].
class AccountPickerScreen extends StatefulWidget {
  final AuthService authService;
  final void Function(SavedAccount account) onAccountPicked;
  final VoidCallback onSignInWithOther;

  const AccountPickerScreen({
    super.key,
    required this.authService,
    required this.onAccountPicked,
    required this.onSignInWithOther,
  });

  @override
  State<AccountPickerScreen> createState() => _AccountPickerScreenState();
}

class _AccountPickerScreenState extends State<AccountPickerScreen> {
  List<SavedAccount> _accounts = [];
  String? _busyEmail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _accounts = StorageService.instance.savedAccounts);
  }

  Future<void> _pick(SavedAccount account) async {
    if (_busyEmail != null) return;
    setState(() => _busyEmail = account.email);
    widget.onAccountPicked(account);
  }

  Future<void> _forget(SavedAccount account) async {
    await StorageService.instance.forgetAccount(account.email);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FlowTokens.space32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Welcome back', style: FlowType.largeTitle),
                const SizedBox(height: FlowTokens.space6),
                Text(
                  'Choose an account to continue',
                  style: FlowType.body.copyWith(
                    color: FlowTokens.textSecondary,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: FlowTokens.space24),
                for (final account in _accounts) ...[
                  _AccountRow(
                    account: account,
                    busy: _busyEmail == account.email,
                    onTap: () => _pick(account),
                    onForget: () => _forget(account),
                  ),
                  const SizedBox(height: FlowTokens.space10),
                ],
                _AddAnotherAccountRow(onTap: widget.onSignInWithOther),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── One row in the list ───────────────────────────────────────────────

class _AccountRow extends StatefulWidget {
  final SavedAccount account;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onForget;

  const _AccountRow({
    required this.account,
    required this.busy,
    required this.onTap,
    required this.onForget,
  });

  @override
  State<_AccountRow> createState() => _AccountRowState();
}

class _AccountRowState extends State<_AccountRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final subtitleParts = <String>[
      if (account.name.isNotEmpty && account.name != account.email)
        account.email,
      if (account.workspace != null && account.workspace!.isNotEmpty)
        account.workspace!,
    ];
    final title = account.name.isNotEmpty ? account.name : account.email;

    return MouseRegion(
      cursor: widget.busy
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.busy ? null : widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: FlowTokens.durFast,
          curve: FlowTokens.easeStandard,
          padding: const EdgeInsets.symmetric(
            horizontal: FlowTokens.space16,
            vertical: FlowTokens.space12,
          ),
          decoration: BoxDecoration(
            color: _hover
                ? FlowTokens.hoverSurface
                : FlowTokens.bgElevated,
            borderRadius: BorderRadius.circular(FlowTokens.radiusLg),
            border: Border.all(
              color: _hover
                  ? FlowTokens.accent.withValues(alpha: 0.35)
                  : FlowTokens.glassEdge,
              width: 0.8,
            ),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: FlowTokens.contactShadow,
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              _Avatar(initials: account.initials),
              const SizedBox(width: FlowTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: FlowType.bodyStrong.copyWith(fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitleParts.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitleParts.join(' · '),
                        style: FlowType.caption.copyWith(
                          color: FlowTokens.textSecondary,
                          fontSize: 12.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: FlowTokens.space10),
              if (widget.busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: FlowTokens.accent,
                    strokeWidth: 2,
                  ),
                )
              else if (account.role != null && account.role!.isNotEmpty)
                _RoleBadge(role: account.role!),
              // Forget (x) icon — only on hover, never obscured by
              // the role badge since they sit in the same end-cap.
              if (_hover && !widget.busy) ...[
                const SizedBox(width: FlowTokens.space6),
                _ForgetButton(onTap: widget.onForget),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Circular avatar with initials over an accent gradient ─────────────

class _Avatar extends StatelessWidget {
  final String initials;

  const _Avatar({required this.initials});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [FlowTokens.accentHover, FlowTokens.accent],
        ),
        borderRadius: BorderRadius.circular(FlowTokens.radiusMd),
        boxShadow: [
          BoxShadow(
            color: FlowTokens.accent.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: FlowType.bodyStrong.copyWith(
          color: Colors.white,
          fontSize: 15,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── ADMIN / USER capsule ──────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  final String role;

  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isAdmin = role.toUpperCase() == 'ADMIN' ||
        role.toUpperCase() == 'SUPERADMIN';
    final bg = isAdmin
        ? FlowTokens.accent.withValues(alpha: 0.18)
        : FlowTokens.hoverSurface;
    final fg = isAdmin ? FlowTokens.accent : FlowTokens.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FlowTokens.space8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(FlowTokens.radiusXs),
      ),
      child: Text(
        role.toUpperCase(),
        style: FlowType.footnote.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          fontSize: 10.5,
        ),
      ),
    );
  }
}

// ── Tiny round "×" to forget an account ───────────────────────────────

class _ForgetButton extends StatefulWidget {
  final VoidCallback onTap;

  const _ForgetButton({required this.onTap});

  @override
  State<_ForgetButton> createState() => _ForgetButtonState();
}

class _ForgetButtonState extends State<_ForgetButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Tooltip(
          message: 'Forget this account',
          waitDuration: const Duration(milliseconds: 400),
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _hover
                  ? FlowTokens.systemRed.withValues(alpha: 0.20)
                  : FlowTokens.hoverSurface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close_rounded,
              size: 12,
              color: _hover
                  ? FlowTokens.systemRed
                  : FlowTokens.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── "Sign in with another account" row ────────────────────────────────

class _AddAnotherAccountRow extends StatefulWidget {
  final VoidCallback onTap;

  const _AddAnotherAccountRow({required this.onTap});

  @override
  State<_AddAnotherAccountRow> createState() =>
      _AddAnotherAccountRowState();
}

class _AddAnotherAccountRowState extends State<_AddAnotherAccountRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: FlowTokens.durFast,
          curve: FlowTokens.easeStandard,
          padding: const EdgeInsets.symmetric(
            horizontal: FlowTokens.space16,
            vertical: FlowTokens.space12,
          ),
          decoration: BoxDecoration(
            color: _hover
                ? FlowTokens.hoverSurface
                : Colors.transparent,
            borderRadius: BorderRadius.circular(FlowTokens.radiusLg),
            border: Border.all(
              color: _hover
                  ? FlowTokens.accent.withValues(alpha: 0.35)
                  : FlowTokens.strokeDivider,
              width: 0.8,
              // Dashed feel via the lighter stroke — Flutter doesn't
              // ship dashed `BoxBorder` out of the box, and a paint
              // mask here would be overkill for a single row.
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: FlowTokens.hoverSurface,
                  borderRadius:
                      BorderRadius.circular(FlowTokens.radiusMd),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.login_rounded,
                  size: 20,
                  color: FlowTokens.textSecondary,
                ),
              ),
              const SizedBox(width: FlowTokens.space12),
              Expanded(
                child: Text(
                  'Sign in with another account',
                  style: FlowType.bodyStrong.copyWith(
                    fontSize: 15,
                    color: FlowTokens.textPrimary,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: FlowTokens.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
