import 'package:armature/advanced.dart' show StateUpdateCallback;
import 'package:armature/armature.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'service_listeners.mocks.dart';

typedef TestState = ({int id});

class TaskParams {
  final int amount;

  const TaskParams(this.amount);
}

class TaskResult {
  final int receivedAmount;

  const TaskResult(this.receivedAmount);
}

class TestService extends Store<TestState> {
  final List<String> queueEvents = [];

  late final queueSequentialTask = createTask(
    fn: (int p) async {
      queueEvents.add('start:$p');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      queueEvents.add('end:$p');
      return p;
    },
    strategy: TaskStrategy.queue,
  );

  late final onceSuccessTask = createTask(
    fn: (TaskParams params) async {
      return TaskResult(params.amount);
    },
    strategy: TaskStrategy.once,
  );

  int onceCallCount = 0;

  late final onceCountedTask = createTask<int, int, Object>(
    fn: (p) async {
      onceCallCount++;
      return p * 2;
    },
    strategy: TaskStrategy.once,
  );

  int onceFailingCallCount = 0;

  late final onceSharedFailingTask = createTask<int, int, Object>(
    fn: (p) async {
      onceFailingCallCount++;
      throw StateError('attempt failed');
    },
    strategy: TaskStrategy.once,
  );

  late final onceSuccessDelayedTask = createTask(
    fn: (TaskParams params) async {
      await Future<void>.delayed(Duration(seconds: 1));

      return TaskResult(params.amount);
    },
    strategy: TaskStrategy.once,
  );

  late final onceFailTask = createTask(
    fn: (TaskParams params) async {
      if (params.amount == 1) {
        throw ArgumentError("Something went wrong");
      }
      return TaskResult(params.amount);
    },
    strategy: TaskStrategy.once,
  );

  late final queueSuccessTask = createTask(
    fn: (TaskParams params) async {
      return TaskResult(params.amount);
    },
    strategy: TaskStrategy.queue,
  );

  late final queueFailTask = createTask(
    fn: (TaskParams params) async {
      if (params.amount == 100) {
        throw ArgumentError("Something went wrong");
      }
    },
    strategy: TaskStrategy.queue,
  );

  /// Non-`async` function whose body is a raw `throw`. This is the
  /// edge case that bypasses the internal try/finally unless
  /// `_executeFn` wraps the call in `Future.sync`.
  late final syncThrowTask = createTask<int, int, Object>(
    fn: (int p) => throw StateError('sync-boom'),
    strategy: TaskStrategy.queue,
  );

  int latestCallCount = 0;

  late final latestTask = createTask<int, int, Object>(
    fn: (int p) async {
      latestCallCount++;
      await Future<void>.delayed(Duration(milliseconds: 40 - p * 5));
      return p * 100;
    },
    strategy: TaskStrategy.latest,
  );

  int debounceCallCount = 0;

  late final debounceTask = createTask<int, int, Object>(
    fn: (int p) async {
      debounceCallCount++;
      return p * 2;
    },
    strategy: TaskStrategy.debounce(Duration(milliseconds: 40)),
  );

  int throttleCallCount = 0;

  late final throttleTask = createTask<int, int, Object>(
    fn: (int p) async {
      throttleCallCount++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return p;
    },
    strategy: TaskStrategy.throttle(Duration(milliseconds: 60)),
  );

  TestService({required super.state});

  void setState(TestState newState) {
    state = newState;
  }

  void updateState(StateUpdateCallback<TestState> callback) {
    update(callback);
  }
}

void main() {
  group('service state tests', () {
    test('set state must update state', () {
      const initialState = (id: 0);

      var service = TestService(state: initialState);

      final nextState = (id: 1);

      service.setState(nextState);

      expect(service.state, equals(nextState));
    });

    test('update() must update state', () {
      const initialState = (id: 0);

      var service = TestService(state: initialState);

      service.updateState((state) => (id: state.id + 1));

      expect(service.state, equals((id: 1)));
    });

    test('subscribe() listener should call with prev and actual state', () {
      const initialState = (id: 0);
      final listeners = MockListeners();

      final service = TestService(state: initialState)
        ..subscribe(listeners.onChangeState);

      final nextState = (id: 1);

      service.setState(nextState);

      verify(listeners.onChangeState(initialState, nextState)).called(1);
    });
    test('subscribe() listener should call immediately', () {
      const initialState = (id: 0);
      final listeners = MockListeners();

      TestService(
        state: initialState,
      ).subscribe(listeners.onChangeState, fireImmediately: true);

      verify(listeners.onChangeState(initialState, initialState)).called(1);
    });

    test(
      'subscribe() the listener should not be called if the state has not changed',
      () {
        const initialState = (id: 0);
        final listeners = MockListeners();

        final service = TestService(state: initialState)
          ..subscribe(listeners.onChangeState);

        final nextState = (id: 0);

        service.setState(nextState);

        verifyNever(listeners.onChangeState(any, any)).called(0);
      },
    );
  });

  // Integration smoke tests: verify Store.createTask correctly
  // delegates to the underlying Task for every strategy, plus the
  // Store↔Task dispose cascade. Pure strategy mechanics (state
  // machine transitions, dispose rejection semantics, edge cases)
  // live in `task_strategy_test.dart` and exercise the `create` /
  // `createVoid` factories directly.
  group('Store × Task integration', () {
    test(
      'createTask() with "strategy: once" should call the function only once',
      () async {
        final service = TestService(state: const (id: 0));

        final results = await Future.wait([
          service.onceSuccessTask(const TaskParams(1)),
          service.onceSuccessTask(const TaskParams(2)),
          service.onceSuccessTask(const TaskParams(3)),
        ]);

        for (var result in results) {
          expect(result.receivedAmount, equals(1));
        }

        expect(
          service.onceSuccessTask.state,
          isA<TaskDone<TaskParams, TaskResult, Object?>>(),
        );

        await service.onceSuccessTask(const TaskParams(1));
      },
    );

    test('createTask() with "strategy: once" should throw error', () async {
      final service = TestService(state: const (id: 0));

      try {
        await service.onceFailTask(const TaskParams(1));
      } on Object catch (error) {
        expect(error, isA<ArgumentError>());
        final s = service.onceFailTask.state;
        expect(s, isA<TaskFailed<TaskParams, TaskResult, Object?>>());
        expect(
          (s as TaskFailed<TaskParams, TaskResult, Object?>).error,
          isA<ArgumentError>(),
        );
      }
      final result = await service.onceFailTask(const TaskParams(2));
      expect(result.receivedAmount, equals(2));
    });

    test(
      'createTask() with "strategy: once" should update pending state',
      () async {
        final service = TestService(state: const (id: 0));

        const params = TaskParams(1);
        final task = service.onceSuccessDelayedTask(params);

        final pending = service.onceSuccessDelayedTask.state;
        expect(pending, isA<TaskPending<TaskParams, TaskResult, Object?>>());
        expect(
          (pending as TaskPending<TaskParams, TaskResult, Object?>).params,
          params,
        );

        await task;

        // Successful completion transitions to TaskDone (not back to Idle).
        expect(
          service.onceSuccessDelayedTask.state,
          isA<TaskDone<TaskParams, TaskResult, Object?>>(),
        );
      },
    );

    test(
      'createTask() with "strategy: queue" must perform tasks in call order',
      () async {
        final service = TestService(state: const (id: 0));

        final results = await Future.wait([
          service.queueSuccessTask(const TaskParams(1)),
          service.queueSuccessTask(const TaskParams(2)),
          service.queueSuccessTask(const TaskParams(3)),
          service.queueSuccessTask(const TaskParams(4)),
        ]);

        expect(results[0].receivedAmount, equals(1));
        expect(results[1].receivedAmount, equals(2));
        expect(results[2].receivedAmount, equals(3));
        expect(results[3].receivedAmount, equals(4));
      },
    );

    test(
      'createTask() with "strategy: queue" runs tasks sequentially under real async',
      () async {
        final service = TestService(state: const (id: 0));

        await Future.wait([
          service.queueSequentialTask(1),
          service.queueSequentialTask(2),
          service.queueSequentialTask(3),
        ]);

        expect(
          service.queueEvents,
          equals(['start:1', 'end:1', 'start:2', 'end:2', 'start:3', 'end:3']),
        );
      },
    );

    test('createTask() with "strategy: queue" should throw error', () async {
      final service = TestService(state: const (id: 0));

      final List<TaskResult?> results = await Future.wait([
        service.queueSuccessTask(const TaskParams(1)),
        service.queueFailTask(const TaskParams(100)).catchError((
          Object? error,
        ) {
          expect(error, isA<ArgumentError>());
          expect(
            service.queueFailTask.state,
            isA<TaskFailed<TaskParams, void, Object?>>(),
          );
        }),
        service.queueSuccessTask(const TaskParams(3)),
      ]);

      expect(results.first?.receivedAmount, equals(1));
      expect(results.last?.receivedAmount, equals(3));
    });

    test(
      'once strategy calls fn exactly once across successful invocations',
      () async {
        final service = TestService(state: const (id: 0));

        final r1 = await service.onceCountedTask(1);
        final r2 = await service.onceCountedTask(2);
        final r3 = await service.onceCountedTask(3);

        expect(service.onceCallCount, equals(1));
        // All subsequent callers get the first successful result.
        expect(r1, equals(2));
        expect(r2, equals(2));
        expect(r3, equals(2));
      },
    );

    test('once: concurrent callers share the first failing attempt', () async {
      final service = TestService(state: const (id: 0));

      Future<Object?> attempt(int p) async {
        try {
          await service.onceSharedFailingTask(p);
          return null;
        } on Object catch (e) {
          return e;
        }
      }

      final results = await Future.wait([attempt(1), attempt(2), attempt(3)]);

      expect(service.onceFailingCallCount, equals(1));
      expect(results[0], isA<StateError>());
      expect(results[1], same(results[0]));
      expect(results[2], same(results[0]));
    });

    test(
      'queue: dispose while tasks in flight — pending complete, new calls throw',
      () async {
        final service = TestService(state: const (id: 0));

        final aFuture = service.queueSequentialTask(1);
        final bFuture = service.queueSequentialTask(2);

        // Let A start running.
        await Future<void>.delayed(const Duration(milliseconds: 5));

        service.queueSequentialTask.dispose();

        // In-flight / already-queued calls complete normally.
        expect(await aFuture, equals(1));
        expect(await bFuture, equals(2));

        // New call() after dispose throws TaskError.
        expect(() => service.queueSequentialTask(3), throwsA(isA<TaskError>()));
      },
    );

    test(
      'sync-throwing fn still settles pending state and releases the queue',
      () async {
        final service = TestService(state: const (id: 0));

        Object? caught;
        try {
          await service.syncThrowTask(1);
        } on Object catch (e) {
          caught = e;
        }
        expect(caught, isA<StateError>());
        // syncThrowTask declares TError=Object, so StateError matches
        // → terminal state is TaskFailed (not TaskPending).
        expect(
          service.syncThrowTask.state,
          isA<TaskFailed<int, int, Object>>(),
        );

        // Queue must be usable for subsequent calls too.
        Object? second;
        try {
          await service.syncThrowTask(2);
        } on Object catch (e) {
          second = e;
        }
        expect(second, isA<StateError>());
        expect(
          service.syncThrowTask.state,
          isA<TaskFailed<int, int, Object>>(),
        );
      },
    );

    test('Store.dispose cascades to owned tasks', () async {
      final service = TestService(state: const (id: 0));

      await service.onceSuccessTask(const TaskParams(1));
      service.dispose();

      expect(
        () => service.onceSuccessTask(const TaskParams(2)),
        throwsA(isA<TaskError>()),
      );
    });

    test(
      'Store.createTask with .latest: all pending callers share the latest result',
      () async {
        final service = TestService(state: const (id: 0));

        final f1 = service.latestTask(1);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final f2 = service.latestTask(2);

        expect(await f1, equals(200));
        expect(await f2, equals(200));
        expect(service.latestCallCount, equals(2));
      },
    );

    test('Store.createTask with .debounce coalesces a burst', () async {
      final service = TestService(state: const (id: 0));

      final results = await Future.wait([
        service.debounceTask(1),
        service.debounceTask(2),
        service.debounceTask(3),
      ]);
      expect(results, equals([6, 6, 6]));
      expect(service.debounceCallCount, equals(1));
    });

    test('Store.createTask with .throttle runs one per window', () async {
      final service = TestService(state: const (id: 0));

      final f1 = service.throttleTask(1);
      final f2 = service.throttleTask(2);
      expect(await f1, equals(1));
      expect(await f2, equals(1));
      expect(service.throttleCallCount, equals(1));
    });

    test(
      'Store.dispose cascades to debounce task and rejects its future',
      () async {
        final service = TestService(state: const (id: 0));

        final f = service.debounceTask(1);
        service.dispose();

        Object? caught;
        try {
          await f;
        } on Object catch (e) {
          caught = e;
        }
        expect(caught, isA<TaskError>());
      },
    );
  });
}
