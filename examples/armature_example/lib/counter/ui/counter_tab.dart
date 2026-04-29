import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import '../../layout/layout_mode.dart';
import '../counter_store.dart';

class CounterTab extends StatelessWidget {
  final CounterStore store;
  final LayoutMode mode;

  const CounterTab({super.key, required this.store, required this.mode});

  @override
  Widget build(BuildContext context) {
    final isPhone = mode == LayoutMode.phone;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            StateObserver(
              builder: (_) => Text(
                '${store.state.value}',
                style: Theme.of(context).textTheme.displayLarge,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'LayoutMode.${mode.name} — buttons in ${isPhone ? 'Column' : 'Row'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            _Buttons(store: store, horizontal: !isPhone),
          ],
        ),
      ),
    );
  }
}

class _Buttons extends StatelessWidget {
  final CounterStore store;
  final bool horizontal;

  const _Buttons({required this.store, required this.horizontal});

  @override
  Widget build(BuildContext context) {
    final children = [
      FilledButton.icon(
        onPressed: () => store.increment(),
        icon: const Icon(Icons.add),
        label: const Text('Increment (.queue)'),
      ),
      OutlinedButton.icon(
        onPressed: () => store.decrementTo(0),
        icon: const Icon(Icons.south),
        label: const Text('Decrement to 0'),
      ),
      TextButton.icon(
        onPressed: () => store.reset(),
        icon: const Icon(Icons.restart_alt),
        label: const Text('Reset'),
      ),
      TextButton.icon(
        onPressed: () {
          store.debouncedBump();
        },
        icon: const Icon(Icons.timer),
        label: const Text('Debounced bump (300ms)'),
      ),
      _FlakyFetchButton(store: store),
    ];

    if (horizontal) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: children,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          children[i],
        ],
      ],
    );
  }
}

/// Demo button for `Task.autoReset` + typed-error snackbar pattern.
///
/// On tap, fires `store.flakyFetch` (50% fail rate). The state machine
/// flickers `TaskIdle → TaskPending → TaskDone | TaskFailed` and the
/// `autoReset: Duration(seconds: 3)` returns it to `TaskIdle`
/// automatically, re-enabling the button. A subscribed listener shows
/// a SnackBar on every settle so the user gets ephemeral feedback in
/// addition to the in-button state.
class _FlakyFetchButton extends StatefulWidget {
  final CounterStore store;

  const _FlakyFetchButton({required this.store});

  @override
  State<_FlakyFetchButton> createState() => _FlakyFetchButtonState();
}

class _FlakyFetchButtonState extends State<_FlakyFetchButton> {
  void Function()? _disposeListener;

  @override
  void initState() {
    super.initState();
    _disposeListener = widget.store.flakyFetch.subscribe((_, next) {
      if (!mounted) return;
      switch (next) {
        case TaskDone(:final result):
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(result),
              backgroundColor: Colors.green.shade600,
              duration: const Duration(seconds: 2),
            ),
          );
        case TaskFailed(:final error):
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('Fetch failed: $error'),
              backgroundColor: Colors.red.shade600,
              duration: const Duration(seconds: 2),
            ),
          );
        case TaskIdle() || TaskPending():
        // No snackbar for idle / pending transitions.
      }
    });
  }

  @override
  void dispose() {
    _disposeListener?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TaskBuilder(
      task: widget.store.flakyFetch,
      idle: (_) => OutlinedButton.icon(
        onPressed: () => widget.store.flakyFetch(),
        icon: const Icon(Icons.cloud_download_outlined),
        label: const Text('Fetch greeting (50% fail, autoReset 3s)'),
      ),
      pending: (_, _) => OutlinedButton.icon(
        onPressed: null,
        icon: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: const Text('Fetching…'),
      ),
      done: (_, result) => OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_circle, color: Colors.green),
        label: Text('OK: $result'),
      ),
      failed: (_, FetchError error) => OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.error_outline, color: Colors.red),
        label: Text('Failed: $error'),
      ),
    );
  }
}
