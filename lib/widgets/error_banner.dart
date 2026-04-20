import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'flow_button.dart';

/// Reusable error display banner using tokens + FlowButton for consistency.
class ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  const ErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FlowTokens.space12),
      decoration: BoxDecoration(
        color: FlowTokens.systemRed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(FlowTokens.radiusLg),
        border: Border.all(
          color: FlowTokens.systemRed.withValues(alpha: 0.28),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: FlowTokens.systemRed.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              size: 15,
              color: FlowTokens.systemRed,
            ),
          ),
          const SizedBox(width: FlowTokens.space12),
          Expanded(
            child: Text(
              message,
              style: FlowType.body.copyWith(
                fontSize: 13,
                color: FlowTokens.systemRed,
              ),
            ),
          ),
          if (onRetry != null)
            FlowButton(
              label: 'Retry',
              variant: FlowButtonVariant.tinted,
              size: FlowButtonSize.sm,
              onPressed: onRetry,
            ),
          if (onDismiss != null)
            Padding(
              padding: const EdgeInsets.only(left: FlowTokens.space4),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onDismiss,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(FlowTokens.radiusSm),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: FlowTokens.systemRed.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
