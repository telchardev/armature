/// Core public surface of `package:armature`.
///
/// This barrel exposes the ~25 symbols needed to author features,
/// stores, tasks, and declare ports. Framework plumbing —
/// internal typedefs, port base classes, debug mirrors, and the
/// individual `TaskStrategy*` constructors — lives in
/// `package:armature/advanced.dart`. Reach for it only when you need
/// to annotate a field with a handler signature, build a debug
/// overlay, or extend the framework itself.
library;

export 'src/container/container.dart'
    show AppContainer, ContainerErrorHandler, ContainerOptions, ContainerStatus;
export 'src/errors.dart'
    show
        ArmatureError,
        ContainerError,
        ContainerUsageError,
        FeatureConfigurationError,
        FeatureResolutionError,
        FeatureResolutionReason,
        HandlerError,
        ListenerError,
        PortError,
        RenderError,
        StoreLookupError,
        TaskError;
export 'src/feature/activation_helpers.dart'
    show
        manualActivation,
        whenActive,
        whenAllActive,
        whenInactive,
        whenStoreState;
export 'src/feature/cleanup.dart' show Cleanup;
export 'src/feature/feature.dart'
    show ActivationSetup, AnyFeature, Feature, StartCallback, createFeature;
export 'src/feature/feature_api.dart'
    show
        ExportsFactory,
        FeatureHandlerContext,
        FeatureParentApi,
        FeatureScopeApi,
        StoresFactory;
export 'src/feature/feature_status.dart'
    show FeatureStatus, FeatureToggle, ToggleState;
export 'src/logger/logger.dart' show Logger, LogLevel;
export 'src/logger/print_logger.dart' show PrintLogger;
export 'src/port/behavior.dart'
    show Behavior, BehaviorDescriptor, createBehavior;
export 'src/port/pipe.dart' show Pipe, createPipe;
export 'src/store/store.dart' show Store;
export 'src/store/task.dart'
    show
        Task,
        TaskDone,
        TaskFailed,
        TaskIdle,
        TaskPending,
        TaskState,
        TaskStrategy,
        ThrottleEdge;
export 'src/store/task_state_extensions.dart' show TaskStateExtensions;
