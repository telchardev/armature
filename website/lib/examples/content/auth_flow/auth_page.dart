import 'package:flutter/material.dart';

import '../../../docs/doc_typography.dart';
import '../../../widgets/code_block.dart';
import 'auth_demo.dart';

class AuthFlowPage extends StatelessWidget {
  const AuthFlowPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DocTitle('Auth flow'),
          const DocParagraph(
            'A realistic feature-gated experience with a proper data '
            'layer. Auth owns a session store backed by a repository; '
            'Profile activates only while a user is signed in, via the '
            'whenStoreState activation helper. Sign in and the profile '
            'card appears on the right; sign out and it disappears — '
            'no manual slot wiring.',
          ),
          const DocParagraph(
            'Persistence lives behind a repository interface so the '
            'store never touches SharedPreferences directly. You can '
            'edit your display name and it survives a page reload — '
            'the SharedPrefs impl writes to localStorage on web.',
          ),
          const SizedBox(height: 8),
          const _Tabs(),
          const SizedBox(height: 24),
          const SizedBox(
            height: 620,
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [_PreviewTab(), _CodeTab()],
            ),
          ),
          const SizedBox(height: 24),
          const DocParagraph(
            'The Repository interface keeps the store testable — swap '
            'PrefsProfileRepository for a fake in unit tests, or point '
            'at a secure-storage impl in production. The store has no '
            'idea where the bytes actually live.',
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerHeight: 0,
        tabs: const [
          Tab(text: 'Preview'),
          Tab(text: 'Code'),
        ],
      ),
    );
  }
}

class _PreviewTab extends StatefulWidget {
  const _PreviewTab();

  @override
  State<_PreviewTab> createState() => _PreviewTabState();
}

class _PreviewTabState extends State<_PreviewTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: AuthFlowDemoWidget(),
      ),
    );
  }
}

class _CodeTab extends StatelessWidget {
  const _CodeTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _Caption('auth_demo.dart'),
          CodeBlock(code: _authDemoSource, language: 'dart'),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

const _authDemoSource = r'''import 'dart:convert';

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

  SharedPreferences? _cached;
  Future<SharedPreferences> _prefs() async =>
      _cached ??= await SharedPreferences.getInstance();

  @override
  Future<UserProfile?> load() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return UserProfile.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
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
      if (trimmed.isEmpty) return;
      final profile = UserProfile(
        id: 'u_${trimmed.hashCode.abs().toRadixString(16)}',
        login: trimmed,
        name: trimmed[0].toUpperCase() + trimmed.substring(1),
      );
      await _repo.save(profile);
      state = (user: profile);
    },
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

final authFeature = createFeature(
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
    // Inside a slot, FeatureContext is the *contributor* (profileFeature),
    // which owns no stores. Pass the session store as a parameter so
    // the card doesn't need a StoreContext.of lookup.
    final session = api.of(authFeature).session;
    final user = session.state.user;
    if (user == null) return null;
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
  final _controller = TextEditingController(text: 'alice');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final login = _controller.text.trim();
    if (login.isEmpty) return;
    widget.onSubmit(login);
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = widget.taskState is TaskPending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          enabled: !isLoading,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(labelText: 'Login'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: isLoading ? null : _submit,
          child: Text(isLoading ? 'Signing in…' : 'Sign in'),
        ),
      ],
    );
  }
}

class _SignedInBar extends StatelessWidget {
  const _SignedInBar({required this.user, required this.onSignOut});

  final UserProfile user;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Signed in as ${user.login}.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}

class _GuestView extends StatelessWidget {
  const _GuestView();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text('Sign in to see your profile.'),
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
  late final _nameInput = TextEditingController(text: widget.user.name);

  @override
  void didUpdateWidget(covariant _ProfileCard old) {
    super.didUpdateWidget(old);
    if (old.user.name != widget.user.name && !_editing) {
      _nameInput.text = widget.user.name;
    }
  }

  @override
  void dispose() {
    _nameInput.dispose();
    super.dispose();
  }

  void _save() {
    widget.session.updateName(_nameInput.text);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('@${widget.user.login}'),
          Text(widget.user.id),
          const SizedBox(height: 14),
          if (_editing)
            Row(
              children: [
                Expanded(child: TextField(controller: _nameInput)),
                IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: _save,
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(child: Text(widget.user.name)),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => setState(() => _editing = true),
                ),
              ],
            ),
        ],
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
    return ArmatureApp(
      features: [authFeature, profileFeature],
      child: _authRoot(data: null),
    );
  }
}
''';
