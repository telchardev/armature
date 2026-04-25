import 'package:flutter/widgets.dart';

import 'content/activation_helpers.dart';
import 'content/armature_app.dart';
import 'content/coming_soon.dart';
import 'content/debug_overlay.dart';
import 'content/dependency_graph.dart';
import 'content/error_model.dart';
import 'content/feature_root.dart';
import 'content/features.dart';
import 'content/getting_started.dart';
import 'content/installation.dart';
import 'content/multi_port_builder.dart';
import 'content/ports.dart';
import 'content/slot_widgets.dart';
import 'content/stores.dart';
import 'content/tasks.dart';
import 'content/when_to_use.dart';
import 'docs_tree.dart';

/// Maps a doc slug to its content widget. Slugs without a registered widget
/// fall through to [ComingSoonContent].
const Map<String, Widget> _registry = {
  'when-to-use': WhenToUseContent(),
  'getting-started': GettingStartedContent(),
  'installation': InstallationContent(),
  'features': FeaturesContent(),
  'dependency-graph': DependencyGraphContent(),
  'stores': StoresContent(),
  'ports': PortsContent(),
  'tasks': TasksContent(),
  'activation-helpers': ActivationHelpersContent(),
  'error-model': ErrorModelContent(),
  'armature-app': ArmatureAppContent(),
  'feature-root': FeatureRootContent(),
  'slot-widgets': SlotWidgetsContent(),
  'multi-port-builder': MultiPortBuilderContent(),
  'debug-overlay': DebugOverlayContent(),
};

/// Resolves [slug] to a content widget.
///
/// If no content is registered for the slug, returns a "coming soon"
/// placeholder using the title from [docsTree] (or the slug itself when the
/// slug is unknown).
Widget resolveDocContent(String slug) {
  final registered = _registry[slug];
  if (registered != null) {
    return registered;
  }
  final entry = findEntry(slug);
  return ComingSoonContent(title: entry?.title ?? slug);
}
