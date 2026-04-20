import 'package:flutter/material.dart';
import '../services/speech_service.dart';
import '../services/api_service.dart';

class WordSuggestionsDialog extends StatefulWidget {
  final List<SuggestedWord> suggestions;
  final ApiService apiService;

  const WordSuggestionsDialog({
    super.key,
    required this.suggestions,
    required this.apiService,
  });

  @override
  State<WordSuggestionsDialog> createState() => _WordSuggestionsDialogState();
}

class _WordSuggestionsDialogState extends State<WordSuggestionsDialog> {
  late List<bool> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List.filled(widget.suggestions.length, true);
  }

  Future<void> _addSelected() async {
    for (int i = 0; i < widget.suggestions.length; i++) {
      if (_selected[i]) {
        final s = widget.suggestions[i];
        await widget.apiService.addDictionaryEntry(
          word: s.word,
          replacement: s.replacement.isNotEmpty ? s.replacement : null,
        );
      }
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Color(0xFFFFA726), size: 18),
                const SizedBox(width: 8),
                const Text('Add to Dictionary?', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38, size: 16),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'These words might improve future recognition',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 14),

            ...List.generate(widget.suggestions.length, (i) {
              final s = widget.suggestions[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _selected[i] = !_selected[i]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _selected[i] ? const Color(0xFF1F2937) : const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _selected[i]
                            ? const Color(0xFFE94560).withValues(alpha: 0.3)
                            : const Color(0xFF374151),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selected[i] ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 16,
                          color: _selected[i] ? const Color(0xFFE94560) : Colors.white38,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    s.word,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                  if (s.replacement.isNotEmpty && s.replacement != s.word) ...[
                                    const Text(' → ', style: TextStyle(color: Colors.white38, fontSize: 12)),
                                    Text(
                                      s.replacement,
                                      style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ],
                              ),
                              Text(s.reason, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),

            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Color(0xFF374151)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Skip', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selected.any((s) => s) ? _addSelected : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE94560),
                      disabledBackgroundColor: const Color(0xFF374151),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      'Add ${_selected.where((s) => s).length} words',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
