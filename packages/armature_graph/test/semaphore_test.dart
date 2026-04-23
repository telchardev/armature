import 'dart:async';

import 'package:armature_graph/src/semaphore.dart';
import 'package:test/test.dart';

void main() {
  group('Semaphore', () {
    test('run executes fn and returns its result', () async {
      final sem = Semaphore(1);
      final result = await sem.run<int>(() async => 42);
      expect(result, equals(42));
    });

    test('limits concurrent in-flight to max', () async {
      final sem = Semaphore(2);
      var inFlight = 0;
      var maxObserved = 0;

      Future<void> slow() async {
        inFlight++;
        if (inFlight > maxObserved) maxObserved = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        inFlight--;
      }

      await Future.wait([for (var i = 0; i < 5; i++) sem.run(slow)]);

      expect(maxObserved, lessThanOrEqualTo(2));
      expect(maxObserved, greaterThan(0));
    });

    test('releases a waiter in FIFO order', () async {
      final sem = Semaphore(1);
      final order = <int>[];

      // Hold the only slot.
      final holdCompleter = Completer<void>();
      // ignore: unawaited_futures
      sem.run(() => holdCompleter.future);

      // Queue three waiters.
      final futures = <Future<void>>[];
      for (var i = 0; i < 3; i++) {
        final index = i;
        futures.add(
          sem.run(() async {
            order.add(index);
          }),
        );
      }

      // Release the holder → FIFO drain.
      holdCompleter.complete();
      await Future.wait(futures);

      expect(order, equals([0, 1, 2]));
    });

    test('fn that throws releases the slot', () async {
      final sem = Semaphore(1);

      Object? caught;
      try {
        await sem.run<void>(() => throw StateError('boom'));
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isA<StateError>());

      // Next call must proceed without deadlock.
      final result = await sem.run<int>(() async => 7);
      expect(result, equals(7));
    });

    test('drain() releases queued waiters without deadlock', () async {
      final sem = Semaphore(1);

      // Hold the only slot.
      final holder = Completer<void>();
      // ignore: unawaited_futures
      sem.run(() => holder.future);

      final waited = <int>[];
      final futures = [
        for (var i = 0; i < 3; i++)
          sem.run(() async {
            waited.add(i);
          }),
      ];

      // Drain before the holder finishes — queued waiters wake up.
      sem.drain();

      // All queued callers resolve.
      await Future.wait(futures);
      expect(waited, hasLength(3));

      // Release holder so its future completes cleanly.
      holder.complete();
    });

    test('calls made after drain bypass the gate (no blocking)', () async {
      final sem = Semaphore(1);
      sem.drain();

      final results = await Future.wait([
        for (var i = 0; i < 3; i++) sem.run<int>(() async => i),
      ]);

      expect(results, equals([0, 1, 2]));
    });

    test('max must be > 0 (ArgumentError)', () {
      expect(() => Semaphore(0), throwsA(isA<ArgumentError>()));
      expect(() => Semaphore(-1), throwsA(isA<ArgumentError>()));
    });
  });
}
