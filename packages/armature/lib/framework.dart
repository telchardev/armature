/// Framework-internal barrel for sibling packages (`armature_flutter`,
/// custom [Renderer] implementations, debug tooling). **Application
/// code must not import this** — the typed APIs in
/// `package:armature/armature.dart` cover every end-user scenario.
///
/// Types here ([Port], [AnyPort], [PortType], [PortSubscription]) are
/// the plumbing behind the public port subclasses (`Pipe`, `Behavior`,
/// slot variants) and may change without a major bump as long as the
/// public typed APIs stay stable.
library;

export 'src/container/port_subscription.dart' show PortSubscription;
export 'src/port/port.dart' show AnyPort, Port;
export 'src/port/port_type.dart' show PortType;
