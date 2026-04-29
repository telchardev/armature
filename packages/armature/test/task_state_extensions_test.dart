import 'package:armature/armature.dart';
import 'package:test/test.dart';

void main() {
  group('TaskState.when (exhaustive pattern match)', () {
    test('routes idle branch', () {
      const state = TaskIdle<int, String, Object>();
      final result = state.when(
        idle: () => 'idle',
        pending: (p) => 'pending:$p',
        done: (r) => 'done:$r',
        failed: (e) => 'failed:$e',
      );
      expect(result, 'idle');
    });

    test('routes pending branch with params', () {
      const state = TaskPending<int, String, Object>(42);
      final result = state.when(
        idle: () => 'idle',
        pending: (p) => 'pending:$p',
        done: (r) => 'done:$r',
        failed: (e) => 'failed:$e',
      );
      expect(result, 'pending:42');
    });

    test('routes done branch with result', () {
      const state = TaskDone<int, String, Object>('ok');
      final result = state.when(
        idle: () => 'idle',
        pending: (p) => 'pending:$p',
        done: (r) => 'done:$r',
        failed: (e) => 'failed:$e',
      );
      expect(result, 'done:ok');
    });

    test('routes failed branch with error', () {
      const state = TaskFailed<int, String, String>('boom');
      final result = state.when(
        idle: () => 'idle',
        pending: (p) => 'pending:$p',
        done: (r) => 'done:$r',
        failed: (e) => 'failed:$e',
      );
      expect(result, 'failed:boom');
    });
  });

  group('TaskState.maybeWhen (partial pattern match)', () {
    test('matched branch wins over orElse', () {
      const state = TaskDone<int, String, Object>('hi');
      final result = state.maybeWhen(
        done: (r) => 'matched:$r',
        orElse: (s) => 'fallback',
      );
      expect(result, 'matched:hi');
    });

    test('unmatched branch falls through to orElse', () {
      const state = TaskFailed<int, String, String>('boom');
      final result = state.maybeWhen(
        done: (r) => 'matched',
        orElse: (s) => 'fallback:${s.runtimeType}',
      );
      expect(result, startsWith('fallback:TaskFailed'));
    });

    test('orElse receives the original state for inspection', () {
      const state = TaskPending<int, String, Object>(7);
      final result = state.maybeWhen<TaskState<int, String, Object>>(
        orElse: (s) => s,
      );
      expect(identical(result, state), isTrue);
    });
  });

  group('TaskState boolean / payload getters', () {
    test('isIdle / isPending / isDone / isFailed are mutually exclusive', () {
      const idle = TaskIdle<int, String, Object>();
      const pending = TaskPending<int, String, Object>(1);
      const done = TaskDone<int, String, Object>('ok');
      const failed = TaskFailed<int, String, String>('boom');

      expect(
        [idle.isIdle, idle.isPending, idle.isDone, idle.isFailed],
        [true, false, false, false],
      );
      expect(
        [pending.isIdle, pending.isPending, pending.isDone, pending.isFailed],
        [false, true, false, false],
      );
      expect(
        [done.isIdle, done.isPending, done.isDone, done.isFailed],
        [false, false, true, false],
      );
      expect(
        [failed.isIdle, failed.isPending, failed.isDone, failed.isFailed],
        [false, false, false, true],
      );
    });

    test('paramsOrNull / resultOrNull / errorOrNull return non-null '
        'only on the matching branch', () {
      const idle = TaskIdle<int, String, Object>();
      const pending = TaskPending<int, String, Object>(99);
      const done = TaskDone<int, String, Object>('result');
      const failed = TaskFailed<int, String, String>('boom');

      expect(idle.paramsOrNull, isNull);
      expect(idle.resultOrNull, isNull);
      expect(idle.errorOrNull, isNull);

      expect(pending.paramsOrNull, 99);
      expect(pending.resultOrNull, isNull);
      expect(pending.errorOrNull, isNull);

      expect(done.paramsOrNull, isNull);
      expect(done.resultOrNull, 'result');
      expect(done.errorOrNull, isNull);

      expect(failed.paramsOrNull, isNull);
      expect(failed.resultOrNull, isNull);
      expect(failed.errorOrNull, 'boom');
    });
  });
}
