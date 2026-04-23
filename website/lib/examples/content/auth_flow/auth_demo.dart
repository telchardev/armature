import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

typedef User = ({String name, String role});

typedef SessionState = ({User? user});

/// Source of truth for the logged-in user. Nullable user = guest.
class SessionStore extends Store<SessionState> {
  SessionStore() : super(state: (user: null));

  void signIn({required String name, required String role}) {
    state = (user: (name: name, role: role));
  }

  void signOut() {
    state = (user: null);
  }
}

/// Slot where the profile card renders when the profile feature is active.
final profileSlot = createSingleSlot<Null>(name: 'auth.profile');

/// Auth feature — owns the session store + declares the profile slot.
final authFeature = createFeature(
  name: 'Auth',
  stores: (_) => (session: SessionStore()),
  ports: (profile: profileSlot),
  exports: (api) => api.own,
);

/// Profile feature — activation gated on "signed in as any user".
///
/// `whenStoreState` subscribes to the session store and flips
/// ToggleState on every change. While inactive, the slot handler is
/// skipped and the profile card disappears from the layout without
/// any manual wiring.
final profileFeature = createFeature(name: 'Profile', dependsOn: [authFeature])
  ..activation(
    whenStoreState(
      feature: authFeature,
      store: (exports) => exports.session,
      predicate: (state) => state.user != null,
    ),
  )
  ..useSingleSlot(profileSlot, (_, api) {
    final user = api.of(authFeature).session.state.user;
    if (user == null) {
      // Defensive: activation gate should ensure this never hits.
      return null;
    }
    return _ProfileCard(user: user);
  });

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.onSecondaryContainer,
            foregroundColor: theme.colorScheme.secondaryContainer,
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, ${user.name}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Role: ${user.role} — profileFeature is ACTIVE',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthView extends StatefulWidget {
  const _AuthView();

  @override
  State<_AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<_AuthView> {
  late final TextEditingController _nameController;
  String _role = 'member';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'Alice');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = StoreContext.of<SessionStore>(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StateObserver(
          builder: (_) {
            final user = session.state.user;
            if (user != null) {
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      'Signed in as ${user.name} (${user.role}).',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: session.signOut,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Sign out'),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'member', label: Text('member')),
                    ButtonSegment(value: 'admin', label: Text('admin')),
                  ],
                  selected: {_role},
                  onSelectionChanged: (s) => setState(() => _role = s.first),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    final name = _nameController.text.trim();
                    if (name.isEmpty) return;
                    session.signIn(name: name, role: _role);
                  },
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in'),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 4),
        SingleSlotProvider(
          slot: profileSlot,
          data: null,
          builder: (child, _) => child ?? const SizedBox.shrink(),
        ),
      ],
    );
  }
}

final _authRoot = createFeatureRoot(
  feature: authFeature,
  widget: const _AuthView(),
);

class AuthFlowDemoWidget extends StatelessWidget {
  const AuthFlowDemoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      constraints: const BoxConstraints(maxWidth: 480),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ArmatureApp(
        features: [authFeature, profileFeature],
        child: _authRoot(data: null),
      ),
    );
  }
}
