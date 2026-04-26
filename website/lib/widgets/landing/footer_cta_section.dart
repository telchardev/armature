import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../external_links.dart';
import '../max_width.dart';

class FooterCtaSection extends StatelessWidget {
  const FooterCtaSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 72),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: MaxWidth(
        child: Column(
          children: [
            Text(
              'Ready to build?',
              style: theme.textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Browse the documentation or jump straight into working examples.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => context.go('/docs/quickstart'),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Read docs'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/examples'),
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: const Text('See examples'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => openExternal(kPubDevUrl),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('pub.dev'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
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
