/// Advanced / framework-adjacent surface of `package:armature`.
///
/// Import this barrel when you need:
///
/// * handler / callback typedefs for explicit field annotations
///   ([BehaviorHandler], [PipeHandler], [TaskFn], [VoidTask],
///   [StateChangeListener], [StateListenerDisposer],
///   [StateUpdateCallback]);
/// * port base types for generic code ([AnyPort], [Port], [PortType],
///   [PortSubscription]);
/// * the individual `TaskStrategy*` classes (usually you reach for
///   factories on [TaskStrategy] — `.queue`, `.once`, `.debounce(...)`
///   — and never touch these directly);
/// * debug-overlay mirrors of the live container
///   ([ContainerDebug], [FeatureDebugInfo], [FeatureDependency],
///   [PortDebugInfo]);
/// * [LoggerDebugInfo] for implementing a custom [Logger].
///
/// Everything here is deliberately kept out of the main
/// `package:armature/armature.dart` barrel to keep discovery sharp —
/// typical feature / store / task code should not need this import.
library;

export 'src/container/container_debug.dart'
    show
        ContainerDebug,
        ContainerDebugExt,
        FeatureDebugInfo,
        FeatureDependency,
        PortDebugInfo;
export 'src/container/port_subscription.dart' show PortSubscription;
export 'src/logger/logger.dart' show LoggerDebugInfo;
export 'src/port/behavior.dart' show BehaviorHandler;
export 'src/port/pipe.dart' show PipeHandler;
export 'src/port/port.dart' show AnyPort, Port;
export 'src/port/port_type.dart' show PortType;
export 'src/store/state.dart'
    show StateChangeListener, StateListenerDisposer, StateUpdateCallback;
export 'src/store/task.dart'
    show
        TaskFn,
        TaskStrategyDebounce,
        TaskStrategyLatest,
        TaskStrategyOnce,
        TaskStrategyQueue,
        TaskStrategyThrottle,
        VoidTask;
