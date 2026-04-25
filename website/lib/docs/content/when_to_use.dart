import 'package:flutter/material.dart';

import '../doc_typography.dart';

class WhenToUseContent extends StatelessWidget {
  const WhenToUseContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('Is this for me?'),
        const DocParagraph(
          'Armature is built around explicit feature boundaries. It pays '
          'off in apps that grow into several independent feature areas '
          'with explicit dependencies between them. For a small app or a '
          'quick prototype, it is overkill — Provider or Riverpod will '
          'get you there with less ceremony.',
        ),
        const DocParagraph(
          'This page lays out the signals that say "you are in armature '
          'territory" and the ones that say "keep using Provider/Riverpod". '
          'Read it once before you commit to the framework.',
        ),
        const DocHeading('Use armature when'),
        const DocBullet(
          'Your app has many feature areas with clear boundaries (auth, '
          'profile, content, admin, settings, …). The port system pays off '
          'precisely when features need to coordinate without knowing about '
          'each other.',
        ),
        const DocBullet(
          'Multiple developers or teams work on the same app. Explicit '
          'feature boundaries reduce merge conflicts and let each team '
          'own a module end-to-end.',
        ),
        const DocBullet(
          'You need runtime feature toggles — admin views gated on user '
          'role, A/B variants, env-specific modules. activation() with '
          'whenStoreState() / whenActive() turns this into a one-liner '
          'instead of if-statements scattered through the codebase.',
        ),
        const DocBullet(
          'Non-trivial coordination across features — auth state affecting '
          'five places, counter ticks logged to history, theme changes '
          'propagating through ports. Manual wiring of these in a Provider '
          'tree gets fragile fast.',
        ),
        const DocHeading('Skip armature if'),
        const DocBullet(
          'You are a solo developer on a one- or two-screen app. Provider '
          'or Riverpod ship faster and the framework structure has nothing '
          'to amortise against.',
        ),
        const DocBullet(
          'Your app is a single feature area with no plans to grow. The '
          'structure costs more than it saves.',
        ),
        const DocBullet(
          'You are prototyping throwaway code. The cascade syntax and '
          'explicit wiring will outpace your iteration speed when you are '
          'still figuring out the product.',
        ),
        const DocBullet(
          'You optimise for the absolute smallest codebase. Armature trades '
          'lines for explicit dependencies — that is the deal it offers.',
        ),
        const DocHeading('Where armature fits'),
        const DocParagraph(
          'Armature focuses on the feature/module layer — composing '
          'self-contained modules through dependencies, ports, and runtime '
          'activation. State management inside a module uses armature\'s '
          'own Store and reactive primitives.',
        ),
        const DocParagraph(
          'If your pain point is "too many tangled providers across the '
          'app", that\'s where armature helps. If your pain point is '
          '"writing reactive logic inside one screen", Riverpod or BLoC '
          'are more direct tools.',
        ),
        const DocHeading('What is next?'),
        const DocBullet(
          'Installation — pick the packages that match your project and '
          'add them to pubspec.yaml.',
        ),
        const DocBullet(
          'Introduction — define your first feature, bootstrap the app, '
          'render reactive state from a store.',
        ),
      ],
    );
  }
}
