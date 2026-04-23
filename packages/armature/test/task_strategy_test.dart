import 'package:armature/armature.dart';
import 'package:armature/src/store/task.dart' show create, createVoid;
import 'package:test/test.dart';

Task<TParams, TResult, Object> makeTask<TParams, TResult>({
  required Future<TResult> Function(TParams) fn,
  required TaskStrategy strategy,
}) {
  return create<TParams, TResult, Object>(fn: fn, strategy: strategy);
}

VoidTask<TResult, Object> makeVoidTask<TResult>({
  required Future<TResult> Function() fn,
  required TaskStrategy strategy,
}) {
  return createVoid<TResult, Object>(fn: fn, strategy: strategy);
}

void main() {
  group('TaskStrategy sealed hierarchy', () {
    test('.once / .queue / .latest resolve to the expected variants', () {
      expect(TaskStrategy.once, isA<TaskStrategyOnce>());
      expect(TaskStrategy.queue, isA<TaskStrategyQueue>());
      expect(TaskStrategy.latest, isA<TaskStrategyLatest>());
    });

    test('.debounce / .throttle factory constructors', () {
      const d = TaskStrategy.debounce(Duration(milliseconds: 250));
      expect(d, isA<TaskStrategyDebounce>());
      expect((d as TaskStrategyDebounce).duration.inMilliseconds, equals(250));

      const t = TaskStrategy.throttle(Duration(milliseconds: 500));
      expect(t, isA<TaskStrategyThrottle>());
      expect((t as TaskStrategyThrottle).edge, equals(ThrottleEdge.leading));
    });

    test('dot-shorthand resolves to the static constants', () {
      const TaskStrategy s1 = TaskStrategy.once;
      expect(s1, isA<TaskStrategyOnce>());

      const TaskStrategy s2 = TaskStrategy.debounce(Duration(milliseconds: 10));
      expect(s2, isA<TaskStrategyDebounce>());
    });
  });

  group('TaskStrategy.latest', () {
    test('superseded callers share the latest run result', () async {
      var delay = const Duration(milliseconds: 80);
      final task = makeTask<int, int>(
        fn: (p) async {
          await Future<void>.delayed(delay);
          delay = const Duration(milliseconds: 10);
          return p;
        },
        strategy: TaskStrategy.latest,
      );

      final f1 = task(1);
      // Stagger the second call so the first is still in-flight.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final f2 = task(2);

      final r1 = await f1;
      final r2 = await f2;
      expect(r1, equals(2));
      expect(r2, equals(2));
    });

    test('state reflects only the latest run result', () async {
      final task = makeTask<int, int>(
        fn: (p) async {
          await Future<void>.delayed(Duration(milliseconds: 40 - p * 5));
          return p * 10;
        },
        strategy: TaskStrategy.latest,
      );

      final results = await Future.wait([task(1), task(2), task(3)]);
      expect(results, equals([30, 30, 30]));
      expect(task.state.state, equals(const TaskDone<int, int, Object>(30)));
    });

    test(
      'state transitions are intermediate TaskPending(params_latest)',
      () async {
        final task = makeTask<int, int>(
          fn: (p) async {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            return p;
          },
          strategy: TaskStrategy.latest,
        );

        final f1 = task(1);
        expect(
          task.state.state,
          equals(const TaskPending<int, int, Object>(1)),
        );
        final f2 = task(2);
        expect(
          task.state.state,
          equals(const TaskPending<int, int, Object>(2)),
        );

        final r1 = await f1;
        final r2 = await f2;
        expect(r1, equals(2));
        expect(r2, equals(2));
      },
    );

    test('dispose during in-flight rejects pending future', () async {
      final task = makeTask<int, int>(
        fn: (p) async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return p;
        },
        strategy: TaskStrategy.latest,
      );
      final f = task(1);
      task.dispose();

      Object? caught;
      try {
        await f;
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isA<TaskError>());
    });

    test('TError throw records TaskFailed on the latest run', () async {
      final task = makeTask<int, int>(
        fn: (p) async {
          if (p == 2) throw ArgumentError('bad $p');
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return p;
        },
        strategy: TaskStrategy.latest,
      );

      Object? caught;
      try {
        await task(2);
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isA<ArgumentError>());
      expect(task.state.state, isA<TaskFailed<int, int, Object>>());
    });
  });

  group('TaskStrategy.debounce', () {
    test(
      'coalesces a burst into a single execution with the last params',
      () async {
        var callCount = 0;
        final task = makeTask<int, int>(
          fn: (p) async {
            callCount++;
            return p;
          },
          strategy: const TaskStrategy.debounce(Duration(milliseconds: 60)),
        );

        final f1 = task(1);
        final f2 = task(2);
        final f3 = task(3);

        final results = await Future.wait([f1, f2, f3]);
        expect(callCount, equals(1));
        expect(results, equals([3, 3, 3]));
        expect(task.state.state, equals(const TaskDone<int, int, Object>(3)));
      },
    );

    test(
      'state transitions to TaskPending(latestParams) while the timer is waiting',
      () async {
        final task = makeTask<int, int>(
          fn: (p) async => p,
          strategy: const TaskStrategy.debounce(Duration(milliseconds: 50)),
        );

        final f = task(1);
        expect(
          task.state.state,
          equals(const TaskPending<int, int, Object>(1)),
        );

        // A second call before the timer fires updates the pending params.
        final f2 = task(42);
        expect(
          task.state.state,
          equals(const TaskPending<int, int, Object>(42)),
        );

        await f;
        await f2;
        expect(task.state.state, equals(const TaskDone<int, int, Object>(42)));
      },
    );

    test('new cycle after completion starts fresh', () async {
      var callCount = 0;
      final task = makeTask<int, int>(
        fn: (p) async {
          callCount++;
          return p * 100;
        },
        strategy: const TaskStrategy.debounce(Duration(milliseconds: 30)),
      );

      expect(await task(1), equals(100));
      expect(await task(2), equals(200));
      expect(callCount, equals(2));
    });

    test('dispose cancels pending timer and rejects future', () async {
      final task = makeTask<int, int>(
        fn: (p) async => p,
        strategy: const TaskStrategy.debounce(Duration(milliseconds: 200)),
      );

      final f = task(1);
      task.dispose();

      Object? caught;
      try {
        await f;
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isA<TaskError>());
    });

    test(
      'TError thrown during the debounced run lands in TaskFailed',
      () async {
        final task = makeTask<int, int>(
          fn: (p) async => throw ArgumentError('bad'),
          strategy: const TaskStrategy.debounce(Duration(milliseconds: 20)),
        );

        Object? caught;
        try {
          await task(1);
        } on Object catch (e) {
          caught = e;
        }
        expect(caught, isA<ArgumentError>());
        expect(task.state.state, isA<TaskFailed<int, int, Object>>());
      },
    );
  });

  group('TaskStrategy.throttle (leading)', () {
    test('leading edge runs first call immediately', () async {
      var callCount = 0;
      final task = makeTask<int, int>(
        fn: (p) async {
          callCount++;
          return p;
        },
        strategy: const TaskStrategy.throttle(Duration(milliseconds: 50)),
      );

      expect(await task(7), equals(7));
      expect(callCount, equals(1));
    });

    test('calls during cooldown share the in-flight future', () async {
      var callCount = 0;
      final task = makeTask<int, int>(
        fn: (p) async {
          callCount++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return p;
        },
        strategy: const TaskStrategy.throttle(Duration(milliseconds: 80)),
      );

      final f1 = task(1);
      final f2 = task(2);
      final f3 = task(3);
      expect(await f1, equals(1));
      expect(await f2, equals(1));
      expect(await f3, equals(1));
      expect(callCount, equals(1));
    });

    test('after cooldown elapses, next call executes fresh', () async {
      var callCount = 0;
      final task = makeTask<int, int>(
        fn: (p) async {
          callCount++;
          return p;
        },
        strategy: const TaskStrategy.throttle(Duration(milliseconds: 40)),
      );

      expect(await task(1), equals(1));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(await task(2), equals(2));
      expect(callCount, equals(2));
    });
  });

  group('TaskStrategy.throttle (trailing)', () {
    test(
      'trailing: coalesces window calls into one run with the latest params',
      () async {
        var callCount = 0;
        int? lastSeen;
        final task = makeTask<int, int>(
          fn: (p) async {
            callCount++;
            lastSeen = p;
            return p;
          },
          strategy: const TaskStrategy.throttle(
            Duration(milliseconds: 60),
            edge: ThrottleEdge.trailing,
          ),
        );

        final f1 = task(1);
        final f2 = task(2);
        final f3 = task(3);
        final results = await Future.wait([f1, f2, f3]);

        expect(callCount, equals(1));
        expect(lastSeen, equals(3));
        expect(results, equals([3, 3, 3]));
      },
    );

    test(
      'trailing: state is TaskPending(latestParams) during the window',
      () async {
        final task = makeTask<int, int>(
          fn: (p) async => p,
          strategy: const TaskStrategy.throttle(
            Duration(milliseconds: 50),
            edge: ThrottleEdge.trailing,
          ),
        );

        final f = task(1);
        expect(
          task.state.state,
          equals(const TaskPending<int, int, Object>(1)),
        );
        final f2 = task(2);
        expect(
          task.state.state,
          equals(const TaskPending<int, int, Object>(2)),
        );

        await f;
        await f2;
        expect(task.state.state, equals(const TaskDone<int, int, Object>(2)));
      },
    );

    test(
      'trailing: after the window fires, a new call starts a new window',
      () async {
        var callCount = 0;
        final task = makeTask<int, int>(
          fn: (p) async {
            callCount++;
            return p;
          },
          strategy: const TaskStrategy.throttle(
            Duration(milliseconds: 30),
            edge: ThrottleEdge.trailing,
          ),
        );

        expect(await task(1), equals(1));
        expect(await task(2), equals(2));
        expect(callCount, equals(2));
      },
    );

    test(
      'trailing: dispose cancels the window and rejects pending future',
      () async {
        final task = makeTask<int, int>(
          fn: (p) async => p,
          strategy: const TaskStrategy.throttle(
            Duration(milliseconds: 200),
            edge: ThrottleEdge.trailing,
          ),
        );

        final f = task(1);
        task.dispose();

        Object? caught;
        try {
          await f;
        } on Object catch (e) {
          caught = e;
        }
        expect(caught, isA<TaskError>());
      },
    );

    test(
      'trailing: TError thrown during the run lands in TaskFailed',
      () async {
        final task = makeTask<int, int>(
          fn: (p) async => throw ArgumentError('bad'),
          strategy: const TaskStrategy.throttle(
            Duration(milliseconds: 20),
            edge: ThrottleEdge.trailing,
          ),
        );

        Object? caught;
        try {
          await task(1);
        } on Object catch (e) {
          caught = e;
        }
        expect(caught, isA<ArgumentError>());
        expect(task.state.state, isA<TaskFailed<int, int, Object>>());
      },
    );
  });

  group('backward-compat: .once and .queue unchanged', () {
    test('.once still caches first result', () async {
      var callCount = 0;
      final task = makeTask<int, int>(
        fn: (p) async {
          callCount++;
          return p * 2;
        },
        strategy: TaskStrategy.once,
      );
      expect(await task(5), equals(10));
      expect(await task(6), equals(10));
      expect(callCount, equals(1));
    });

    test('.queue still runs tasks in order', () async {
      final log = <int>[];
      final task = makeTask<int, int>(
        fn: (p) async {
          log.add(p);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return p;
        },
        strategy: TaskStrategy.queue,
      );

      await Future.wait([task(1), task(2), task(3)]);
      expect(log, equals([1, 2, 3]));
    });
  });

  group('VoidTask with new strategies', () {
    test('VoidTask.latest shares the latest run result', () async {
      var callCount = 0;
      final task = makeVoidTask<int>(
        fn: () async {
          callCount++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return callCount;
        },
        strategy: TaskStrategy.latest,
      );

      final f1 = task();
      final f2 = task();
      expect(await f1, equals(2));
      expect(await f2, equals(2));
    });

    test('VoidTask.debounce coalesces', () async {
      var callCount = 0;
      final task = makeVoidTask<int>(
        fn: () async {
          callCount++;
          return callCount;
        },
        strategy: const TaskStrategy.debounce(Duration(milliseconds: 30)),
      );

      final f1 = task();
      final f2 = task();
      final f3 = task();
      final results = await Future.wait([f1, f2, f3]);
      expect(callCount, equals(1));
      expect(results, equals([1, 1, 1]));
    });
  });
}
