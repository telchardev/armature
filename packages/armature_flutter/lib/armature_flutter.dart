/// Flutter integration layer on top of `package:armature` — provides
/// the widget stack (`ArmatureApp`, `bootstrap`), pluggable [Renderer],
/// slot / provider widgets, and the debug overlay.
///
/// Production code imports this barrel; tests additionally import
/// `package:armature_flutter/test_utils.dart` for harness helpers.
library;

export './src/armature_app.dart' show ArmatureApp;
export './src/bootstrap.dart' show bootstrap;
export './src/contexts/container_context.dart' show ContainerContext;
export './src/contexts/store_context.dart'
    show BuildContextStoreExt, StoreContext;
export './src/create_feature_root.dart'
    show FeatureRootBuilder, createFeatureRoot;
export './src/debug/feature_graph_overlay.dart' show FeatureGraphOverlay;
export './src/feature_slot_extensions.dart';
export './src/ports/multi_slot.dart'
    show createMultiSlot, MultiSlotOrderDirection;
export './src/ports/multi_switch_slot.dart' show createMultiSwitchSlot;
export './src/ports/single_slot.dart' show createSingleSlot;
export './src/ports/single_switch_slot.dart' show createSingleSwitchSlot;
export './src/ports/slot_descriptor.dart'
    show SlotDescriptor, SlotLoaderBuilder;
export './src/providers/behavior_provider.dart' show BehaviorProvider;
export './src/providers/multi_port_builder.dart'
    show MultiPortBuilder, MultiPortWidgetBuilder, PortReader;
export './src/providers/multi_slot_provider.dart'
    show MultiSlotProvider, MultiSlotWidgetBuilder;
export './src/providers/pipe_provider.dart' show PipeProvider;
export './src/providers/single_slot_provider.dart'
    show SingleSlotProvider, SingleSlotWidgetBuilder;
export './src/renderer/flutter_renderer.dart'
    show
        FlutterRendererErrorBuilder,
        FlutterRendererLoaderBuilder,
        FlutterRendererOptions;
export './src/renderer/renderer.dart' show Renderer, RenderRootResult;
export './src/services/state_observer.dart' show StateObserver;
export './src/services/store_builder.dart' show StoreBuilder;
export './src/services/store_selector.dart' show StoreSelector;
