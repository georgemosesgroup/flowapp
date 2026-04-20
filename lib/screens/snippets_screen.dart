import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/flow_button.dart';
import '../widgets/flow_card.dart';
import '../widgets/flow_dialog.dart';
import '../widgets/flow_search_field.dart';
import '../widgets/flow_text_field.dart';
import '../widgets/toolbar_inset.dart';

class SnippetsScreen extends StatefulWidget {
  final ApiService apiService;
  const SnippetsScreen({super.key, required this.apiService});

  @override
  State<SnippetsScreen> createState() => _SnippetsScreenState();
}

class _SnippetsScreenState extends State<SnippetsScreen> {
  List<Map<String, dynamic>> _snippets = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.apiService.getSnippets();
    if (mounted) setState(() { _snippets = items; _loading = false; });
  }

  void _showAddDialog() {
    final triggerCtrl = TextEditingController();
    final expansionCtrl = TextEditingController();

    Future<void> submit() async {
      if (triggerCtrl.text.trim().isEmpty ||
          expansionCtrl.text.trim().isEmpty) {
        return;
      }
      if (mounted) Navigator.of(context).pop();
      await widget.apiService.addSnippet(
        triggerPhrase: triggerCtrl.text.trim(),
        expansion: expansionCtrl.text.trim(),
      );
      _load();
    }

    showFlowDialog<void>(
      context: context,
      dialog: FlowDialog(
        title: 'New snippet',
        subtitle:
            'Pick a short trigger phrase Flow expands into the longer text.',
        maxWidth: 480,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FlowTextField(
              controller: triggerCtrl,
              hint: 'Trigger phrase (e.g. "intro email")',
              autofocus: true,
            ),
            const SizedBox(height: FlowTokens.space8),
            FlowTextField(
              controller: expansionCtrl,
              hint: 'Expansion text…',
              maxLines: 6,
              minLines: 3,
            ),
          ],
        ),
        actions: [
          FlowDialogAction(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          FlowDialogAction(
            label: 'Add snippet',
            isPrimary: true,
            onPressed: submit,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? _snippets
        : _snippets.where((s) {
            final trig = (s['trigger_phrase'] ?? '').toString().toLowerCase();
            final exp = (s['expansion'] ?? '').toString().toLowerCase();
            final q = _search.toLowerCase();
            return trig.contains(q) || exp.contains(q);
          }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          title: 'Snippets',
          count: _snippets.length,
          onSearch: (v) => setState(() => _search = v),
          onAdd: _showAddDialog,
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: FlowTokens.accent,
                      strokeWidth: 2.2,
                    ),
                  ),
                )
              : filtered.isEmpty
                  ? _EmptyState(
                      searching: _search.isNotEmpty,
                      query: _search,
                      onAdd: _showAddDialog,
                    )
                  : _SnippetList(
                      snippets: filtered,
                      onDelete: (id) async {
                        await widget.apiService.deleteSnippet(id);
                        _load();
                      },
                    ),
        ),
      ],
    );
  }
}

// ── Toolbar ─────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  final String title;
  final int count;
  final ValueChanged<String> onSearch;
  final VoidCallback onAdd;

  const _Toolbar({
    required this.title,
    required this.count,
    required this.onSearch,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final leftInset = ToolbarInset.leftOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        FlowTokens.space20 + leftInset,
        FlowTokens.space12,
        FlowTokens.space20,
        FlowTokens.space12,
      ),
      child: Row(
        children: [
          Text(title, style: FlowType.title),
          const SizedBox(width: FlowTokens.space8),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FlowTokens.space6,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: FlowTokens.hoverSurface,
                borderRadius: BorderRadius.circular(FlowTokens.radiusXs),
              ),
              child: Text(
                '$count',
                style: FlowType.footnote.copyWith(
                  fontSize: 10.5,
                  color: FlowTokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const Spacer(),
          FlowSearchField(
            hint: 'Search snippets',
            onChanged: onSearch,
          ),
          const SizedBox(width: FlowTokens.space8),
          FlowButton(
            label: 'Add',
            leadingIcon: Icons.add_rounded,
            variant: FlowButtonVariant.filled,
            size: FlowButtonSize.sm,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool searching;
  final String query;
  final VoidCallback onAdd;

  const _EmptyState({
    required this.searching,
    required this.query,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(FlowTokens.space32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      FlowTokens.accent.withValues(alpha: 0.25),
                      FlowTokens.accent.withValues(alpha: 0.10),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(FlowTokens.radiusLg),
                  border: Border.all(
                    color: FlowTokens.accent.withValues(alpha: 0.25),
                    width: 0.5,
                  ),
                ),
                child: Icon(
                  searching ? Icons.search_off_rounded : Icons.bolt_rounded,
                  size: 28,
                  color: FlowTokens.accent,
                ),
              ),
              const SizedBox(height: FlowTokens.space16),
              Text(
                searching ? 'No matches' : 'No snippets yet',
                style: FlowType.headline,
              ),
              const SizedBox(height: FlowTokens.space6),
              Text(
                searching
                    ? 'Nothing matches "$query".'
                    : 'Create trigger phrases like "intro email" that Flow '
                        'expands into longer text automatically while dictating.',
                style: FlowType.caption.copyWith(height: 1.45),
                textAlign: TextAlign.center,
              ),
              if (!searching) ...[
                const SizedBox(height: FlowTokens.space20),
                FlowButton(
                  label: 'Create first snippet',
                  leadingIcon: Icons.add_rounded,
                  variant: FlowButtonVariant.filled,
                  size: FlowButtonSize.md,
                  onPressed: onAdd,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Grouped snippet list ────────────────────────────────────────────

class _SnippetList extends StatelessWidget {
  final List<Map<String, dynamic>> snippets;
  final ValueChanged<dynamic> onDelete;

  const _SnippetList({required this.snippets, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        FlowTokens.space24,
        FlowTokens.space16,
        FlowTokens.space24,
        FlowTokens.space24,
      ),
      child: FlowCard(
        interactive: false,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < snippets.length; i++) ...[
              _SnippetRow(
                trigger: snippets[i]['trigger_phrase'] ?? '',
                expansion: snippets[i]['expansion'] ?? '',
                onDelete: () => onDelete(snippets[i]['id']),
              ),
              if (i < snippets.length - 1)
                const Padding(
                  padding: EdgeInsets.only(left: FlowTokens.space16),
                  child: Divider(height: 0.5, thickness: 0.5),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SnippetRow extends StatefulWidget {
  final String trigger;
  final String expansion;
  final VoidCallback onDelete;

  const _SnippetRow({
    required this.trigger,
    required this.expansion,
    required this.onDelete,
  });

  @override
  State<_SnippetRow> createState() => _SnippetRowState();
}

class _SnippetRowState extends State<_SnippetRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: FlowTokens.durFast,
        padding: const EdgeInsets.symmetric(
          horizontal: FlowTokens.space16,
          vertical: FlowTokens.space12,
        ),
        color: _hover ? FlowTokens.hoverSubtle : Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FlowTokens.space8,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: FlowTokens.accentSubtle,
                borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
              ),
              child: Text(
                widget.trigger,
                style: FlowType.bodyStrong.copyWith(
                  fontSize: 12,
                  color: FlowTokens.accent,
                  fontFeatures: const [],
                ),
              ),
            ),
            const SizedBox(width: FlowTokens.space10),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 12,
                color: FlowTokens.textTertiary,
              ),
            ),
            const SizedBox(width: FlowTokens.space10),
            Expanded(
              child: Text(
                widget.expansion,
                style: FlowType.body.copyWith(
                  fontSize: 13,
                  color: FlowTokens.textSecondary,
                  height: 1.45,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: FlowTokens.space10),
            AnimatedOpacity(
              duration: FlowTokens.durFast,
              opacity: _hover ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !_hover,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.onDelete,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: FlowTokens.systemRed.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        size: 13,
                        color: FlowTokens.systemRed,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
