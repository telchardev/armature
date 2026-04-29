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

/// Tiny store used by the `subscribeSelect` content-equality test. Keeps
/// a `List<int>` and exposes a setter that replaces the underlying
/// list reference on every call — verifies that without a content-
/// aware `equals`, identity-based `==` would fire on each write.
class _ItemsStore extends Store<List<int>> {
  _ItemsStore({required List<int> items}) : super(state: items);

  void replaceItems(List<int> next) => state = List<int>.of(next);
}

class TestStore extends Store<TestState> {
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

  TestStore({required super.state});

  void setState(TestState newState) {
    state = newState;
  }

  void updateState(StateUpdateCallback<TestState> callback) {
    update(callback);
  }
}

void main() {
  group('stores state tests', () {
    test('set state must update state', () {
      const initialState = (id: 0);

      var store = TestStore(state: initialState);

      final nextState = (id: 1);

      store.setState(nextState);

      expect(store.state, equals(nextState));
    });

    test('update() must update state', () {
      const initialState = (id: 0);

      var store = TestStore(state: initialState);

      store.updateState((state) => (id: state.id + 1));

      expect(store.state, equals((id: 1)));
    });

    test('subscribe() listener should call with prev and actual state', () {
      const initialState = (id: 0);
      final listeners = MockListeners();

      final store = TestStore(state: initialState)
        ..subscribe(listeners.onChangeState);

      final nextState = (id: 1);

      store.setState(nextState);

      verify(listeners.onChangeState(initialState, nextState)).called(1);
    });
    test('subscribe() listener should call immediately', () {
      const initialState = (id: 0);
      final listeners = MockListeners();

      TestStore(
        state: initialState,
      ).subscribe(listeners.onChangeState, fireImmediately: true);

      verify(listeners.onChangeState(initialState, initialState)).called(1);
    });

    test(
      'subscribe() the listener should not be called if the state has not changed',
      () {
        const initialState = (id: 0);
        final listeners = MockListeners();

        final store = TestStore(state: initialState)
          ..subscribe(listeners.onChangeState);

        final nextState = (id: 0);

        store.setState(nextState);

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
        final store = TestStore(state: const (id: 0));

        final results = await Future.wait([
          store.onceSuccessTask(const TaskParams(1)),
          store.onceSuccessTask(const TaskParams(2)),
          store.onceSuccessTask(const TaskParams(3)),
        ]);

        for (var result in results) {
          expect(result.receivedAmount, equals(1));
        }

        expect(
          store.onceSuccessTask.state,
          isA<TaskDone<TaskParams, TaskResult, Object?>>(),
        );

        await store.onceSuccessTask(const TaskParams(1));
      },
    );

    test('createTask() with "strategy: once" should throw error', () async {
      final store = TestStore(state: const (id: 0));

      try {
        await store.onceFailTask(const TaskParams(1));
      } on Object catch (error) {
        expect(error, isA<ArgumentError>());
        final s = store.onceFailTask.state;
        expect(s, isA<TaskFailed<TaskParams, TaskResult, Object?>>());
        expect(
          (s as TaskFailed<TaskParams, TaskResult, Object?>).error,
          isA<ArgumentError>(),
        );
      }
      final result = await store.onceFailTask(const TaskParams(2));
      expect(result.receivedAmount, equals(2));
    });

    test(
      'createTask() with "strategy: once" should update pending state',
      () async {
        final store = TestStore(state: const (id: 0));

        const params = TaskParams(1);
        final task = store.onceSuccessDelayedTask(params);

        final pending = store.onceSuccessDelayedTask.state;
        expect(pending, isA<TaskPending<TaskParams, TaskResult, Object?>>());
        expect(
          (pending as TaskPending<TaskParams, TaskResult, Object?>).params,
          params,
        );

        await task;

        // Successful completion transitions to TaskDone (not back to Idle).
        expect(
          store.onceSuccessDelayedTask.state,
          isA<TaskDone<TaskParams, TaskResult, Object?>>(),
        );
      },
    );

    test(
      'createTask() with "strategy: queue" must perform tasks in call order',
      () async {
        final store = TestStore(state: const (id: 0));

        final results = await Future.wait([
          store.queueSuccessTask(const TaskParams(1)),
          store.queueSuccessTask(const TaskParams(2)),
          store.queueSuccessTask(const TaskParams(3)),
          store.queueSuccessTask(const TaskParams(4)),
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
        final store = TestStore(state: const (id: 0));

        await Future.wait([
          store.queueSequentialTask(1),
          store.queueSequentialTask(2),
          store.queueSequentialTask(3),
        ]);

        expect(
          store.queueEvents,
          equals(['start:1', 'end:1', 'start:2', 'end:2', 'start:3', 'end:3']),
        );
      },
    );

    test('createTask() with "strategy: queue" should throw error', () async {
      final store = TestStore(state: const (id: 0));

      final List<TaskResult?> results = await Future.wait([
        store.queueSuccessTask(const TaskParams(1)),
        store.queueFailTask(const TaskParams(100)).catchError((Object? error) {
          expect(error, isA<ArgumentError>());
          expect(
            store.queueFailTask.state,
            isA<TaskFailed<TaskParams, void, Object?>>(),
          );
        }),
        store.queueSuccessTask(const TaskParams(3)),
      ]);

      expect(results.first?.receivedAmount, equals(1));
      expect(results.last?.receivedAmount, equals(3));
    });

    test(
      'once strategy calls fn exactly once across successful invocations',
      () async {
        final store = TestStore(state: const (id: 0));

        final r1 = await store.onceCountedTask(1);
        final r2 = await store.onceCountedTask(2);
        final r3 = await store.onceCountedTask(3);

        expect(store.onceCallCount, equals(1));
        // All subsequent callers get the first successful result.
        expect(r1, equals(2));
        expect(r2, equals(2));
        expect(r3, equals(2));
      },
    );

    test('once: concurrent callers share the first failing attempt', () async {
      final store = TestStore(state: const (id: 0));

      Future<Object?> attempt(int p) async {
        try {
          await store.onceSharedFailingTask(p);
          return null;
        } on Object catch (e) {
          return e;
        }
      }

      final results = await Future.wait([attempt(1), attempt(2), attempt(3)]);

      expect(store.onceFailingCallCount, equals(1));
      expect(results[0], isA<StateError>());
      expect(results[1], same(results[0]));
      expect(results[2], same(results[0]));
    });

    test(
      'queue: dispose while tasks in flight — pending complete, new calls throw',
      () async {
        final store = TestStore(state: const (id: 0));

        final aFuture = store.queueSequentialTask(1);
        final bFuture = store.queueSequentialTask(2);

        // Let A start running.
        await Future<void>.delayed(const Duration(milliseconds: 5));

        store.queueSequentialTask.dispose();

        // In-flight / already-queued calls complete normally.
        expect(await aFuture, equals(1));
        expect(await bFuture, equals(2));

        // New call() after dispose throws TaskError.
        expect(() => store.queueSequentialTask(3), throwsA(isA<TaskError>()));
      },
    );

    test(
      'sync-throwing fn still settles pending state and releases the queue',
      () async {
        final store = TestStore(state: const (id: 0));

        Object? caught;
        try {
          await store.syncThrowTask(1);
        } on Object catch (e) {
          caught = e;
        }
        expect(caught, isA<StateError>());
        // syncThrowTask declares TError=Object, so StateError matches
        // → terminal state is TaskFailed (not TaskPending).
        expect(store.syncThrowTask.state, isA<TaskFailed<int, int, Object>>());

        // Queue must be usable for subsequent calls too.
        Object? second;
        try {
          await store.syncThrowTask(2);
        } on Object catch (e) {
          second = e;
        }
        expect(second, isA<StateError>());
        expect(store.syncThrowTask.state, isA<TaskFailed<int, int, Object>>());
      },
    );

    test('Store.dispose cascades to owned tasks', () async {
      final store = TestStore(state: const (id: 0));

      await store.onceSuccessTask(const TaskParams(1));
      store.dispose();

      expect(
        () => store.onceSuccessTask(const TaskParams(2)),
        throwsA(isA<TaskError>()),
      );
    });

    test('Store.dispose iterates every owned task; siblings still tear down '
        'when one disposal throws (error isolation contract)', () async {
      // Healthy multi-task store path: verify Store.dispose() reaches
      // every owned task even though its dispose phase now wraps each
      // call in a try/catch. We exercise four distinct strategies (once,
      // queue, debounce, throttle) — after dispose all four should
      // reject further calls with [TaskError], proving the loop
      // didn't bail on the first task.
      final store = TestStore(state: const (id: 0));

      // Touch every `late final` task so it lands in Store._tasks
      // before dispose; otherwise the late-init would resolve them
      // AFTER teardown, against a fresh state (not what we test).
      // Returned tuple is unused — discarding it via `_` keeps
      // `unnecessary_statements` quiet without per-line ignores.
      final _ = (
        store.queueSequentialTask,
        store.onceSuccessTask,
        store.debounceTask,
        store.throttleTask,
      );
      await store.onceSuccessTask(const TaskParams(1));

      expect(() => store.dispose(), returnsNormally);

      expect(() => store.queueSequentialTask(1), throwsA(isA<TaskError>()));
      expect(
        () => store.onceSuccessTask(const TaskParams(2)),
        throwsA(isA<TaskError>()),
      );
      expect(() => store.debounceTask(1), throwsA(isA<TaskError>()));
      expect(() => store.throttleTask(1), throwsA(isA<TaskError>()));
    });

    test(
      'Store.createTask with .latest: all pending callers share the latest result',
      () async {
        final store = TestStore(state: const (id: 0));

        final f1 = store.latestTask(1);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final f2 = store.latestTask(2);

        expect(await f1, equals(200));
        expect(await f2, equals(200));
        expect(store.latestCallCount, equals(2));
      },
    );

    test('Store.createTask with .debounce coalesces a burst', () async {
      final store = TestStore(state: const (id: 0));

      final results = await Future.wait([
        store.debounceTask(1),
        store.debounceTask(2),
        store.debounceTask(3),
      ]);
      expect(results, equals([6, 6, 6]));
      expect(store.debounceCallCount, equals(1));
    });

    test('Store.createTask with .throttle runs one per window', () async {
      final store = TestStore(state: const (id: 0));

      final f1 = store.throttleTask(1);
      final f2 = store.throttleTask(2);
      expect(await f1, equals(1));
      expect(await f2, equals(1));
      expect(store.throttleCallCount, equals(1));
    });

    test(
      'Store.dispose cascades to debounce task and rejects its future',
      () async {
        final store = TestStore(state: const (id: 0));

        final f = store.debounceTask(1);
        store.dispose();

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

  group('Store.subscribeSelect', () {
    test('listener fires only when the selected projection changes', () {
      final store = TestStore(state: const (id: 0));
      addTearDown(store.dispose);
      final seen = <(int, int)>[];

      store.subscribeSelect<int>(
        (s) => s.id,
        (prev, next) => seen.add((prev, next)),
      );

      store.setState(const (id: 0));
      expect(seen, isEmpty);

      store.setState(const (id: 1));
      expect(seen, equals([(0, 1)]));

      store.setState(const (id: 1));
      expect(seen, equals([(0, 1)]));

      store.setState(const (id: 2));
      expect(seen, equals([(0, 1), (1, 2)]));
    });

    test('fireImmediately seeds the listener with (current, current)', () {
      final store = TestStore(state: const (id: 5));
      addTearDown(store.dispose);
      final seen = <(int, int)>[];

      store.subscribeSelect<int>(
        (s) => s.id,
        (prev, next) => seen.add((prev, next)),
        fireImmediately: true,
      );
      expect(seen, equals([(5, 5)]));
    });

    test('returned disposer detaches the listener', () {
      final store = TestStore(state: const (id: 0));
      addTearDown(store.dispose);
      final seen = <int>[];

      final dispose = store.subscribeSelect<int>(
        (s) => s.id,
        (_, next) => seen.add(next),
      );
      store.setState(const (id: 1));
      dispose();
      store.setState(const (id: 2));
      expect(seen, equals([1]));
    });

    test('custom equals filters projection by content (e.g. listEquals)', () {
      // List<int> projection — `==` is identity, so without a custom
      // equals the listener would fire on every state write that
      // produces a fresh list, even with the same contents.
      bool listEquals(List<int> a, List<int> b) {
        if (a.length != b.length) return false;
        for (var i = 0; i < a.length; i++) {
          if (a[i] != b[i]) return false;
        }
        return true;
      }

      final store = _ItemsStore(items: const [1, 2]);
      addTearDown(store.dispose);
      final seen = <List<int>>[];

      store.subscribeSelect<List<int>>(
        (s) => s,
        (_, next) => seen.add(List.of(next)),
        equals: listEquals,
      );

      // Same content, fresh list — must NOT fire.
      store.replaceItems(const [1, 2]);
      expect(seen, isEmpty);

      // Different content — fires once.
      store.replaceItems(const [1, 2, 3]);
      expect(
        seen,
        equals([
          [1, 2, 3],
        ]),
      );
    });
  });

  group('Task.firstWhere / awaitDone / awaitFailed / awaitSettled', () {
    test(
      'firstWhere resolves immediately when state already matches',
      () async {
        final store = TestStore(state: const (id: 0));
        addTearDown(store.dispose);

        await store.onceSuccessTask(const TaskParams(7));
        final settled = await store.onceSuccessTask.firstWhere(
          (s) => s is TaskDone<TaskParams, TaskResult, Object?>,
        );
        expect(settled, isA<TaskDone<TaskParams, TaskResult, Object?>>());
      },
    );

    test('firstWhere awaits a future transition', () async {
      final store = TestStore(state: const (id: 0));
      addTearDown(store.dispose);

      final donePromise = store.onceCountedTask.firstWhere(
        (s) => s is TaskDone<int, int, Object>,
      );

      final result = await store.onceCountedTask(3);
      expect(result, 6);
      expect(await donePromise, isA<TaskDone<int, int, Object>>());
    });

    test('awaitDone yields the result payload', () async {
      final store = TestStore(state: const (id: 0));
      addTearDown(store.dispose);

      final futureResult = store.onceCountedTask.awaitDone();
      await store.onceCountedTask(4);
      expect(await futureResult, 8);
    });

    test('awaitFailed yields the typed error payload', () async {
      final store = TestStore(state: const (id: 0));
      addTearDown(store.dispose);

      final futureError = store.onceSharedFailingTask.awaitFailed();
      try {
        await store.onceSharedFailingTask(1);
      } on Object {
        // expected — task fn throws on every call
      }
      expect(await futureError, isA<StateError>());
    });

    test('awaitSettled yields whichever terminal state lands first', () async {
      final store = TestStore(state: const (id: 0));
      addTearDown(store.dispose);

      final settledOk = store.onceCountedTask.awaitSettled();
      await store.onceCountedTask(2);
      expect(await settledOk, isA<TaskDone<int, int, Object>>());
    });
  });
}
