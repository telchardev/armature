import 'package:armature/armature.dart';

import './auth_repository.dart';

typedef User = ({String name});
typedef AuthState = ({User? user});

extension AuthStateCopyWith on AuthState {
  AuthState copyWith({User? user, bool clearUser = false}) =>
      (user: clearUser ? null : (user ?? this.user));
}

class AuthStore extends Store<AuthState> {
  final AuthRepository _repo;

  AuthStore(AuthRepository repo) : _repo = repo, super(state: (user: null));

  late final load = createVoidTask(
    fn: () async {
      final name = await _repo.load();
      if (name != null) {
        update((s) => s.copyWith(user: (name: name)));
      }
    },
    strategy: TaskStrategy.once,
  );

  late final login = createTask(
    fn: (String name) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      update((s) => s.copyWith(user: (name: name)));
      await _repo.save(name);
    },
    strategy: TaskStrategy.queue,
  );

  void logout() {
    state = state.copyWith(clearUser: true);
    _repo.clear();
  }
}
