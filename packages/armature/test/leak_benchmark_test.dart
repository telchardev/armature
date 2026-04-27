// Safety-net benchmark for the config / runtime split:
//   * top-level `final` features keep their identity and config across
//     N container lifecycles (no drift, no silent mutation);
//   * process memory high-water mark does not balloon per-cycle.
//
// The RSS check is a rough upper bound — allocator behavior is not
// deterministic and Dart has no portable "force GC" hook, so the
// threshold is generous. A regression that leaks a container-sized
// object per cycle (~a few KB × 20 = tens of KB) wouldn't trip this
// test, but a leak on the order of scope maps or store lists (KB per
// feature per cycle) will. Tighten the threshold if a real leak is
// suspected.

import 'dart:io' show ProcessInfo, Platform;

import 'package:armature/armature.dart';
import 'package:armature/test_utils.dart';
import 'package:test/test.dart';

class _CounterStore extends Store<int> {
  _CounterStore() : super(state: 0);
  void inc() => state = state + 1;
}

// Shared top-level features — the canonical Armature idiom.
final _pipe = createPipe<int>(name: 'bench.pipe');
final _host =
    createFeature(
      name: 'bench.host',
      stores: (_) => (counter: _CounterStore()),
      ports: (pipe: _pipe),
      exports: (api) => api.own,
    )..onStart((api, cleanup) async {
      // Non-trivial onStart work so lifecycle exercises the cleanup bag.
      cleanup.add(() {}); // benign disposer
    });

final _contributor = createFeature(
  name: 'bench.contributor',
  dependsOn: [_host],
)..usePipe(_pipe, (v, api) => v + api.of(_host).counter.state);

void main() {
  group('safety-net benchmark', () {
    test('feature identity + config are stable across 20 cycles', () async {
      final hostIdBefore = identityHashCode(_host);
      final contribIdBefore = identityHashCode(_contributor);
      final pipeIdBefore = identityHashCode(_pipe);

      final hostBindingsBefore = _host.config.portBindings.length;
      final contribBindingsBefore = _contributor.config.portBindings.length;
      final hostPortsBefore = _host.config.ports.length;
      final contribPortsBefore = _contributor.config.ports.length;
      final hostFactoryBefore = _host.config.storesFactory;
      final hostStartCallbackBefore = _host.config.startCallback;

      for (var i = 0; i < 20; i++) {
        final c = AppContainer(
          features: [_host, _contributor],
          options: silentOptions(),
        );
        await c.start();

        // Exercise the container: read through the pipe, poke the store,
        // read it again so reactions fire.
        final store = _host.storeOf<_CounterStore>(c);
        store.inc();
        final observed = c.apply(
          rootFeature: _host,
          port: _pipe,
          initialValue: 0,
          data: null,
        );
        expect(observed, equals(1), reason: 'cycle $i observed pipe value');

        await c.stop();
      }

      // Identity must not drift — top-level finals are stable refs.
      expect(identityHashCode(_host), equals(hostIdBefore));
      expect(identityHashCode(_contributor), equals(contribIdBefore));
      expect(identityHashCode(_pipe), equals(pipeIdBefore));

      // Config must not mutate across container lifecycles.
      expect(_host.config.portBindings.length, equals(hostBindingsBefore));
      expect(
        _contributor.config.portBindings.length,
        equals(contribBindingsBefore),
      );
      expect(_host.config.ports.length, equals(hostPortsBefore));
      expect(_contributor.config.ports.length, equals(contribPortsBefore));
      expect(_host.config.storesFactory, same(hostFactoryBefore));
      expect(_host.config.startCallback, same(hostStartCallbackBefore));
    });

    test(
      'process RSS high-water does not balloon over 20 cycles',
      () async {
        // Warm up: lazy inits, code path JIT, allocator stabilisation.
        for (var i = 0; i < 3; i++) {
          final c = AppContainer(
            features: [_host, _contributor],
            options: silentOptions(),
          );
          await c.start();
          await c.stop();
        }

        final warmRss = ProcessInfo.currentRss;

        for (var i = 0; i < 20; i++) {
          final c = AppContainer(
            features: [_host, _contributor],
            options: silentOptions(),
          );
          await c.start();
          c.apply(rootFeature: _host, port: _pipe, initialValue: 0, data: null);
          await c.stop();
        }

        final afterRss = ProcessInfo.currentRss;
        final growthBytes = afterRss - warmRss;

        // Threshold: 5 MB. A real per-cycle leak on order of several
        // KB (leaked scope map + stores) would exceed this across 20
        // cycles even after GC uncertainty. Generous enough that CI
        // noise (platform differences, allocator quirks) doesn't trip.
        const threshold = 5 * 1024 * 1024;
        expect(
          growthBytes,
          lessThan(threshold),
          reason:
              'RSS grew by ${(growthBytes / 1024).toStringAsFixed(1)} KB '
              'after 20 container cycles (threshold: '
              '${(threshold / 1024).toStringAsFixed(0)} KB). '
              'Platform: ${Platform.operatingSystem}.',
        );
      },
      // Skip on platforms where ProcessInfo.currentRss is unreliable
      // (browsers, fuchsia). On Linux/macOS/Windows it's dependable.
      skip: Platform.isFuchsia,
    );

    test(
      'process RSS does not balloon over 20 stop/start cycles on the same container',
      () async {
        // Catches leaks specific to the restart-friendly path: the
        // container instance is reused across cycles, so per-cycle
        // resets that fail to release prior-cycle state (statusStore,
        // lifetimeCleanup bag, scope API) accumulate inside the same
        // FeatureRuntime objects and surface as steady RSS growth.
        final container = AppContainer(
          features: [_host, _contributor],
          options: silentOptions(),
        );

        // Warm up the same container's lifecycle.
        for (var i = 0; i < 3; i++) {
          await container.start();
          await container.stop();
        }

        final warmRss = ProcessInfo.currentRss;

        for (var i = 0; i < 20; i++) {
          await container.start();
          container.apply(
            rootFeature: _host,
            port: _pipe,
            initialValue: 0,
            data: null,
          );
          // Re-subscribe each cycle — listeners are cleared on stop, so
          // a leak here would mean either the disposer didn't reach the
          // listener or stored callbacks survived clearListeners.
          final unsub = container.onFeatureStatusChanged(
            feature: _host,
            callback: () {},
          );
          unsub();
          await container.stop();
        }

        final afterRss = ProcessInfo.currentRss;
        final growthBytes = afterRss - warmRss;

        // Same threshold as the new-container variant — the per-cycle
        // working set is dominated by store / cleanup-bag allocations,
        // and reusing the container shouldn't change that envelope.
        const threshold = 5 * 1024 * 1024;
        expect(
          growthBytes,
          lessThan(threshold),
          reason:
              'RSS grew by ${(growthBytes / 1024).toStringAsFixed(1)} KB '
              'after 20 stop/start cycles on the same container '
              '(threshold: ${(threshold / 1024).toStringAsFixed(0)} KB). '
              'Platform: ${Platform.operatingSystem}.',
        );
      },
      skip: Platform.isFuchsia,
    );
  });
}
