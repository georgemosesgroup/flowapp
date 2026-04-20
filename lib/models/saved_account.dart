/// A previously-signed-in account, ready to be picked from the
/// "Welcome back" chooser. Tokens (access + refresh) live in secure
/// storage keyed by [email]; this model only carries the public bits
/// we want to show in the UI.
class SavedAccount {
  /// Primary key — the email address used to sign in.
  final String email;

  /// Display name (falls back to [email] when empty).
  final String name;

  /// Workspace/company name the account belongs to (optional).
  final String? workspace;

  /// Role label — typically "ADMIN" or "USER", uppercased for the
  /// badge in the picker.
  final String? role;

  /// Server URL the account was signed in to. Keeps us honest when a
  /// user has accounts on multiple Flow environments (staging vs
  /// production vs self-hosted).
  final String serverUrl;

  /// When the user last signed in with this account. Used for sort
  /// order in the picker (most-recent first) and a subtle "Active N
  /// hours ago" label on hover.
  final DateTime lastUsedAt;

  const SavedAccount({
    required this.email,
    required this.name,
    required this.serverUrl,
    required this.lastUsedAt,
    this.workspace,
    this.role,
  });

  /// Shown as the first/second letter avatar when no workspace icon
  /// is available. Grabs the first letter of the first word + first
  /// letter of the last word of [name]; falls back to the first two
  /// letters of [email] before the `@` otherwise.
  String get initials {
    final source = name.trim().isEmpty ? email.split('@').first : name.trim();
    final parts = source
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final s = parts.first;
      return s.length >= 2
          ? s.substring(0, 2).toUpperCase()
          : s.substring(0, 1).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  SavedAccount copyWith({
    String? name,
    String? workspace,
    String? role,
    String? serverUrl,
    DateTime? lastUsedAt,
  }) {
    return SavedAccount(
      email: email,
      name: name ?? this.name,
      workspace: workspace ?? this.workspace,
      role: role ?? this.role,
      serverUrl: serverUrl ?? this.serverUrl,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        'name': name,
        if (workspace != null) 'workspace': workspace,
        if (role != null) 'role': role,
        'server_url': serverUrl,
        'last_used_at': lastUsedAt.toIso8601String(),
      };

  factory SavedAccount.fromJson(Map<String, dynamic> json) {
    return SavedAccount(
      email: (json['email'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      workspace: json['workspace']?.toString(),
      role: json['role']?.toString(),
      serverUrl: (json['server_url'] ?? '').toString(),
      lastUsedAt: DateTime.tryParse((json['last_used_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
