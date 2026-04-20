import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// Wrap a screen's header content in this widget and give it the scroll
/// controller / notification of its list below. When the list scrolls
/// past a threshold (default 4 px) the header picks up a subtle dark
/// translucent fill, a hairline stroke and a rounded-pill look —
/// matching the macOS behaviour where toolbars animate in a background
/// once the user has started scrolling.
///
/// Keep the header itself stateless — this wrapper owns the `elevated`
/// boolean and animates the surrounding container.
class FlowScrollElevated extends StatelessWidget {
  final bool elevated;
  final Widget child;

  const FlowScrollElevated({
    super.key,
    required this.elevated,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // No darkening — just a faint hairline at the bottom once the list
    // has scrolled past the header, so it still feels visually
    // separated from the content without adding a dark tint.
    return AnimatedContainer(
      duration: FlowTokens.durBase,
      curve: FlowTokens.easeStandard,
      decoration: BoxDecoration(
        border: elevated
            ? Border(
                bottom: BorderSide(
                  color: FlowTokens.strokeSubtle,
                  width: 0.5,
                ),
              )
            : null,
      ),
      child: child,
    );
  }
}
