import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/flow_card.dart';
import '../widgets/flow_segmented_control.dart';
import '../widgets/toolbar_inset.dart';

class StyleScreen extends StatefulWidget {
  const StyleScreen({super.key});

  @override
  State<StyleScreen> createState() => _StyleScreenState();
}

class _StyleScreenState extends State<StyleScreen> {
  late StorageService _storage;
  String _selectedContext = 'personal';

  static const _contexts = <FlowSegment<String>>[
    FlowSegment(value: 'personal', label: 'Personal'),
    FlowSegment(value: 'work', label: 'Work'),
    FlowSegment(value: 'email', label: 'Email'),
    FlowSegment(value: 'other', label: 'Other'),
  ];

  @override
  void initState() {
    super.initState();
    _storage = StorageService.instance;
  }

  String _currentStyle() => _storage.dictationStyle;

  void _setStyle(String style) {
    _storage.setDictationStyle(style);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final currentStyle = _currentStyle();

    final leftInset = ToolbarInset.leftOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            FlowTokens.space20 + leftInset,
            FlowTokens.space12,
            FlowTokens.space20,
            FlowTokens.space12,
          ),
          child: Row(
            children: [
              Text('Style', style: FlowType.title),
              const SizedBox(width: FlowTokens.space16),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FlowSegmentedControl<String>(
                    selected: _selectedContext,
                    segments: _contexts,
                    onChanged: (v) => setState(() => _selectedContext = v),
                    size: FlowSegmentSize.sm,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              FlowTokens.space24,
              FlowTokens.space16,
              FlowTokens.space24,
              FlowTokens.space24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    left: FlowTokens.space4,
                    bottom: FlowTokens.space10,
                  ),
                  child: Text(
                    'How dictated text is formatted and capitalized.',
                    style: FlowType.caption,
                  ),
                ),
                _StyleOption(
                  title: 'Formal',
                  description: 'Full capitalization and punctuation.',
                  example:
                      "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you.",
                  isSelected: currentStyle == 'formal',
                  onTap: () => _setStyle('formal'),
                ),
                const SizedBox(height: FlowTokens.space8),
                _StyleOption(
                  title: 'Casual',
                  description: 'Capitalization with reduced punctuation.',
                  example:
                      'Hey are you free for lunch tomorrow? Lets do 12 if that works for you',
                  isSelected: currentStyle == 'casual',
                  onTap: () => _setStyle('casual'),
                ),
                const SizedBox(height: FlowTokens.space8),
                _StyleOption(
                  title: 'Very casual',
                  description: 'All lowercase with minimal punctuation.',
                  example:
                      'hey are you free for lunch tomorrow lets do 12 if that works for you',
                  isSelected: currentStyle == 'very_casual',
                  onTap: () => _setStyle('very_casual'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Style option card (radio-card) ─────────────────────────────────

class _StyleOption extends StatelessWidget {
  final String title;
  final String description;
  final String example;
  final bool isSelected;
  final VoidCallback onTap;

  const _StyleOption({
    required this.title,
    required this.description,
    required this.example,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FlowCard(
      selected: isSelected,
      onTap: onTap,
      padding: const EdgeInsets.all(FlowTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: FlowTokens.durFast,
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: isSelected ? FlowTokens.accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? FlowTokens.accent
                        : FlowTokens.strokeDivider,
                    width: isSelected ? 2 : 1.2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: FlowTokens.space10),
              Text(title, style: FlowType.headline),
              const SizedBox(width: FlowTokens.space8),
              Flexible(
                child: Text(
                  description,
                  style: FlowType.caption,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: FlowTokens.space12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(FlowTokens.space12),
            decoration: BoxDecoration(
              color: FlowTokens.bgPressed,
              borderRadius: BorderRadius.circular(FlowTokens.radiusMd),
              border: Border.all(color: FlowTokens.strokeSubtle, width: 0.5),
            ),
            child: Text(
              example,
              style: FlowType.body.copyWith(
                fontSize: 13,
                color: FlowTokens.textSecondary,
                fontStyle: FontStyle.italic,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
