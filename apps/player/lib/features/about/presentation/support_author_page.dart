import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';

class SupportAuthorPage extends StatelessWidget {
  const SupportAuthorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.supportAuthorTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  l10n.supportAuthorDescription,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/support/1b21b39164d4ad6ee94e35db23cf51f7.jpg',
                    width: 280,
                    height: 280,
                    semanticLabel: l10n.supportAuthorTitle,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.supportAuthorHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
