import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Apple-style text field with token colors, subtle stroke + focus tint.
/// Set [search] = true to get a leading search icon variant.
class FlowTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool search;
  final bool autofocus;
  final int? maxLines;
  final int? minLines;

  const FlowTextField({
    super.key,
    this.controller,
    this.hint,
    this.onChanged,
    this.onSubmitted,
    this.search = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
      maxLines: maxLines,
      minLines: minLines,
      cursorColor: FlowTokens.accent,
      style: FlowType.body.copyWith(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: FlowType.body.copyWith(
          fontSize: 13,
          color: FlowTokens.textTertiary,
        ),
        prefixIcon: search
            ? Icon(
                Icons.search_rounded,
                size: 15,
                color: FlowTokens.textTertiary,
              )
            : null,
        filled: true,
        fillColor: FlowTokens.bgElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: FlowTokens.space12,
          vertical: FlowTokens.space10,
        ),
        isDense: true,
        border: _border(FlowTokens.strokeSubtle),
        enabledBorder: _border(FlowTokens.strokeSubtle),
        focusedBorder: _border(FlowTokens.accent.withValues(alpha: 0.6), 1.2),
        disabledBorder: _border(FlowTokens.strokeSubtle),
      ),
    );
  }

  OutlineInputBorder _border(Color color, [double width = 0.5]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(FlowTokens.radiusMd),
        borderSide: BorderSide(color: color, width: width),
      );
}
