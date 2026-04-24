import 'package:armature/src/store/state.dart';
import 'package:test/test.dart';

void main() {
  group('State', () {
    test('initial state is stored and retrievable', () {
      final s = State<int>(state: 42);
      expect(s.state, equals(42));
    });

    test('setter updates state and notifies listeners', () {
      final s = State<int>(state: 0);
      int? seenPrev, seenCurr;
      s.subscribe((prev, curr) {
        seenPrev = prev;
        seenCurr = curr;
      }, fireImmediately: false);

      s.state = 5;

      expect(s.state, equals(5));
      expect(seenPrev, equals(0));
      expect(seenCurr, equals(5));
    });

    test('setter is a no-op when the value is equal', () {
      final s = State<int>(state: 0);
      var calls = 0;
      s.subscribe((_, _) => calls++, fireImmediately: false);

      s.state = 0;

      expect(calls, equals(0));
    });

    test('update() applies callback to current state', () {
      final s = State<int>(state: 10);
      s.update((v) => v + 5);
      expect(s.state, equals(15));
    });

    test('update() notifies listeners with prev/next', () {
      final s = State<int>(state: 1);
      int? seenPrev, seenCurr;
      s.subscribe((prev, curr) {
        seenPrev = prev;
        seenCurr = curr;
      }, fireImmediately: false);

      s.update((v) => v * 3);

      expect(seenPrev, equals(1));
      expect(seenCurr, equals(3));
    });

    test('fireImmediately fires with (state, state) on subscribe', () {
      final s = State<int>(state: 7);
      int? seenPrev, seenCurr;
      s.subscribe((prev, curr) {
        seenPrev = prev;
        seenCurr = curr;
      }, fireImmediately: true);

      expect(seenPrev, equals(7));
      expect(seenCurr, equals(7));
    });

    test('subscribe disposer removes the listener', () {
      final s = State<int>(state: 0);
      var calls = 0;
      final dispose = s.subscribe((_, _) => calls++, fireImmediately: false);

      s.state = 1;
      expect(calls, equals(1));

      dispose();
      s.state = 2;
      expect(calls, equals(1));
    });

    test('setter and update() are no-ops after dispose', () {
      final s = State<int>(state: 0);
      var calls = 0;
      s.subscribe((_, _) => calls++, fireImmediately: false);

      s.dispose();
      s.state = 99;
      s.update((v) => v + 1);

      expect(s.state, equals(0));
      expect(calls, equals(0));
    });

    test('subscribe after dispose returns a harmless disposer', () {
      final s = State<int>(state: 0);
      s.dispose();

      var calls = 0;
      final dispose = s.subscribe((_, _) => calls++, fireImmediately: false);

      expect(() => dispose(), returnsNormally);
      expect(calls, equals(0));
    });

    test('listener may remove itself during notify (one-shot pattern)', () {
      final s = State<int>(state: 0);
      var calls = 0;
      late StateListenerDisposer disposer;
      disposer = s.subscribe((_, _) {
        calls++;
        disposer();
      }, fireImmediately: false);

      // Defensive snapshot: listener may unsubscribe itself during
      // notify without tripping ConcurrentModificationError.
      s.state = 1;
      expect(calls, equals(1));

      // After self-removal subsequent writes don't fire the listener.
      s.state = 2;
      expect(calls, equals(1));
    });

    test('deferring unsubscribe to a microtask is also safe', () async {
      final s = State<int>(state: 0);
      var calls = 0;
      late StateListenerDisposer disposer;
      disposer = s.subscribe((_, _) {
        calls++;
        // Still-supported pattern: schedule mutation outside notify.
        Future.microtask(disposer);
      }, fireImmediately: false);

      s.state = 1;
      await Future<void>.delayed(Duration.zero);
      s.state = 2;

      expect(calls, equals(1));
    });

    test('multiple subscribers with fireImmediately all fire', () {
      final s = State<int>(state: 0);
      var calls = 0;
      s.subscribe((_, _) => calls++, fireImmediately: true);
      s.subscribe((_, _) => calls++, fireImmediately: true);

      expect(calls, equals(2));
    });

    test('listener exception propagates to the setter caller', () {
      final s = State<int>(state: 0);
      s.subscribe(
        (_, _) => throw Exception('listener error'),
        fireImmediately: false,
      );

      expect(() => s.state = 1, throwsException);
    });

    test('disposer is idempotent — double dispose is safe', () {
      final s = State<int>(state: 0);
      var calls = 0;
      final dispose = s.subscribe((_, _) => calls++, fireImmediately: false);

      dispose();
      dispose();
      s.state = 1;

      expect(calls, equals(0));
    });
  });
}
