import 'dart:async';

import 'package:armature/armature.dart';

/// Self-contained end-to-end example of `armature` — three features
/// wired together through a container, demonstrating:
///
/// - **stores + tasks** (`OrdersStore`, `AnalyticsStore`, `SettingsStore`)
/// - **required** dependencies (`analyticsFeature` depends on orders)
/// - **optional** dependencies + **activation helpers**
///   (`auditFeature` opts in to orders, activation gated by a settings
///   toggle via `whenStoreState`)
/// - **cross-feature reactive subscriptions** inside `onStart`
/// - **unified error routing** via `ContainerOptions.errorHandler`
///
/// Run with `dart run example/example.dart`.

// ── Stores ──

class OrdersStore extends Store<List<String>> {
  OrdersStore() : super(state: const []);

  late final placeOrder = createTask<String, void, Never>(
    fn: (id) async => update((s) => [...s, id]),
    strategy: TaskStrategy.queue,
  );
}

class AnalyticsStore extends Store<int> {
  AnalyticsStore() : super(state: 0);
  void tick() => update((s) => s + 1);
}

typedef AppSettings = ({bool auditEnabled});

class SettingsStore extends Store<AppSettings> {
  SettingsStore() : super(state: (auditEnabled: false));
  void toggleAudit() => update((s) => (auditEnabled: !s.auditEnabled));
}

// ── Demo-only handles ──
//
// In a real app, interactions happen *inside* features (tasks, port
// handlers, activation setups). For this CLI demo we want `main()` to
// drive orders + toggle settings, so we publish a handle to each store
// via `late final`. The constructor still runs *inside* the `stores:`
// factory — so `Store.track()` registers the store for `api.store<T>()`
// lookups and the debug inspector — we just also stash the reference
// for the demo's convenience.

late final OrdersStore _orders;
late final AnalyticsStore _analytics;
late final SettingsStore _settings;

// ── Features ──

final ordersFeature = createFeature(
  name: 'Orders',
  stores: (_) {
    _orders = OrdersStore();
    return (orders: _orders);
  },
  exports: (api) => api.own,
);

final settingsFeature = createFeature(
  name: 'Settings',
  stores: (_) {
    _settings = SettingsStore();
    return (settings: _settings);
  },
  exports: (api) => api.own,
);

/// Depends on orders — mirrors every placed order into a counter. In
/// `onStart` we subscribe; the returned disposer goes into the
/// per-activation cleanup bag so it runs LIFO on deactivation.
final analyticsFeature =
    createFeature(
      name: 'Analytics',
      dependsOn: [ordersFeature],
      stores: (_) {
        _analytics = AnalyticsStore();
        return (analytics: _analytics);
      },
      exports: (api) => api.own,
    )..onStart((api, cleanup) {
      final orders = api.of(ordersFeature).orders;
      cleanup.add(
        orders.subscribe((prev, curr) {
          if (curr.length > prev.length) api.own.analytics.tick();
        }),
      );
    });

/// Optional dependency on orders + an activation helper:
/// `whenStoreState` reads a store from a declared parent and flips
/// activation when the predicate changes. Audit only runs while
/// `settings.auditEnabled == true`.
final auditFeature =
    createFeature(
        name: 'Audit',
        dependsOn: [settingsFeature],
        optionalDependsOn: [ordersFeature],
      )
      ..onStart((api, cleanup) {
        final orders = api.of(ordersFeature).orders;
        cleanup.add(
          orders.subscribe((prev, curr) {
            if (curr.length > prev.length) {
              print('[audit] new order: ${curr.last}');
            }
          }),
        );
      })
      ..activation(
        whenStoreState(
          feature: settingsFeature,
          store: (exports) => exports.settings,
          predicate: (s) => s.auditEnabled,
        ),
      );

// ── Main ──

Future<void> main() async {
  final container = AppContainer(
    features: [settingsFeature, ordersFeature, analyticsFeature, auditFeature],
    options: ContainerOptions(
      errorHandler: ({required source, required error, required meta}) {
        // Single sink for every recoverable error the framework sees.
        print('[$source] $error');
      },
    ),
  );

  await container.start();
  print('status: analytics=${_analytics.state}, audit=off');

  await _orders.placeOrder('o-1');
  await _orders.placeOrder('o-2');
  // Analytics reacted; Audit stayed silent (it's inactive).
  print('after 2 orders: analytics=${_analytics.state}');

  // Flip the settings toggle — `whenStoreState` drives auditFeature to
  // `.active`, its `onStart` runs, future orders now trigger audit logs.
  _settings.toggleAudit();
  await Future<void>.delayed(Duration.zero); // let the cascade settle

  await _orders.placeOrder('o-3');
  // Prints: [audit] new order: o-3

  // Flip back — audit deactivates, its cleanup bag drains (LIFO), next
  // orders are silent again.
  _settings.toggleAudit();
  await Future<void>.delayed(Duration.zero);

  await _orders.placeOrder('o-4');
  print('after 4 orders: analytics=${_analytics.state}');

  await container.dispose();
}
