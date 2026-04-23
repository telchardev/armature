import 'package:armature/armature.dart';

typedef InspectorState = ({DateTime? lastRefresh, int refreshCount});

extension InspectorStateCopyWith on InspectorState {
  InspectorState copyWith({DateTime? lastRefresh, int? refreshCount}) => (
    lastRefresh: lastRefresh ?? this.lastRefresh,
    refreshCount: refreshCount ?? this.refreshCount,
  );
}

class InspectorStore extends Store<InspectorState> {
  InspectorStore() : super(state: (lastRefresh: null, refreshCount: 0));

  late final refresh = createVoidTask(
    fn: () async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      update(
        (s) => s.copyWith(
          lastRefresh: DateTime.now(),
          refreshCount: s.refreshCount + 1,
        ),
      );
    },
    strategy: TaskStrategy.queue,
  );
}
