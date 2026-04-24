import 'package:armature/armature.dart';

import './night_mode_repository.dart';

typedef NightModeState = ({bool enabled});

class NightModeStore extends Store<NightModeState> {
  final NightModeRepository _repo;

  NightModeStore(NightModeRepository repo)
    : _repo = repo,
      super(state: (enabled: false));

  late final load = createVoidTask(
    fn: () async {
      final value = await _repo.load();
      update((s) => (enabled: value));
    },
    strategy: TaskStrategy.once,
  );

  void toggle() {
    update((s) => (enabled: !s.enabled));
    _repo.save(state.enabled);
  }
}
