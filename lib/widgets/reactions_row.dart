import 'package:flutter/material.dart';
import '../core/theme.dart';

class ReactionsRow extends StatelessWidget {
  final Map<String, String> reactions;
  final String currentUserId;
  final Function(String emoji) onReactionTapped;

  const ReactionsRow({
    super.key,
    required this.reactions,
    required this.currentUserId,
    required this.onReactionTapped,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    // Group reactions by emoji character
    final Map<String, List<String>> grouped = {};
    reactions.forEach((userId, emoji) {
      grouped.putIfAbsent(emoji, () => []).add(userId);
    });

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: grouped.entries.map((entry) {
        final emoji = entry.key;
        final userIds = entry.value;
        final count = userIds.length;
        final hasReacted = userIds.contains(currentUserId);

        return GestureDetector(
          onTap: () => onReactionTapped(emoji),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: hasReacted
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                  : context.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasReacted
                    ? Theme.of(context).colorScheme.primary
                    : context.textSecondary.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: hasReacted
                        ? Theme.of(context).colorScheme.primary
                        : context.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
