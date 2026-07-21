import 'package:flutter/material.dart';

import '../models/models.dart';

class WordDefinitionSheet extends StatelessWidget {
  const WordDefinitionSheet({super.key, required this.group});

  final WordGroup group;

  static Future<void> show(BuildContext context, WordGroup group) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => WordDefinitionSheet(group: group),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (group.lemma.isNotEmpty)
              Text(
                group.lemma,
                textAlign: TextAlign.center,
                style: theme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              group.strongs,
              textAlign: TextAlign.center,
              style: theme.titleMedium?.copyWith(
                color: Colors.amberAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (group.phrase.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '"${group.phrase}"',
                textAlign: TextAlign.center,
                style: theme.bodyMedium?.copyWith(color: Colors.white70),
              ),
            ],
            if (group.definition.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                group.definition,
                textAlign: TextAlign.center,
                style: theme.bodyLarge?.copyWith(
                  color: Colors.white,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
