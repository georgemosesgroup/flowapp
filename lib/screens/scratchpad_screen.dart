import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/flow_button.dart';

class ScratchpadScreen extends StatefulWidget {
  const ScratchpadScreen({super.key});

  @override
  State<ScratchpadScreen> createState() => _ScratchpadScreenState();
}

class _ScratchpadScreenState extends State<ScratchpadScreen> {
  List<_Note> _notes = [];
  _Note? _activeNote;
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  /// Width of the Notes glass pane. User can drag the handle to
  /// resize; clamped to:
  ///   • a hard-floor so the pane never collapses into a sliver
  ///   • 30% of the available Scratchpad width so the editor always
  ///     owns at least 70% of the screen and notes can never take
  ///     over the workspace
  static const double _notesMinWidth = 160;
  static const double _notesMaxWidthRatio = 0.35;
  double _notesWidth = 200;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  void _loadNotes() {
    final raw = StorageService.instance.getString('scratchpad_notes');
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _notes = list.map((e) => _Note.fromJson(e)).toList();
      } catch (_) {}
    }
    setState(() {});
  }

  void _saveNotes() {
    final json = _notes.map((n) => n.toJson()).toList();
    StorageService.instance.setString('scratchpad_notes', jsonEncode(json));
  }

  void _createNote() {
    final note = _Note(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Untitled',
      body: '',
      createdAt: DateTime.now(),
    );
    setState(() {
      _notes.insert(0, note);
      _selectNote(note);
    });
    _saveNotes();
  }

  void _selectNote(_Note note) {
    _activeNote = note;
    _titleCtrl.text = note.title;
    _bodyCtrl.text = note.body;
    setState(() {});
  }

  void _updateActiveNote() {
    if (_activeNote == null) return;
    _activeNote!.title = _titleCtrl.text;
    _activeNote!.body = _bodyCtrl.text;
    _saveNotes();
    setState(() {});
  }

  void _deleteNote(_Note note) {
    setState(() {
      _notes.remove(note);
      if (_activeNote == note) {
        _activeNote = _notes.isNotEmpty ? _notes.first : null;
        if (_activeNote != null) _selectNote(_activeNote!);
      }
    });
    _saveNotes();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 30% of the available Scratchpad viewport — clamp the user's
        // stored width so a narrow window can't leave the editor with
        // nothing to stand on.
        final maxWidth = (constraints.maxWidth * _notesMaxWidthRatio)
            .clamp(_notesMinWidth, constraints.maxWidth);
        final effectiveWidth =
            _notesWidth.clamp(_notesMinWidth, maxWidth);

        return Row(
          children: [
            _NotesColumn(
              notes: _notes,
              activeId: _activeNote?.id,
              width: effectiveWidth,
              onCreate: _createNote,
              onSelect: _selectNote,
              onDelete: _deleteNote,
            ),
            // Thin vertical handle — press and drag horizontally to
            // resize the Notes pane. Shows a col-resize cursor on
            // hover so users discover the affordance.
            _NotesResizeHandle(
              onDrag: (dx) {
                setState(() {
                  _notesWidth =
                      (_notesWidth + dx).clamp(_notesMinWidth, maxWidth);
                });
              },
            ),
            Expanded(
              child: _activeNote == null ? _emptyEditor() : _editor(),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyEditor() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: FlowTokens.bgElevated,
              borderRadius: BorderRadius.circular(FlowTokens.radiusLg),
              border: Border.all(color: FlowTokens.strokeSubtle, width: 0.5),
            ),
            child: Icon(
              Icons.edit_note_rounded,
              size: 28,
              color: FlowTokens.textTertiary,
            ),
          ),
          const SizedBox(height: FlowTokens.space16),
          Text('Select or create a note', style: FlowType.headline),
          const SizedBox(height: FlowTokens.space4),
          Text(
            'A quick scratch space for dictation drafts.',
            style: FlowType.caption,
          ),
          const SizedBox(height: FlowTokens.space16),
          FlowButton(
            label: 'New note',
            leadingIcon: Icons.add_rounded,
            variant: FlowButtonVariant.tinted,
            size: FlowButtonSize.sm,
            onPressed: _createNote,
          ),
        ],
      ),
    );
  }

  Widget _editor() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FlowTokens.space32,
        FlowTokens.space24,
        FlowTokens.space32,
        FlowTokens.space24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleCtrl,
            cursorColor: FlowTokens.accent,
            style: FlowType.largeTitle.copyWith(fontSize: 24),
            decoration: InputDecoration(
              hintText: 'Title',
              hintStyle: FlowType.largeTitle.copyWith(
                fontSize: 24,
                color: FlowTokens.textTertiary,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
            onChanged: (_) => _updateActiveNote(),
          ),
          const SizedBox(height: FlowTokens.space12),
          Expanded(
            child: TextField(
              controller: _bodyCtrl,
              cursorColor: FlowTokens.accent,
              style: FlowType.body.copyWith(fontSize: 14, height: 1.7),
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: 'Start typing or dictate…',
                hintStyle: FlowType.body.copyWith(
                  fontSize: 14,
                  color: FlowTokens.textTertiary,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (_) => _updateActiveNote(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Notes sidebar column ───────────────────────────────────────────

class _NotesColumn extends StatelessWidget {
  final List<_Note> notes;
  final String? activeId;
  final double width;
  final VoidCallback onCreate;
  final ValueChanged<_Note> onSelect;
  final ValueChanged<_Note> onDelete;

  const _NotesColumn({
    required this.notes,
    required this.activeId,
    required this.width,
    required this.onCreate,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Floating glass pane — matches the main sidebar on the left side
    // of the app. Sits over the opaque-dark body with its own
    // translucent gradient, bright edge, and shadow so "two glass
    // panes stacked" reads properly. Width is driven by the parent so
    // the user can drag a handle to resize it.
    return Container(
      width: width,
      margin: const EdgeInsets.fromLTRB(
        FlowTokens.space8, // breathing room from the main Flow nav pane
        FlowTokens.space8,
        0,
        FlowTokens.space8,
      ),
      decoration: BoxDecoration(
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(
                FlowTokens.space16,
                FlowTokens.space16,
                FlowTokens.space10,
                FlowTokens.space12,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: FlowTokens.strokeSubtle,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text('Notes', style: FlowType.headline),
                  const SizedBox(width: FlowTokens.space6),
                  if (notes.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FlowTokens.space6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: FlowTokens.hoverSurface,
                        borderRadius:
                            BorderRadius.circular(FlowTokens.radiusXs),
                      ),
                      child: Text(
                        '${notes.length}',
                        style: FlowType.footnote.copyWith(
                          fontSize: 10.5,
                          color: FlowTokens.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const Spacer(),
                  _AddButton(onTap: onCreate),
                ],
              ),
            ),
            Expanded(
              child: notes.isEmpty
                  ? Center(
                      child: Text(
                        'No notes',
                        style: FlowType.caption.copyWith(
                          color: FlowTokens.textTertiary,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FlowTokens.space8,
                        vertical: FlowTokens.space8,
                      ),
                      itemCount: notes.length,
                      itemBuilder: (_, i) {
                        final n = notes[i];
                        return _NoteRow(
                          note: n,
                          isActive: n.id == activeId,
                          onSelect: () => onSelect(n),
                          onDelete: () => onDelete(n),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatefulWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton> {
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
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: _hover ? FlowTokens.accentSubtle : Colors.transparent,
            borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
          ),
          child: const Icon(
            Icons.add_rounded,
            size: 16,
            color: FlowTokens.accent,
          ),
        ),
      ),
    );
  }
}

class _NoteRow extends StatefulWidget {
  final _Note note;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  const _NoteRow({
    required this.note,
    required this.isActive,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  State<_NoteRow> createState() => _NoteRowState();
}

class _NoteRowState extends State<_NoteRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.note;
    final bg = widget.isActive
        ? FlowTokens.accentSubtle
        : _hover
            ? FlowTokens.bgElevatedHover
            : Colors.transparent;
    final titleColor = widget.isActive
        ? FlowTokens.textPrimary
        : FlowTokens.textSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: FlowTokens.durFast,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(
            horizontal: FlowTokens.space8,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      n.title.isEmpty ? 'Untitled' : n.title,
                      style: FlowType.body.copyWith(
                        fontSize: 12.5,
                        fontWeight: widget.isActive
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: titleColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${n.createdAt.day}.${n.createdAt.month}.${n.createdAt.year}',
                      style: FlowType.footnote.copyWith(
                        fontSize: 10,
                        color: FlowTokens.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.isActive || _hover)
                GestureDetector(
                  onTap: widget.onDelete,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 13,
                      color: FlowTokens.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Model ──────────────────────────────────────────────────────────

class _Note {
  String id;
  String title;
  String body;
  DateTime createdAt;

  _Note({required this.id, required this.title, required this.body, required this.createdAt});

  factory _Note.fromJson(Map<String, dynamic> json) => _Note(
    id: json['id'] ?? '',
    title: json['title'] ?? '',
    body: json['body'] ?? '',
    createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'created_at': createdAt.toIso8601String(),
  };
}

// ── Resize handle for the Notes pane ───────────────────────────────

class _NotesResizeHandle extends StatefulWidget {
  final ValueChanged<double> onDrag;
  const _NotesResizeHandle({required this.onDrag});

  @override
  State<_NotesResizeHandle> createState() => _NotesResizeHandleState();
}

class _NotesResizeHandleState extends State<_NotesResizeHandle> {
  bool _hover = false;
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    // Full-height hit target (8px wide) so the cursor is easy to land,
    // but the visible indicator is a short vertical "grip pill" sitting
    // at the vertical center. Keeps the UI clean — no hairline running
    // the whole window height — while still telegraphing "I can be
    // dragged" via the resize cursor + hover emphasis.
    final indicatorColor = _active
        ? FlowTokens.accent
        : (_hover ? FlowTokens.textTertiary : FlowTokens.strokeDivider);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _active = true),
        onHorizontalDragEnd: (_) => setState(() => _active = false),
        onHorizontalDragCancel: () => setState(() => _active = false),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        child: SizedBox(
          width: 14, // generous hit target so the cursor lands easily
          child: Align(
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: FlowTokens.durFast,
              curve: FlowTokens.easeStandard,
              width: _active || _hover ? 3 : 2.5,
              height: _active ? 44 : (_hover ? 36 : 28),
              decoration: BoxDecoration(
                color: indicatorColor,
                borderRadius: BorderRadius.circular(FlowTokens.radiusFull),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
