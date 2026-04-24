import 'package:armature/src/emitter.dart';
import 'package:test/test.dart';

/// Helper: emitter that silently swallows listener errors.
Emitter<TEvent> _emitter<TEvent>() =>
    Emitter<TEvent>(onListenerError: (_, _, _) {});

void main() {
  group('Emitter', () {
    test('emit fires the listener', () {
      final emitter = _emitter<String>();
      var calls = 0;
      emitter.add('event', () => calls++);

      emitter.emit('event');

      expect(calls, equals(1));
    });

    test('emit fires multiple listeners for the same event', () {
      final emitter = _emitter<String>();
      var a = 0, b = 0;
      emitter.add('event', () => a++);
      emitter.add('event', () => b++);

      emitter.emit('event');

      expect(a, equals(1));
      expect(b, equals(1));
    });

    test('emit only fires listeners of matching event', () {
      final emitter = _emitter<String>();
      var a = 0, b = 0;
      emitter.add('a', () => a++);
      emitter.add('b', () => b++);

      emitter.emit('a');

      expect(a, equals(1));
      expect(b, equals(0));
    });

    test('emit with no listeners is a no-op', () {
      final emitter = _emitter<String>();
      expect(() => emitter.emit('nothing'), returnsNormally);
    });

    test('remove stops the listener from firing', () {
      final emitter = _emitter<String>();
      var calls = 0;
      void listener() => calls++;
      emitter.add('event', listener);

      emitter.emit('event');
      emitter.remove('event', listener);
      emitter.emit('event');

      expect(calls, equals(1));
    });

    test('remove of unknown event is a no-op', () {
      final emitter = _emitter<String>();
      expect(() => emitter.remove('unknown', () {}), returnsNormally);
    });

    test('listener may remove itself during emit (one-shot pattern)', () {
      final emitter = _emitter<String>();
      var calls = 0;
      late VoidEventListener self;
      self = () {
        calls++;
        emitter.remove('event', self);
      };
      emitter.add('event', self);

      // First emit: listener fires, removes itself.
      emitter.emit('event');
      expect(calls, equals(1));

      // Second emit: listener is gone, nothing fires.
      emitter.emit('event');
      expect(calls, equals(1));
    });

    test(
      'listener may add a new listener during emit — only existing ones fire this round',
      () {
        final emitter = _emitter<String>();
        var lateCalls = 0;
        emitter.add('event', () {
          emitter.add('event', () => lateCalls++);
        });

        // Defensive snapshot: the newly added listener is captured
        // by the next emit only, not this one.
        emitter.emit('event');
        expect(lateCalls, equals(0));

        emitter.emit('event');
        // Now both listeners fire; each of them adds yet another, but
        // the snapshot excludes the newly added. The late one fires
        // once per subsequent emit.
        expect(lateCalls, greaterThanOrEqualTo(1));
      },
    );

    test(
      'listener exception is routed to onListenerError, siblings still run',
      () {
        final errors = <Object>[];
        final emitter = Emitter<String>(
          onListenerError: (_, error, _) => errors.add(error),
        );
        var laterCalled = false;
        emitter.add('event', () => throw StateError('boom'));
        emitter.add('event', () => laterCalled = true);

        // emit itself does not throw — each listener's error is isolated.
        expect(() => emitter.emit('event'), returnsNormally);

        expect(errors, hasLength(1));
        expect(errors.single, isA<StateError>());
        expect(
          laterCalled,
          isTrue,
          reason: 'Sibling listeners must run after an earlier throw.',
        );
      },
    );

    test('dispose clears all listeners', () {
      final emitter = _emitter<String>();
      var calls = 0;
      emitter.add('event', () => calls++);

      emitter.dispose();
      emitter.emit('event');

      expect(calls, equals(0));
    });
  });
}
