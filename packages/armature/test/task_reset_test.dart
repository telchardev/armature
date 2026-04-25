import 'package:armature/advanced.dart' show VoidTask;
import 'package:armature/armature.dart';
import 'package:armature/src/store/task.dart' show create, createVoid;
import 'package:test/test.dart';

Task<TParams, TResult, Object> makeTask<TParams, TResult>({
  required Future<TResult> Function(TParams) fn,
  required TaskStrategy strategy,
  Duration? autoReset,
}) {
  return create<TParams, TResult, Object>(
    fn: fn,
    strategy: strategy,
    autoReset: autoReset,
  );
}

VoidTask<TResult, Object> makeVoidTask<TResult>({
  required Future<TResult> Function() fn,
  required TaskStrategy strategy,
  Duration? autoReset,
}) {
  return createVoid<TResult, Object>(
    fn: fn,
    strategy: strategy,
    autoReset: autoReset,
  );
}

void main() {
  group('Task.reset() — manual', () {
    test('reset from TaskIdle is a no-op (no listener fire)', () {
      final task = makeTask<int, int>(
        fn: (p) async => p,
        strategy: TaskStrategy.queue,
      );

      var fired = 0;
      task.subscribe((_, _) => fired++);

      task.reset();

      expect(task.state, isA<TaskIdle<int, int, Object>>());
      expect(fired, equals(0));
    });

    test('reset from TaskDone transitions to TaskIdle', () async {
      final task = makeTask<int, int>(
        fn: (p) async => p * 2,
        strategy: TaskStrategy.queue,
      );

      await task(7);
      expect(task.state, equals(const TaskDone<int, int, Object>(14)));

      final transitions = <TaskState<int, int, Object>>[];
      task.subscribe((_, next) => transitions.add(next));

      task.reset();

      expect(task.state, isA<TaskIdle<int, int, Object>>());
      expect(transitions, hasLength(1));
      expect(transitions.first, isA<TaskIdle<int, int, Object>>());
    });

    test('reset from TaskFailed transitions to TaskIdle', () async {
      final task = makeTask<int, int>(
        fn: (p) async => throw 'boom',
        strategy: TaskStrategy.queue,
      );

      await expectLater(task(1), throwsA('boom'));
      expect(task.state, isA<TaskFailed<int, int, Object>>());

      task.reset();

      expect(task.state, isA<TaskIdle<int, int, Object>>());
    });

    test(
      'reset during .queue TaskPending — fn runs but state writes drop',
      () async {
        final task = makeTask<int, int>(
          fn: (p) async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return p * 10;
          },
          strategy: TaskStrategy.queue,
        );

        final fut = task(5);
        // Let the call write TaskPending.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(task.state, isA<TaskPending<int, int, Object>>());

        task.reset();
        expect(task.state, isA<TaskIdle<int, int, Object>>());

        // Underlying fn still resolves with the value (no Dart cancellation),
        // but the TaskDone state write is dropped.
        final result = await fut;
        expect(result, equals(50));
        expect(task.state, isA<TaskIdle<int, int, Object>>());
      },
    );

    test(
      'reset during .latest pending — pending callers reject with TaskError',
      () async {
        final task = makeTask<int, int>(
          fn: (p) async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return p;
          },
          strategy: TaskStrategy.latest,
        );

        final fut = task(1);
        await Future<void>.delayed(const Duration(milliseconds: 5));

        task.reset();

        await expectLater(fut, throwsA(isA<TaskError>()));
        expect(task.state, isA<TaskIdle<int, int, Object>>());
      },
    );

    test(
      'reset during .debounce quiet window — coalesced caller rejects',
      () async {
        final task = makeTask<int, int>(
          fn: (p) async => p,
          strategy: const TaskStrategy.debounce(Duration(milliseconds: 50)),
        );

        final fut = task(1);
        // Within the quiet window — timer hasn't fired.
        await Future<void>.delayed(const Duration(milliseconds: 5));

        task.reset();

        await expectLater(fut, throwsA(isA<TaskError>()));

        // Wait past the original debounce window to confirm the timer
        // was actually cancelled (no late firing).
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(task.state, isA<TaskIdle<int, int, Object>>());
      },
    );

    test(
      'reset during .throttle(trailing) window — coalesced caller rejects',
      () async {
        final task = makeTask<int, int>(
          fn: (p) async => p,
          strategy: const TaskStrategy.throttle(
            Duration(milliseconds: 50),
            edge: ThrottleEdge.trailing,
          ),
        );

        final fut = task(1);
        await Future<void>.delayed(const Duration(milliseconds: 5));

        task.reset();

        await expectLater(fut, throwsA(isA<TaskError>()));

        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(task.state, isA<TaskIdle<int, int, Object>>());
      },
    );

    test('reset clears .once cache: subsequent call re-executes fn', () async {
      var calls = 0;
      final task = makeTask<int, int>(
        fn: (p) async {
          calls++;
          return p;
        },
        strategy: TaskStrategy.once,
      );

      expect(await task(1), equals(1));
      expect(calls, equals(1));

      // Cached — does not re-execute.
      expect(await task(2), equals(1));
      expect(calls, equals(1));

      task.reset();
      expect(task.state, isA<TaskIdle<int, int, Object>>());

      expect(await task(3), equals(3));
      expect(calls, equals(2));
    });

    test('reset after dispose() is a silent no-op', () async {
      final task = makeTask<int, int>(
        fn: (p) async => p,
        strategy: TaskStrategy.queue,
      );

      await task(1);
      task.dispose();

      expect(() => task.reset(), returnsNormally);
    });

    test(
      'reset then immediate call() — new call writes go through (post-reset gen)',
      () async {
        final task = makeTask<int, int>(
          fn: (p) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return p * 100;
          },
          strategy: TaskStrategy.queue,
        );

        final inFlight = task(1);
        await Future<void>.delayed(const Duration(milliseconds: 3));
        task.reset();

        final after = task(2);

        await inFlight; // Old run completes; its writes are dropped.
        final r2 = await after;
        expect(r2, equals(200));
        expect(task.state, equals(const TaskDone<int, int, Object>(200)));
      },
    );

    test(
      'reset during in-flight .latest then call() resumes cleanly',
      () async {
        final task = makeTask<int, int>(
          fn: (p) async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return p;
          },
          strategy: TaskStrategy.latest,
        );

        final f1 = task(1);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        task.reset();
        await expectLater(f1, throwsA(isA<TaskError>()));

        final f2 = task(2);
        expect(await f2, equals(2));
        expect(task.state, equals(const TaskDone<int, int, Object>(2)));
      },
    );

    test('VoidTask.reset() works through subclass', () async {
      final task = makeVoidTask<int>(
        fn: () async => 42,
        strategy: TaskStrategy.queue,
      );

      await task();
      expect(task.state, equals(const TaskDone<void, int, Object>(42)));

      task.reset();
      expect(task.state, isA<TaskIdle<void, int, Object>>());
    });
  });

  group('Task autoReset', () {
    test('after TaskDone transitions to TaskIdle after duration', () async {
      final task = makeTask<int, int>(
        fn: (p) async => p,
        strategy: TaskStrategy.queue,
        autoReset: const Duration(milliseconds: 30),
      );

      await task(1);
      expect(task.state, equals(const TaskDone<int, int, Object>(1)));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(task.state, isA<TaskIdle<int, int, Object>>());
    });

    test('after TaskFailed transitions to TaskIdle after duration', () async {
      final task = makeTask<int, int>(
        fn: (p) async => throw 'boom',
        strategy: TaskStrategy.queue,
        autoReset: const Duration(milliseconds: 30),
      );

      await expectLater(task(1), throwsA('boom'));
      expect(task.state, isA<TaskFailed<int, int, Object>>());

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(task.state, isA<TaskIdle<int, int, Object>>());
    });

    test('timer cancels when a new call() enters TaskPending', () async {
      final task = makeTask<int, int>(
        fn: (p) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return p;
        },
        strategy: TaskStrategy.queue,
        autoReset: const Duration(milliseconds: 50),
      );

      await task(1);
      expect(task.state, equals(const TaskDone<int, int, Object>(1)));

      // Mid-window: new call should cancel the auto-reset timer.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final fut = task(2);

      // Past the *original* auto-reset window — if the timer hadn't been
      // cancelled, state would have flickered through TaskIdle. Instead
      // it should be either Pending (still in flight) or Done.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await fut;
      expect(task.state, equals(const TaskDone<int, int, Object>(2)));
    });

    test('timer cancels on manual reset() (no double-fire)', () async {
      var resetCount = 0;
      late final Task<int, int, Object> task;
      task = makeTask<int, int>(
        fn: (p) async => p,
        strategy: TaskStrategy.queue,
        autoReset: const Duration(milliseconds: 30),
      );
      task.subscribe((_, next) {
        if (next is TaskIdle<int, int, Object>) resetCount++;
      });

      await task(1);
      task.reset();
      expect(resetCount, equals(1));

      await Future<void>.delayed(const Duration(milliseconds: 60));
      // No double-fire from the auto-reset timer.
      expect(resetCount, equals(1));
    });

    test('timer cancels on dispose() (no fire after disposal)', () async {
      final task = makeTask<int, int>(
        fn: (p) async => p,
        strategy: TaskStrategy.queue,
        autoReset: const Duration(milliseconds: 30),
      );

      await task(1);
      task.dispose();

      // If the timer survived dispose, this delay would fire reset on a
      // disposed task — disposed reset is a no-op, so the only observable
      // effect would be a thrown error, which we'd see as a test failure.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // No assertion needed: the test just needs to not throw.
    });

    test(
      'autoReset with .once strategy: after timeout re-call re-executes fn',
      () async {
        var calls = 0;
        final task = makeTask<int, int>(
          fn: (p) async {
            calls++;
            return p;
          },
          strategy: TaskStrategy.once,
          autoReset: const Duration(milliseconds: 30),
        );

        await task(1);
        expect(calls, equals(1));
        expect(task.state, equals(const TaskDone<int, int, Object>(1)));

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(task.state, isA<TaskIdle<int, int, Object>>());

        // Cache cleared by autoReset; new call re-executes fn.
        await task(2);
        expect(calls, equals(2));
      },
    );

    test('autoReset null (default) — task settles indefinitely', () async {
      final task = makeTask<int, int>(
        fn: (p) async => p,
        strategy: TaskStrategy.queue,
      );

      await task(1);
      expect(task.state, equals(const TaskDone<int, int, Object>(1)));

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(task.state, equals(const TaskDone<int, int, Object>(1)));
    });
  });
}
