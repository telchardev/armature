import 'package:armature/armature.dart';

typedef InspectorState = ({DateTime? lastRefresh, int refreshCount});

class InspectorStore extends Store<InspectorState> {
  InspectorStore() : super(state: (lastRefresh: null, refreshCount: 0));

  late final refresh = createVoidTask(
    fn: () async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      update(
        (s) => (lastRefresh: DateTime.now(), refreshCount: s.refreshCount + 1),
      );
    },
  );

  late final clear = createVoidTask(
    fn: () async {
      state = (lastRefresh: null, refreshCount: 0);
    },
  );
}
