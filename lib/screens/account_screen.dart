import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/flow_button.dart';
import '../widgets/flow_card.dart';
import '../widgets/flow_section.dart';
import '../widgets/flow_text_field.dart';

class AccountScreen extends StatefulWidget {
  final AuthService authService;
  final ApiService apiService;
  final VoidCallback onLogout;
  final VoidCallback onClose;

  const AccountScreen({
    super.key,
    required this.authService,
    required this.apiService,
    required this.onLogout,
    required this.onClose,
  });

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  String _plan = 'basic';
  int _wordsLimit = 2000;
  int _wordsUsed = 0;
  int _wordsTotal = 0;
  int _dictationsThisWeek = 0;
  bool _loading = true;
  bool _showManageAccount = false;
  bool _referralCopied = false;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    final data = await widget.apiService.getFlowUsage();
    if (data != null && mounted) {
      setState(() {
        _plan = data['plan'] as String? ?? 'basic';
        _wordsLimit = data['words_limit'] as int? ?? 2000;
        _wordsUsed = data['words_used_this_week'] as int? ?? 0;
        _wordsTotal = data['words_total'] as int? ?? 0;
        _dictationsThisWeek = data['dictations_this_week'] as int? ?? 0;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  String get _planDisplay {
    switch (_plan) {
      case 'free':
        return 'Flow Free';
      case 'basic':
        return 'Flow Basic';
      case 'pro':
        return 'Flow Pro';
      case 'team':
        return 'Flow Team';
      default:
        return 'Flow ${_plan[0].toUpperCase()}${_plan.substring(1)}';
    }
  }

  int get _wordsLeft => (_wordsLimit - _wordsUsed).clamp(0, _wordsLimit);
  double get _usagePercent =>
      _wordsLimit > 0 ? (_wordsLeft / _wordsLimit).clamp(0.0, 1.0) : 0;

  Color get _usageColor {
    if (_usagePercent > 0.5) return FlowTokens.systemGreen;
    if (_usagePercent > 0.2) return FlowTokens.systemOrange;
    return FlowTokens.systemRed;
  }

  void _copyReferralLink() {
    final userId =
        widget.authService.userName.toLowerCase().replaceAll(' ', '-');
    final link = 'https://flow.voiceassistant.com/invite/$userId';
    Clipboard.setData(ClipboardData(text: link));
    setState(() => _referralCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _referralCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(FlowTokens.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_showManageAccount)
                _IconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => setState(() => _showManageAccount = false),
                ),
              if (_showManageAccount) const SizedBox(width: 4),
              Text(
                _showManageAccount ? 'Manage Account' : 'Account',
                style: FlowType.title,
              ),
              const Spacer(),
              _IconButton(
                icon: Icons.close_rounded,
                onTap: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: FlowTokens.space20),

          if (_showManageAccount)
            _ManageAccountPanel(
              authService: widget.authService,
              apiService: widget.apiService,
            )
          else
            ..._buildOverview(),
        ],
      ),
    );
  }

  List<Widget> _buildOverview() {
    return [
      _ProfileCard(
        name: widget.authService.userName,
        email: widget.authService.userEmail,
      ),
      const SizedBox(height: FlowTokens.space16),
      _SubscriptionCard(
        loading: _loading,
        planDisplay: _planDisplay,
        wordsLeft: _wordsLeft,
        wordsLimit: _wordsLimit,
        usagePercent: _usagePercent,
        usageColor: _usageColor,
        dictationsThisWeek: _dictationsThisWeek,
        wordsTotal: _wordsTotal,
        showUpgrade: _plan != 'pro' && _plan != 'team',
        upgradeLabel: _plan == 'free' ? 'Get Flow Basic' : 'Get Flow Pro',
        onUpgrade: () {},
      ),
      const SizedBox(height: FlowTokens.space16),
      FlowSection(
        rows: [
          FlowSettingRow(
            leadingIcon: _referralCopied
                ? Icons.check_circle_rounded
                : Icons.person_add_alt_1_rounded,
            leadingIconBackground: FlowTokens.systemBlue,
            title: _referralCopied ? 'Link copied!' : 'Refer a friend',
            subtitle: 'Get free Pro when a friend signs up.',
            trailing: Icon(
              _referralCopied
                  ? Icons.check_rounded
                  : Icons.copy_rounded,
              size: 14,
              color: _referralCopied
                  ? FlowTokens.systemGreen
                  : FlowTokens.textTertiary,
            ),
            onTap: _copyReferralLink,
          ),
          FlowSettingRow(
            leadingIcon: Icons.manage_accounts_rounded,
            leadingIconBackground: FlowTokens.textTertiary,
            title: 'Manage account',
            subtitle: 'Edit profile and password',
            trailing: Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: FlowTokens.textTertiary,
            ),
            onTap: () => setState(() => _showManageAccount = true),
          ),
        ],
      ),
      const SizedBox(height: FlowTokens.space20),
      FlowButton(
        label: 'Sign out',
        leadingIcon: Icons.logout_rounded,
        variant: FlowButtonVariant.destructive,
        size: FlowButtonSize.md,
        fullWidth: true,
        onPressed: widget.onLogout,
      ),
    ];
  }
}

// ── Profile card ───────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final String name;
  final String email;
  const _ProfileCard({required this.name, required this.email});

  @override
  Widget build(BuildContext context) {
    return FlowCard(
      interactive: false,
      padding: const EdgeInsets.all(FlowTokens.space16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
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
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: FlowType.title.copyWith(fontSize: 18),
            ),
          ),
          const SizedBox(width: FlowTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name.isEmpty ? '—' : name, style: FlowType.bodyStrong),
                const SizedBox(height: 2),
                Text(email, style: FlowType.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Subscription card ──────────────────────────────────────────────

class _SubscriptionCard extends StatelessWidget {
  final bool loading;
  final String planDisplay;
  final int wordsLeft;
  final int wordsLimit;
  final double usagePercent;
  final Color usageColor;
  final int dictationsThisWeek;
  final int wordsTotal;
  final bool showUpgrade;
  final String upgradeLabel;
  final VoidCallback onUpgrade;

  const _SubscriptionCard({
    required this.loading,
    required this.planDisplay,
    required this.wordsLeft,
    required this.wordsLimit,
    required this.usagePercent,
    required this.usageColor,
    required this.dictationsThisWeek,
    required this.wordsTotal,
    required this.showUpgrade,
    required this.upgradeLabel,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    return FlowCard(
      interactive: false,
      padding: const EdgeInsets.all(FlowTokens.space16),
      child: loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(FlowTokens.space12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: FlowTokens.accent,
                  ),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'SUBSCRIPTION',
                      style: FlowType.footnote.copyWith(
                        color: FlowTokens.textTertiary,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: FlowTokens.accentSubtle,
                        borderRadius:
                            BorderRadius.circular(FlowTokens.radiusXs),
                      ),
                      child: Text(
                        planDisplay,
                        style: FlowType.footnote.copyWith(
                          color: FlowTokens.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FlowTokens.space10),
                Text(
                  '$wordsLeft / $wordsLimit words left this week',
                  style: FlowType.body,
                ),
                const SizedBox(height: FlowTokens.space6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: usagePercent,
                    backgroundColor: FlowTokens.bgSurface,
                    valueColor: AlwaysStoppedAnimation(usageColor),
                    minHeight: 5,
                  ),
                ),
                const SizedBox(height: FlowTokens.space12),
                Row(
                  children: [
                    _StatTile(
                      label: 'This week',
                      value: '$dictationsThisWeek',
                      suffix: 'dictations',
                    ),
                    const SizedBox(width: FlowTokens.space8),
                    _StatTile(
                      label: 'Total words',
                      value: _formatNumber(wordsTotal),
                    ),
                  ],
                ),
                if (showUpgrade) ...[
                  const SizedBox(height: FlowTokens.space12),
                  FlowButton(
                    label: upgradeLabel,
                    leadingIcon: Icons.auto_awesome_rounded,
                    variant: FlowButtonVariant.filled,
                    size: FlowButtonSize.md,
                    fullWidth: true,
                    onPressed: onUpgrade,
                  ),
                ],
              ],
            ),
    );
  }

  static String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? suffix;
  const _StatTile({required this.label, required this.value, this.suffix});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: FlowTokens.space8,
          horizontal: FlowTokens.space10,
        ),
        decoration: BoxDecoration(
          color: FlowTokens.bgSurface,
          borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
          border: Border.all(color: FlowTokens.strokeSubtle, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: FlowType.footnote.copyWith(
                color: FlowTokens.textTertiary,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, style: FlowType.bodyStrong.copyWith(fontSize: 14)),
                if (suffix != null) ...[
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      suffix!,
                      style: FlowType.caption.copyWith(fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Manage Account Panel ───────────────────────────────────────────

class _ManageAccountPanel extends StatefulWidget {
  final AuthService authService;
  final ApiService apiService;
  const _ManageAccountPanel({
    required this.authService,
    required this.apiService,
  });

  @override
  State<_ManageAccountPanel> createState() => _ManageAccountPanelState();
}

class _ManageAccountPanelState extends State<_ManageAccountPanel> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  bool _saving = false;
  String? _message;
  bool _messageIsSuccess = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.authService.userName);
    _emailController = TextEditingController(text: widget.authService.userEmail);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  void _showMessage(String text, {bool success = false}) {
    setState(() {
      _message = text;
      _messageIsSuccess = success;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _message = null);
    });
  }

  Future<void> _saveProfile() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    final ok = await widget.apiService
        .updateProfile(name: _nameController.text.trim());
    setState(() => _saving = false);
    _showMessage(ok ? 'Profile updated' : 'Failed to update profile',
        success: ok);
  }

  Future<void> _changePassword() async {
    if (_currentPasswordController.text.isEmpty ||
        _newPasswordController.text.isEmpty) {
      _showMessage('Fill in both password fields');
      return;
    }
    if (_newPasswordController.text.length < 6) {
      _showMessage('New password must be at least 6 characters');
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    final error = await widget.apiService.changePassword(
      currentPassword: _currentPasswordController.text,
      newPassword: _newPasswordController.text,
    );
    setState(() => _saving = false);
    if (error == null) {
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _showMessage('Password changed', success: true);
    } else {
      _showMessage(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlowCard(
          interactive: false,
          padding: const EdgeInsets.all(FlowTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'PROFILE',
                style: FlowType.footnote.copyWith(
                  color: FlowTokens.textTertiary,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: FlowTokens.space10),
              _LabeledField(
                label: 'Name',
                child: FlowTextField(controller: _nameController),
              ),
              const SizedBox(height: FlowTokens.space10),
              _LabeledField(
                label: 'Email',
                child: Opacity(
                  opacity: 0.6,
                  child: IgnorePointer(
                    child: FlowTextField(controller: _emailController),
                  ),
                ),
              ),
              const SizedBox(height: FlowTokens.space12),
              FlowButton(
                label: _saving ? 'Saving…' : 'Save changes',
                variant: FlowButtonVariant.filled,
                size: FlowButtonSize.md,
                fullWidth: true,
                onPressed: _saving ? null : _saveProfile,
              ),
            ],
          ),
        ),
        const SizedBox(height: FlowTokens.space16),
        FlowCard(
          interactive: false,
          padding: const EdgeInsets.all(FlowTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'CHANGE PASSWORD',
                style: FlowType.footnote.copyWith(
                  color: FlowTokens.textTertiary,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: FlowTokens.space10),
              _LabeledField(
                label: 'Current password',
                child: _passwordField(_currentPasswordController),
              ),
              const SizedBox(height: FlowTokens.space10),
              _LabeledField(
                label: 'New password',
                child: _passwordField(_newPasswordController),
              ),
              const SizedBox(height: FlowTokens.space12),
              FlowButton(
                label: 'Change password',
                variant: FlowButtonVariant.tinted,
                size: FlowButtonSize.md,
                fullWidth: true,
                onPressed: _saving ? null : _changePassword,
              ),
            ],
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: FlowTokens.space12),
          Container(
            padding: const EdgeInsets.all(FlowTokens.space10),
            decoration: BoxDecoration(
              color: (_messageIsSuccess
                      ? FlowTokens.systemGreen
                      : FlowTokens.systemRed)
                  .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(FlowTokens.radiusMd),
              border: Border.all(
                color: (_messageIsSuccess
                        ? FlowTokens.systemGreen
                        : FlowTokens.systemRed)
                    .withValues(alpha: 0.28),
                width: 0.5,
              ),
            ),
            child: Text(
              _message!,
              style: FlowType.caption.copyWith(
                color: _messageIsSuccess
                    ? FlowTokens.systemGreen
                    : FlowTokens.systemRed,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _passwordField(TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      obscureText: true,
      cursorColor: FlowTokens.accent,
      style: FlowType.body.copyWith(fontSize: 13),
      decoration: InputDecoration(
        filled: true,
        fillColor: FlowTokens.bgElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: FlowTokens.space12,
          vertical: FlowTokens.space10,
        ),
        isDense: true,
        border: _pwdBorder(FlowTokens.strokeSubtle),
        enabledBorder: _pwdBorder(FlowTokens.strokeSubtle),
        focusedBorder: _pwdBorder(
          FlowTokens.accent.withValues(alpha: 0.6),
          1.2,
        ),
      ),
    );
  }

  OutlineInputBorder _pwdBorder(Color color, [double width = 0.5]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(FlowTokens.radiusMd),
        borderSide: BorderSide(color: color, width: width),
      );
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: FlowType.caption.copyWith(fontSize: 11)),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

// ── Icon button (close / back) ─────────────────────────────────────

class _IconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconButton({required this.icon, required this.onTap});

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
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
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _hover ? FlowTokens.bgElevatedHover : Colors.transparent,
            borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
          ),
          child: Icon(
            widget.icon,
            size: 16,
            color: _hover ? FlowTokens.textPrimary : FlowTokens.textSecondary,
          ),
        ),
      ),
    );
  }
}
