import 'dart:async';

import 'package:armature/armature.dart' show Store;
import 'package:armature/src/feature/cleanup.dart';
import 'package:test/test.dart';

/// Helper: builds a bag with a collecting error sink.
({CleanupBag bag, List<Object> errors}) _bag() {
  final errors = <Object>[];
  final bag = CleanupBag(onError: (e, _) => errors.add(e));
  return (bag: bag, errors: errors);
}

void main() {
  group('CleanupBag', () {
    test('runs disposers in LIFO order', () async {
      final (:bag, :errors) = _bag();
      final order = <int>[];
      bag.add(() => order.add(1));
      bag.add(() => order.add(2));
      bag.add(() => order.add(3));

      await bag.runAll();

      expect(order, equals([3, 2, 1]));
      expect(errors, isEmpty);
    });

    test('sequentially awaits async disposers (no overlap)', () async {
      final bag = _bag().bag;
      final events = <String>[];
      bag.add(() async {
        events.add('a-start');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        events.add('a-end');
      });
      bag.add(() async {
        events.add('b-start');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        events.add('b-end');
      });

      await bag.runAll();

      // LIFO: b runs first to completion, then a.
      expect(events, equals(['b-start', 'b-end', 'a-start', 'a-end']));
    });

    test('runAll is idempotent — second call is a no-op', () async {
      final bag = _bag().bag;
      var calls = 0;
      bag.add(() => calls++);

      await bag.runAll();
      await bag.runAll();

      expect(calls, equals(1));
    });

    test(
      'disposer throw is routed via onError and does not stop the chain',
      () async {
        final (:bag, :errors) = _bag();
        final reached = <int>[];
        bag.add(() => reached.add(1));
        bag.add(() => throw StateError('middle fail'));
        bag.add(() => reached.add(3));

        await bag.runAll();

        // LIFO: 3 runs, then throwing disposer, then 1 still runs.
        expect(reached, equals([3, 1]));
        expect(errors.single, isA<StateError>());
      },
    );

    test(
      'async disposer rejection is routed via onError and chain continues',
      () async {
        final (:bag, :errors) = _bag();
        final reached = <int>[];
        bag.add(() => reached.add(1));
        bag.add(() async => throw StateError('async fail'));
        bag.add(() => reached.add(3));

        await bag.runAll();

        expect(reached, equals([3, 1]));
        expect(errors.single, isA<StateError>());
      },
    );

    test(
      'late add after runAll fires the disposer immediately (sync)',
      () async {
        final bag = _bag().bag;
        await bag.runAll();

        var called = false;
        bag.add(() => called = true);
        expect(called, isTrue);
      },
    );

    test(
      'late add of an async disposer is fire-and-forget and routes errors',
      () async {
        final (:bag, :errors) = _bag();
        await bag.runAll();

        bag.add(() async {
          throw StateError('late async fail');
        });

        // add() is sync and must have returned; give the microtask queue
        // a tick so the fire-and-forget rejection lands in onError.
        await Future<void>.delayed(Duration.zero);
        expect(errors.single, isA<StateError>());
      },
    );

    test(
      'CleanupBag.sealed acts as a no-op default — runAll does nothing',
      () async {
        final bag = CleanupBag.sealed();
        var called = false;
        // Late-add still fires immediately even without onError.
        bag.add(() => called = true);
        expect(called, isTrue);

        // runAll on sealed is a no-op.
        await expectLater(bag.runAll(), completes);
      },
    );

    test('CleanupBag.sealed with onError routes late-add errors', () async {
      final errors = <Object>[];
      final bag = CleanupBag.sealed(onError: (e, _) => errors.add(e));

      bag.add(() => throw StateError('late sync fail'));
      bag.add(() async => throw StateError('late async fail'));

      // Async late-add uses catchError which runs on a microtask boundary.
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(2));
      expect(errors.every((e) => e is StateError), isTrue);
    });

    test(
      'disposer that re-enters runAll short-circuits (no recursive drain)',
      () async {
        final bag = _bag().bag;
        final order = <int>[];
        bag.add(() {
          order.add(1);
          // Re-entering `runAll` from within a disposer is safe — the
          // idempotent guard returns immediately.
          bag.runAll();
          order.add(2);
        });
        await bag.runAll();

        expect(order, equals([1, 2]));
      },
    );

    test(
      'disposer that adds another during runAll fires the new one immediately',
      () async {
        final bag = _bag().bag;
        final order = <String>[];
        bag.add(() {
          order.add('outer');
          // At this point the bag has already marked itself sealed —
          // late-add therefore fires the disposer in-place.
          bag.add(() => order.add('late'));
        });

        await bag.runAll();

        expect(order, equals(['outer', 'late']));
      },
    );
  });

  group('Cleanup.subscribe', () {
    test('forwards listener and cancels on runAll', () async {
      final bag = _bag().bag;
      final store = _CounterStore();
      final received = <int>[];

      bag.subscribe(store, (_, next) => received.add(next));

      store.increment();
      store.increment();
      expect(received, equals([1, 2]));

      await bag.runAll();
      store.increment();
      expect(received, equals([1, 2]), reason: 'should not fire after runAll');
    });

    test('fireImmediately forwards to Store.subscribe', () async {
      final bag = _bag().bag;
      final store = _CounterStore();
      final received = <int>[];

      bag.subscribe(
        store,
        (_, next) => received.add(next),
        fireImmediately: true,
      );

      // Initial state (0) seeded once.
      expect(received, equals([0]));

      store.increment();
      expect(received, equals([0, 1]));

      await bag.runAll();
    });
  });

  group('Cleanup.periodic', () {
    test('fires repeatedly until runAll cancels the timer', () async {
      final bag = _bag().bag;
      var ticks = 0;
      bag.periodic(const Duration(milliseconds: 10), () => ticks++);

      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(
        ticks,
        greaterThanOrEqualTo(2),
        reason: 'at least 2 ticks should fire in ~35ms with 10ms interval',
      );

      await bag.runAll();
      final after = ticks;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        ticks,
        equals(after),
        reason: 'no more ticks should fire after runAll',
      );
    });
  });

  group('Cleanup.listen', () {
    test('forwards stream events; cancels subscription on runAll', () async {
      final bag = _bag().bag;
      final controller = StreamController<int>();
      final received = <int>[];

      bag.listen(controller.stream, received.add);

      controller.add(1);
      controller.add(2);
      await Future<void>.delayed(Duration.zero);
      expect(received, equals([1, 2]));

      await bag.runAll();
      controller.add(3);
      await Future<void>.delayed(Duration.zero);
      expect(
        received,
        equals([1, 2]),
        reason: 'subscription should be cancelled after runAll',
      );

      await controller.close();
    });

    test('forwards onError / onDone / cancelOnError', () async {
      final bag = _bag().bag;
      final controller = StreamController<int>();
      final received = <int>[];
      final errors = <Object>[];
      var done = false;

      bag.listen(
        controller.stream,
        received.add,
        onError: (Object error) => errors.add(error),
        onDone: () => done = true,
        cancelOnError: false,
      );

      controller.add(1);
      controller.addError(StateError('boom'));
      controller.add(2);
      await controller.close();
      await Future<void>.delayed(Duration.zero);

      expect(received, equals([1, 2]));
      expect(errors.single, isA<StateError>());
      expect(done, isTrue);

      await bag.runAll();
    });
  });
}

/// Minimal Store for testing the helpers — no feature wiring needed.
class _CounterStore extends Store<int> {
  _CounterStore() : super(state: 0);

  void increment() {
    state = state + 1;
  }
}
