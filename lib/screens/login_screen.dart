import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/flow_button.dart';

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onLoggedIn;

  /// Email to seed the form with — set when the login screen is
  /// opened as a fallback from the account picker (stashed token
  /// expired, user still needs to retype the password).
  final String? initialEmail;

  /// Shown as a top-left back caret when non-null. Used to route the
  /// user back to the account picker.
  final VoidCallback? onBack;

  const LoginScreen({
    super.key,
    required this.authService,
    required this.onLoggedIn,
    this.initialEmail,
    this.onBack,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _emailController =
      TextEditingController(text: widget.initialEmail ?? '');
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Заполните все поля');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await widget.authService.login(email, password);

    if (!mounted) return;

    if (result.success) {
      widget.onLoggedIn();
    } else {
      setState(() {
        _loading = false;
        _error = result.error;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (widget.onBack != null)
            Positioned(
              top: FlowTokens.space20,
              left: FlowTokens.space20,
              child: _BackButton(onTap: widget.onBack!),
            ),
          Center(
            child: SingleChildScrollView(
          padding: const EdgeInsets.all(FlowTokens.space32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [FlowTokens.accentHover, FlowTokens.accent],
                      ),
                      borderRadius: BorderRadius.circular(FlowTokens.radiusLg),
                      boxShadow: [
                        BoxShadow(
                          color: FlowTokens.accent.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.graphic_eq_rounded,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: FlowTokens.space24),
                Text(
                  'Welcome to Flow',
                  style: FlowType.largeTitle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: FlowTokens.space6),
                Text(
                  'Sign in to continue',
                  style: FlowType.caption,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: FlowTokens.space32),

                _LoginField(
                  controller: _emailController,
                  icon: Icons.alternate_email_rounded,
                  placeholder: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: FlowTokens.space10),
                _LoginField(
                  controller: _passwordController,
                  icon: Icons.lock_outline_rounded,
                  placeholder: 'Password',
                  obscureText: true,
                  onSubmitted: (_) => _login(),
                ),

                if (_error != null) ...[
                  const SizedBox(height: FlowTokens.space12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FlowTokens.space12,
                      vertical: FlowTokens.space8,
                    ),
                    decoration: BoxDecoration(
                      color: FlowTokens.systemRed.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(FlowTokens.radiusMd),
                      border: Border.all(
                        color: FlowTokens.systemRed.withValues(alpha: 0.28),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 14,
                          color: FlowTokens.systemRed,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _error!,
                            style: FlowType.caption.copyWith(
                              color: FlowTokens.systemRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: FlowTokens.space20),
                FlowButton(
                  label: _loading ? 'Signing in…' : 'Sign In',
                  variant: FlowButtonVariant.filled,
                  size: FlowButtonSize.lg,
                  fullWidth: true,
                  onPressed: _loading ? null : _login,
                ),
              ],
            ),
          ),
        ),
          ),
        ],
      ),
    );
  }
}

// ── Top-left back caret (only shown when the login screen is a
//    fall-back from the account picker) ──────────────────────────────

class _BackButton extends StatefulWidget {
  final VoidCallback onTap;

  const _BackButton({required this.onTap});

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
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
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _hover
                ? FlowTokens.hoverSurface
                : Colors.transparent,
            borderRadius: BorderRadius.circular(FlowTokens.radiusFull),
          ),
          child: Icon(
            Icons.arrow_back_rounded,
            size: 17,
            color: FlowTokens.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Apple-style input: thin stroked capsule, no floating label, placeholder
/// reads as the field's name. On focus the border picks up the accent
/// tint plus a soft outer ring — same pattern AppKit uses for NSTextField
/// focus (`NSFocusRingType.default`), just redrawn in Flutter.
class _LoginField extends StatefulWidget {
  final TextEditingController controller;
  final IconData icon;
  final String placeholder;
  final TextInputType? keyboardType;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;

  const _LoginField({
    required this.controller,
    required this.icon,
    required this.placeholder,
    this.keyboardType,
    this.obscureText = false,
    this.onSubmitted,
  });

  @override
  State<_LoginField> createState() => _LoginFieldState();
}

class _LoginFieldState extends State<_LoginField> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() => _focused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _focused
        ? FlowTokens.accent.withValues(alpha: 0.6)
        : FlowTokens.glassEdge;

    return AnimatedContainer(
      duration: FlowTokens.durFast,
      curve: FlowTokens.easeStandard,
      decoration: BoxDecoration(
        // Recessed-well surface — a hair darker than the surrounding
        // canvas so it reads as "input slot" in both themes.
        color: FlowTokens.bgPressed,
        borderRadius: BorderRadius.circular(FlowTokens.radiusMd),
        border: Border.all(
          color: borderColor,
          width: 1.0,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: FlowTokens.accent.withValues(alpha: 0.22),
                  spreadRadius: 2,
                  blurRadius: 0,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: FlowTokens.space12),
          Icon(
            widget.icon,
            color: FlowTokens.textSecondary,
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              keyboardType: widget.keyboardType,
              obscureText: widget.obscureText,
              onSubmitted: widget.onSubmitted,
              cursorColor: FlowTokens.accent,
              style: FlowType.body.copyWith(fontSize: 14),
              decoration: InputDecoration(
                hintText: widget.placeholder,
                hintStyle: FlowType.body.copyWith(
                  fontSize: 14,
                  color: FlowTokens.textTertiary,
                ),
                isCollapsed: true,
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: FlowTokens.space12),
        ],
      ),
    );
  }
}
