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

class DictionaryScreen extends StatefulWidget {
  final ApiService apiService;
  const DictionaryScreen({super.key, required this.apiService});

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.apiService.getDictionary();
    if (mounted) setState(() { _entries = items; _loading = false; });
  }

  void _showAddDialog() {
    final wordCtrl = TextEditingController();
    final replCtrl = TextEditingController();

    Future<void> submit() async {
      if (wordCtrl.text.trim().isEmpty) return;
      if (mounted) Navigator.of(context).pop();
      await widget.apiService.addDictionaryEntry(
        word: wordCtrl.text.trim(),
        replacement: replCtrl.text.trim().isEmpty
            ? null
            : replCtrl.text.trim(),
      );
      _load();
    }

    showFlowDialog<void>(
      context: context,
      dialog: FlowDialog(
        title: 'Add word',
        subtitle: 'Teach Flow how to spell a name, brand, or technical term.',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlowTextField(
              controller: wordCtrl,
              hint: 'Word (e.g. postgis)',
              autofocus: true,
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: FlowTokens.space8),
            FlowTextField(
              controller: replCtrl,
              hint: 'Replacement (optional, e.g. PostGIS)',
              onSubmitted: (_) => submit(),
            ),
          ],
        ),
        actions: [
          FlowDialogAction(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          FlowDialogAction(
            label: 'Add word',
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
        ? _entries
        : _entries
            .where((e) => (e['word'] ?? '')
                .toString()
                .toLowerCase()
                .contains(_search.toLowerCase()))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          title: 'Dictionary',
          count: _entries.length,
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
                  : _EntryList(
                      entries: filtered,
                      onDelete: (id) async {
                        await widget.apiService.deleteDictionaryEntry(id);
                        _load();
                      },
                    ),
        ),
      ],
    );
  }
}

// ── Compact toolbar ─────────────────────────────────────────────────

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
            hint: 'Search dictionary',
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
                  searching
                      ? Icons.search_off_rounded
                      : Icons.menu_book_rounded,
                  size: 28,
                  color: FlowTokens.accent,
                ),
              ),
              const SizedBox(height: FlowTokens.space16),
              Text(
                searching ? 'No matches' : 'Your dictionary is empty',
                style: FlowType.headline,
              ),
              const SizedBox(height: FlowTokens.space6),
              Text(
                searching
                    ? 'Nothing matches "$query".'
                    : 'Teach Flow how to spell names, acronyms, and '
                        'technical terms — they\'ll be applied automatically '
                        'in every dictation.',
                style: FlowType.caption.copyWith(height: 1.45),
                textAlign: TextAlign.center,
              ),
              if (!searching) ...[
                const SizedBox(height: FlowTokens.space20),
                FlowButton(
                  label: 'Add your first word',
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

// ── Grouped entry list (single card with hairline dividers) ─────────

class _EntryList extends StatelessWidget {
  final List<Map<String, dynamic>> entries;
  final ValueChanged<dynamic> onDelete;

  const _EntryList({required this.entries, required this.onDelete});

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
            for (var i = 0; i < entries.length; i++) ...[
              _DictionaryRow(
                word: entries[i]['word'] ?? '',
                replacement: entries[i]['replacement'] as String?,
                onDelete: () => onDelete(entries[i]['id']),
              ),
              if (i < entries.length - 1)
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

// ── Single dictionary row ──────────────────────────────────────────

class _DictionaryRow extends StatefulWidget {
  final String word;
  final String? replacement;
  final VoidCallback onDelete;

  const _DictionaryRow({
    required this.word,
    required this.replacement,
    required this.onDelete,
  });

  @override
  State<_DictionaryRow> createState() => _DictionaryRowState();
}

class _DictionaryRowState extends State<_DictionaryRow> {
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
          vertical: FlowTokens.space10,
        ),
        color: _hover ? FlowTokens.hoverSubtle : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      widget.word,
                      style: FlowType.bodyStrong.copyWith(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.replacement != null &&
                      widget.replacement!.isNotEmpty) ...[
                    const SizedBox(width: FlowTokens.space10),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 12,
                      color: FlowTokens.textTertiary,
                    ),
                    const SizedBox(width: FlowTokens.space10),
                    Flexible(
                      child: Text(
                        widget.replacement!,
                        style: FlowType.body.copyWith(
                          fontSize: 13,
                          color: FlowTokens.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
