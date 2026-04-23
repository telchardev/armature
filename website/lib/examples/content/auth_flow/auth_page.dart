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
            'A realistic feature-gated experience. Auth owns a session '
            'store and declares a slot where the profile card renders; '
            'Profile activates only while a user is signed in, via the '
            'whenStoreState activation helper. Sign in and the profile '
            'card appears; sign out and it disappears — no manual slot '
            'wiring on either transition.',
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
            'This is the canonical pattern for auth gates, paywalls, '
            'and role-restricted sections. Features stay loaded in the '
            'graph; only their runtime state changes in response to the '
            'session.',
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
          _Caption('Session store'),
          CodeBlock(code: _storeSource, language: 'dart'),
          SizedBox(height: 20),
          _Caption('Auth + Profile features'),
          CodeBlock(code: _featuresSource, language: 'dart'),
          SizedBox(height: 20),
          _Caption('Host view'),
          CodeBlock(code: _viewSource, language: 'dart'),
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

const _storeSource = '''typedef User = ({String name, String role});
typedef SessionState = ({User? user});

class SessionStore extends Store<SessionState> {
  SessionStore() : super(state: (user: null));

  void signIn({required String name, required String role}) {
    state = (user: (name: name, role: role));
  }

  void signOut() {
    state = (user: null);
  }
}''';

const _featuresSource =
    '''final profileSlot = createSingleSlot<Null>(name: 'auth.profile');

final authFeature = createFeature(
  name: 'Auth',
  stores: (_) => (session: SessionStore()),
  ports: (profile: profileSlot),
  exports: (api) => api.own,
);

final profileFeature = createFeature(
  name: 'Profile',
  dependsOn: [authFeature],
)
  ..activation(whenStoreState(
    feature: authFeature,
    store: (exports) => exports.session,
    predicate: (state) => state.user != null,
  ))
  ..useSingleSlot(profileSlot, (_, api) {
    final user = api.of(authFeature).session.state.user!;
    return ProfileCard(user: user);
  });''';

const _viewSource = '''class AuthView extends StatelessWidget {
  const AuthView({super.key});

  @override
  Widget build(BuildContext context) {
    final session = StoreContext.of<SessionStore>(context);
    return Column(
      children: [
        StateObserver(
          builder: (_) {
            final user = session.state.user;
            return user == null
                ? LoginForm(onSignIn: session.signIn)
                : SignedInBar(user: user, onSignOut: session.signOut);
          },
        ),
        SingleSlotProvider(
          slot: profileSlot,
          data: null,
          builder: (child, _) => child ?? const SizedBox.shrink(),
        ),
      ],
    );
  }
}''';
