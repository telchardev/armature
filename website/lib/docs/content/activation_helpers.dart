import 'package:flutter/material.dart';

import '../../widgets/code_block.dart';
import '../doc_typography.dart';

class ActivationHelpersContent extends StatelessWidget {
  const ActivationHelpersContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DocTitle('Activation helpers'),
        const DocParagraph(
          'The activation() hook takes an ActivationSetup — a callback '
          'that wires a feature\'s own-active flag to some external '
          'condition. Writing the callback by hand gets repetitive, so '
          'Armature ships five composable helpers for the common cases. '
          'Each returns an ActivationSetup you pass directly into '
          'activation().',
        ),
        const DocHeading('manualActivation()'),
        const DocParagraph(
          'Starts the feature in inactive state and hands the toggle '
          'callable out to user code through an ActivationSetup that '
          'does nothing on its own. Useful when activation is driven '
          'imperatively — e.g. from a debug button, a remote kill-switch, '
          'or a test harness.',
        ),
        const CodeBlock(code: _manualSource, language: 'dart'),
        const DocParagraph(
          'Every activation helper returns a callable you can replace '
          'with your own ActivationSetup at any point. manualActivation() '
          'is the minimal one — no subscriptions, no cleanup needed.',
        ),
        const DocHeading('whenStoreState()'),
        const DocParagraph(
          'Subscribes to a store on a declared parent and flips '
          'activation whenever the predicate over its state changes '
          'truth value. The most common real-world gate.',
        ),
        const CodeBlock(code: _whenStoreStateSource, language: 'dart'),
        const DocParagraph(
          'Fires fireImmediately, so the initial activation matches the '
          'parent store\'s current state — no first-frame flicker.',
        ),
        const DocHeading('whenActive(feature)'),
        const DocParagraph(
          'Owning feature is active exactly when [feature] is. A '
          'lightweight mirror of another feature\'s lifecycle through '
          'the public parentApi.statusOf() accessor.',
        ),
        const CodeBlock(code: _whenActiveSource, language: 'dart'),
        const DocHeading('whenInactive(feature)'),
        const DocParagraph(
          'Inverse of whenActive — owning feature is active while '
          '[feature] is disabled or pending. Good for fallback UI that '
          'shows only when the main counterpart is off.',
        ),
        const CodeBlock(code: _whenInactiveSource, language: 'dart'),
        const DocHeading('whenAllActive(features)'),
        const DocParagraph(
          'Active only when every feature in the list is active. Any '
          'one flipping away deactivates the owner; a return to '
          'all-active re-activates it. An empty list keeps the feature '
          'permanently active.',
        ),
        const CodeBlock(code: _whenAllActiveSource, language: 'dart'),
        const DocHeading('Composing your own'),
        const DocParagraph(
          'The helpers are just factories that return ActivationSetup '
          'closures. Write your own when the built-ins do not fit — '
          'the contract is a function that subscribes its triggers, '
          'registers disposers with cleanup.add(), and calls '
          'toggle(ToggleState.active | .inactive) on every transition:',
        ),
        const CodeBlock(code: _customSource, language: 'dart'),
        const DocHeading('What is next?'),
        const DocBullet(
          'Error model — what happens when an activation setup throws, '
          'and how the failure reaches the container\'s errorHandler.',
        ),
        const DocBullet(
          'ArmatureApp — where the errorHandler these setups report '
          'into is installed.',
        ),
      ],
    );
  }
}

const _manualSource =
    '''// The feature never auto-activates. You keep the toggle reference
// somewhere external (a debug panel, a remote config handler, a test).
late FeatureToggle killSwitchToggle;

final experimentalFeature = createFeature(
  name: 'Experimental',
  stores: (_) => (flag: ExperimentalFlagStore()),
  exports: (api) => api.own,
)..activation((parentApi, toggle, cleanup) {
  killSwitchToggle = toggle;
  return manualActivation()(parentApi, toggle, cleanup);
});

// Later, from anywhere:
void enableExperiment() => killSwitchToggle(ToggleState.active);''';

const _whenStoreStateSource = '''final adminFeature = createFeature(
  name: 'Admin',
  dependsOn: [sessionFeature],
  stores: (_) => (panel: AdminPanelStore()),
  exports: (api) => api.own,
)..activation(whenStoreState(
  feature: sessionFeature,
  store: (exports) => exports.session,
  predicate: (state) => state.user?.role == Role.admin,
));''';

const _whenActiveSource = '''final inspectorOverlayFeature = createFeature(
  name: 'InspectorOverlay',
  optionalDependsOn: [inspectorFeature],
)..activation(whenActive(inspectorFeature));''';

const _whenInactiveSource = '''final loginPromptFeature = createFeature(
  name: 'LoginPrompt',
  optionalDependsOn: [sessionFeature],
)..activation(whenInactive(sessionFeature));''';

const _whenAllActiveSource = '''final syncedFeature = createFeature(
  name: 'SyncedData',
  dependsOn: [networkFeature, sessionFeature],
)..activation(whenAllActive([networkFeature, sessionFeature]));''';

const _customSource =
    '''ActivationSetup whenOffline(AnyFeature networkFeature) {
  return (parentApi, toggle, cleanup) {
    final status = parentApi.of(networkFeature).status;
    cleanup.add(status.subscribe((_, current) {
      unawaited(toggle(
        current.isOffline ? ToggleState.active : ToggleState.inactive,
      ));
    }, fireImmediately: true));
  };
}

// Use it:
final offlineBannerFeature = createFeature(
  name: 'OfflineBanner',
  optionalDependsOn: [networkFeature],
)..activation(whenOffline(networkFeature));''';
