import 'dart:convert';

import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// MODEL — domain shape, no storage concerns.
// ============================================================

class UserProfile {
  const UserProfile({
    required this.id,
    required this.login,
    required this.name,
  });

  final String id;
  final String login;
  final String name;

  UserProfile copyWith({String? name}) =>
      UserProfile(id: id, login: login, name: name ?? this.name);

  Map<String, Object?> toJson() => {'id': id, 'login': login, 'name': name};

  factory UserProfile.fromJson(Map<String, Object?> json) => UserProfile(
    id: json['id']! as String,
    login: json['login']! as String,
    name: json['name']! as String,
  );
}

// ============================================================
// REPOSITORY — data-layer abstraction + SharedPreferences impl.
// The store talks to the interface only; swapping storage
// (memory, secure storage, remote) stays local to this file.
// ============================================================

abstract interface class ProfileRepository {
  Future<UserProfile?> load();
  Future<void> save(UserProfile profile);
  Future<void> clear();
}

class PrefsProfileRepository implements ProfileRepository {
  static const _key = 'armature_demo.auth.profile';

  // Cached instance — `SharedPreferences.getInstance()` is idempotent
  // but caching saves a round-trip per call.
  SharedPreferences? _cached;
  Future<SharedPreferences> _prefs() async =>
      _cached ??= await SharedPreferences.getInstance();

  @override
  Future<UserProfile?> load() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null) {
      return null;
    }
    try {
      return UserProfile.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      // Malformed — drop it so next save starts clean.
      await prefs.remove(_key);
      return null;
    }
  }

  @override
  Future<void> save(UserProfile profile) async {
    final prefs = await _prefs();
    await prefs.setString(_key, jsonEncode(profile.toJson()));
  }

  @override
  Future<void> clear() async {
    final prefs = await _prefs();
    await prefs.remove(_key);
  }
}

// ============================================================
// STORE — owns session state, delegates persistence to repo.
// ============================================================

typedef SessionState = ({UserProfile? user});

class SessionStore extends Store<SessionState> {
  SessionStore(this._repo) : super(state: (user: null));

  final ProfileRepository _repo;

  /// Runs once on feature start — rehydrates session from prefs.
  late final restore = createVoidTask(
    fn: () async {
      final loaded = await _repo.load();
      state = (user: loaded);
    },
    strategy: TaskStrategy.once,
  );

  /// Creates a profile from the login name (demo stub — a real app
  /// would hit an identity service here).
  late final signIn = createTask(
    fn: (String login) async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final trimmed = login.trim();
      if (trimmed.isEmpty) {
        return;
      }
      final profile = UserProfile(
        id: 'u_${trimmed.hashCode.abs().toRadixString(16)}',
        login: trimmed,
        name: trimmed[0].toUpperCase() + trimmed.substring(1),
      );
      await _repo.save(profile);
      state = (user: profile);
    },
    strategy: TaskStrategy.queue,
  );

  /// Renames the signed-in user and persists.
  late final updateName = createTask(
    fn: (String newName) async {
      final current = state.user;
      final trimmed = newName.trim();
      if (current == null || trimmed.isEmpty || trimmed == current.name) {
        return;
      }
      final updated = current.copyWith(name: trimmed);
      await _repo.save(updated);
      state = (user: updated);
    },
    strategy: TaskStrategy.queue,
  );

  Future<void> signOut() async {
    await _repo.clear();
    state = (user: null);
  }
}

// ============================================================
// FEATURES — Auth owns the session + slot; Profile activates
// only while a user is signed in.
// ============================================================

final profileSlot = createSingleSlot<Null>(name: 'auth.profile');

final authFeature =
    createFeature(
      name: 'Auth',
      stores: (_) => (session: SessionStore(PrefsProfileRepository())),
      ports: (profile: profileSlot),
      exports: (api) => api.own,
    )..onStart((api, cleanup) async {
      await api.own.session.restore();
    });

final profileFeature = createFeature(name: 'Profile', dependsOn: [authFeature])
  ..activation(
    whenStoreState(
      feature: authFeature,
      store: (exports) => exports.session,
      predicate: (state) => state.user != null,
    ),
  )
  ..useSingleSlot(authFeature.ports.profile, (_, api) {
    // Inside a slot, the FeatureContext is the *contributor*
    // (profileFeature), which owns no stores. Reach through the
    // parent-API chain for SessionStore and pass it down explicitly
    // so the card doesn't need a StoreContext.of lookup that would
    // hit profileFeature's empty storeMap.
    final session = api.of(authFeature).session;
    final user = session.state.user;
    if (user == null) {
      return null;
    }
    return _ProfileCard(user: user, session: session);
  });

// ============================================================
// VIEW — 2-column layout (stacks on narrow widths).
// ============================================================

class _AuthView extends StatelessWidget {
  const _AuthView();

  static const double _breakpoint = 560;

  @override
  Widget build(BuildContext context) {
    final session = StoreContext.of<SessionStore>(context);

    final left = StateObserver(
      builder: (_) => session.state.user == null
          ? _LoginForm(
              onSubmit: (login) => session.signIn(login),
              taskState: session.signIn.state,
            )
          : _SignedInBar(user: session.state.user!, onSignOut: session.signOut),
    );

    // The profile slot receives its contributor from `profileFeature`
    // while a user is signed in. When inactive, we fall back to the
    // guest view so the right column is never empty.
    final right = SingleSlotProvider(
      slot: authFeature.ports.profile,
      data: null,
      builder: (child, _) => child ?? const _GuestView(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _breakpoint) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: left),
                const SizedBox(width: 20),
                Expanded(child: right),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [left, const SizedBox(height: 16), right],
        );
      },
    );
  }
}

class _LoginForm extends StatefulWidget {
  const _LoginForm({required this.onSubmit, required this.taskState});

  final void Function(String) onSubmit;
  final TaskState<String, void, dynamic> taskState;

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: 'alice');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final login = _controller.text.trim();
    if (login.isEmpty) {
      return;
    }
    widget.onSubmit(login);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoading = widget.taskState is TaskPending;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Sign in',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            enabled: !isLoading,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Login',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: isLoading ? null : _submit,
            icon: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(isLoading ? 'Signing in…' : 'Sign in'),
          ),
        ],
      ),
    );
  }
}

class _SignedInBar extends StatelessWidget {
  const _SignedInBar({required this.user, required this.onSignOut});

  final UserProfile user;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Signed in',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You are logged in as ${user.login}. The Profile feature is '
            'active, contributing the card on the right.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _GuestView extends StatelessWidget {
  const _GuestView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.person_outline,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Guest',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Sign in to see your profile. The Profile feature is inactive '
            'while nobody is signed in, so this slot has no contributor.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatefulWidget {
  const _ProfileCard({required this.user, required this.session});

  final UserProfile user;
  final SessionStore session;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  bool _editing = false;
  late TextEditingController _nameInput;

  @override
  void initState() {
    super.initState();
    _nameInput = TextEditingController(text: widget.user.name);
  }

  @override
  void didUpdateWidget(covariant _ProfileCard old) {
    super.didUpdateWidget(old);
    // Re-seed the input if an external update landed (e.g. another
    // tab wrote to prefs — unlikely here but free correctness).
    if (old.user.name != widget.user.name && !_editing) {
      _nameInput.text = widget.user.name;
    }
  }

  @override
  void dispose() {
    _nameInput.dispose();
    super.dispose();
  }

  void _startEdit() {
    setState(() {
      _nameInput.text = widget.user.name;
      _editing = true;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
    });
  }

  void _saveEdit() {
    widget.session.updateName(_nameInput.text);
    setState(() {
      _editing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _Avatar(user: widget.user),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '@${widget.user.login}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer
                            .withValues(alpha: 0.8),
                      ),
                    ),
                    Text(
                      widget.user.id,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer
                            .withValues(alpha: 0.7),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_editing) _buildEditingRow(theme) else _buildNameRow(theme),
        ],
      ),
    );
  }

  Widget _buildNameRow(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Display name',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer.withValues(
                    alpha: 0.7,
                  ),
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.user.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Edit name',
          onPressed: _startEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ],
    );
  }

  Widget _buildEditingRow(ThemeData theme) {
    return StateObserver(
      builder: (_) {
        final saving = widget.session.updateName.state is TaskPending;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameInput,
              enabled: !saving,
              autofocus: true,
              onSubmitted: (_) => _saveEdit(),
              decoration: InputDecoration(
                labelText: 'Display name',
                border: const OutlineInputBorder(),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.onSecondaryContainer.withValues(
                  alpha: 0.08,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: saving ? null : _cancelEdit,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: saving ? null : _saveEdit,
                  icon: saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check, size: 16),
                  label: Text(saving ? 'Saving…' : 'Save'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  final UserProfile user;

  static const _palette = [
    Color(0xFF4F46E5),
    Color(0xFF0EA5E9),
    Color(0xFF059669),
    Color(0xFFD97706),
    Color(0xFFDC2626),
    Color(0xFF9333EA),
  ];

  @override
  Widget build(BuildContext context) {
    final seed = user.id.hashCode.abs();
    final bg = _palette[seed % _palette.length];
    final initial = user.name.isNotEmpty
        ? user.name[0].toUpperCase()
        : user.login[0].toUpperCase();
    return CircleAvatar(
      radius: 22,
      backgroundColor: bg,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
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
      constraints: const BoxConstraints(maxWidth: 640),
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
