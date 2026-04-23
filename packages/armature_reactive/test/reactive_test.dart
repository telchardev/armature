import 'package:armature_reactive/armature_reactive.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'reactive_listeners.mocks.dart';

void main() {
  group('Reactive tests', () {
    test('onInvalidate() not called if atom not changed', () {
      final listeners = MockListeners();

      final atom = Atom();

      final reaction = Reaction(onInvalidate: listeners.onInvalidate);

      reaction.track(() {
        atom.reportObserved();
      });

      verifyNever(listeners.onInvalidate()).called(0);
    });

    test('onInvalidate() called if atom changed', () {
      final listeners = MockListeners();

      final atom = Atom();

      final atom2 = Atom();

      final atom3 = Atom();

      final reaction = Reaction(onInvalidate: listeners.onInvalidate);

      reaction.track(() {
        atom.reportObserved();
        atom2.reportObserved();
        atom3.reportObserved();
      });

      atom.reportChanged();
      atom2.reportChanged();
      atom3.reportChanged();

      final atom4 = Atom();

      reaction.track(() {
        atom4.reportObserved();
      });

      const calledCount = 3;

      verify(listeners.onInvalidate()).called(calledCount);
    });

    test('onInvalidate() not called after clear', () {
      final listeners = MockListeners();

      final atom = Atom();

      final reaction = Reaction(onInvalidate: listeners.onInvalidate);

      reaction.track(() {
        atom.reportObserved();
      });

      atom.reportChanged();

      verify(listeners.onInvalidate()).called(1);

      reaction.clear();

      atom.reportChanged();

      verifyNever(listeners.onInvalidate()).called(0);
    });
  });

  group('Atom edge cases', () {
    test('reportChanged with no observers should not throw', () {
      final atom = Atom();
      expect(() => atom.reportChanged(), returnsNormally);
    });

    test('reportObserved outside reaction should not throw', () {
      final atom = Atom();
      expect(() => atom.reportObserved(), returnsNormally);
    });
  });

  group('Reaction edge cases', () {
    test('multiple reactions on same atom all fire', () {
      final atom = Atom();
      var count1 = 0;
      var count2 = 0;

      final reaction1 = Reaction(onInvalidate: () => count1++);
      final reaction2 = Reaction(onInvalidate: () => count2++);

      reaction1.track(() => atom.reportObserved());
      reaction2.track(() => atom.reportObserved());

      atom.reportChanged();

      expect(count1, equals(1));
      expect(count2, equals(1));
    });

    test('clear is idempotent', () {
      final atom = Atom();
      var count = 0;

      final reaction = Reaction(onInvalidate: () => count++);
      reaction.track(() => atom.reportObserved());

      reaction.clear();
      reaction.clear();

      atom.reportChanged();
      expect(count, equals(0));
    });

    test('reaction with no tracked atoms does not fire', () {
      var count = 0;

      final reaction = Reaction(onInvalidate: () => count++);
      reaction.track(() {});

      expect(count, equals(0));
    });

    test('reaction tracks only atoms from latest track call', () {
      final atom1 = Atom();
      final atom2 = Atom();
      var count = 0;

      final reaction = Reaction(onInvalidate: () => count++);

      reaction.track(() => atom1.reportObserved());
      reaction.track(() => atom2.reportObserved());

      atom1.reportChanged();
      expect(count, equals(0));

      atom2.reportChanged();
      expect(count, equals(1));
    });

    test('track returns the value from the tracked function', () {
      final atom = Atom();
      final reaction = Reaction(onInvalidate: () {});

      final result = reaction.track(() {
        atom.reportObserved();
        return 42;
      });

      expect(result, equals(42));
    });
  });

  group('Context batching', () {
    test('batch groups multiple changes into one reaction', () {
      final atom1 = Atom();
      final atom2 = Atom();
      var count = 0;

      final reaction = Reaction(onInvalidate: () => count++);
      reaction.track(() {
        atom1.reportObserved();
        atom2.reportObserved();
      });

      globalContext.startBatch();
      atom1.reportChanged();
      atom2.reportChanged();
      expect(count, equals(0));

      globalContext.endBatch();
      expect(count, equals(1));
    });
  });

  group('Error resilience', () {
    test('exception in onInvalidate does not prevent other reactions', () {
      final atom = Atom();
      var secondFired = false;

      Reaction(
        onInvalidate: () {
          throw Exception('reaction 1 failed');
        },
      ).track(() => atom.reportObserved());

      Reaction(
        onInvalidate: () {
          secondFired = true;
        },
      ).track(() => atom.reportObserved());

      atom.reportChanged();

      expect(secondFired, isTrue);
    });

    test('batch completes even if reaction throws', () {
      final atom1 = Atom();
      final atom2 = Atom();
      var count = 0;

      Reaction(
        onInvalidate: () {
          throw Exception('boom');
        },
      ).track(() => atom1.reportObserved());

      Reaction(
        onInvalidate: () {
          count++;
        },
      ).track(() => atom2.reportObserved());

      globalContext.startBatch();
      atom1.reportChanged();
      atom2.reportChanged();
      globalContext.endBatch();

      expect(count, equals(1));
    });
  });

  group('Tracking state recovery', () {
    test(
      'throw inside track() leaves tracking state clean for the next run',
      () {
        final zombieAtom = Atom();
        final ghostAtom = Atom();
        final reaction = Reaction(onInvalidate: () {});

        // First track() aborts with an exception after observing
        // `zombieAtom`. Without try/finally in Context._trackReaction,
        // `_state.trackingReaction` would stay set to `reaction` and
        // subsequent reportObserved calls would pollute its _newAtoms.
        expect(
          () => reaction.track(() {
            zombieAtom.reportObserved();
            throw StateError('track body blew up');
          }),
          throwsA(isA<StateError>()),
        );

        // After the throw, observing atoms OUTSIDE any track scope
        // must be a no-op. If tracking state leaked, ghostAtom would
        // attach to `reaction` even though no one asked for it.
        ghostAtom.reportObserved();
        ghostAtom.reportChanged();

        // Sanity check: reaction really is detached — it can be used
        // again and tracks only what the new run observes.
        var fired = 0;
        final reaction2 = Reaction(onInvalidate: () => fired++);
        reaction2.track(() => ghostAtom.reportObserved());
        ghostAtom.reportChanged();
        expect(fired, equals(1));
      },
    );

    test(
      'non-converging reactions throw ReactiveCycleError with reaction name',
      () {
        final a = Atom();
        final b = Atom();
        late Reaction rA;
        late Reaction rB;

        // Two reactions that ping-pong mutate each other's dependency.
        rA = Reaction(name: 'rA', onInvalidate: () => b.reportChanged())
          ..track(() => a.reportObserved());
        rB = Reaction(name: 'rB', onInvalidate: () => a.reportChanged())
          ..track(() => b.reportObserved());

        expect(
          () => a.reportChanged(),
          throwsA(
            isA<ReactiveCycleError>()
                .having((e) => e.maxIterations, 'maxIterations', equals(100))
                .having(
                  (e) => e.reactionName,
                  'reactionName',
                  anyOf(contains('rA'), contains('rB')),
                ),
          ),
        );

        // Tear down so the leftover reactions don't pollute sibling
        // tests in the shared globalContext.
        rA.clear();
        rB.clear();
      },
    );

    test(
      'ReactiveCycleError is catchable via the sealed ReactiveError base',
      () {
        final a = Atom();
        late Reaction rA;
        late Reaction rB;

        rA = Reaction(onInvalidate: () => a.reportChanged())
          ..track(() => a.reportObserved());
        rB = Reaction(onInvalidate: () => a.reportChanged())
          ..track(() => a.reportObserved());

        try {
          a.reportChanged();
          fail('expected ReactiveCycleError');
        } on ReactiveError catch (e) {
          expect(e, isA<ReactiveCycleError>());
        }

        rA.clear();
        rB.clear();
      },
    );

    test('nested track() restores the outer tracking scope on return', () {
      final outerAtom = Atom();
      final innerAtom = Atom();
      var outerFired = 0;
      var innerFired = 0;

      final outer = Reaction(onInvalidate: () => outerFired++);
      final inner = Reaction(onInvalidate: () => innerFired++);

      outer.track(() {
        outerAtom.reportObserved();
        inner.track(() => innerAtom.reportObserved());
        // After the nested track returns, the ambient is outer
        // again — observing `outerAtom` a second time hits the
        // same reaction, not `inner`.
        outerAtom.reportObserved();
      });

      // Mutating outerAtom fires only the outer reaction.
      outerAtom.reportChanged();
      expect(outerFired, equals(1));
      expect(innerFired, equals(0));

      // Mutating innerAtom fires only the inner reaction.
      innerAtom.reportChanged();
      expect(outerFired, equals(1));
      expect(innerFired, equals(1));

      outer.clear();
      inner.clear();
    });
  });
}
