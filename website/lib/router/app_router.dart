import 'package:go_router/go_router.dart';

import '../pages/docs_page.dart';
import '../pages/examples_page.dart';
import '../pages/landing_page.dart';
import '../pages/not_found_page.dart';
import '../widgets/app_shell.dart';

class AppRouter {
  const AppRouter._();

  static GoRouter create() {
    return GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (_, _) =>
                  const NoTransitionPage(child: LandingPage()),
            ),
            GoRoute(path: '/docs', redirect: (_, _) => '/docs/quickstart'),
            GoRoute(
              path: '/docs/:slug',
              pageBuilder: (_, state) => NoTransitionPage(
                child: DocsPage(slug: state.pathParameters['slug']!),
              ),
            ),
            GoRoute(path: '/examples', redirect: (_, _) => '/examples/counter'),
            GoRoute(
              path: '/examples/:slug',
              pageBuilder: (_, state) => NoTransitionPage(
                child: ExamplesPage(slug: state.pathParameters['slug']!),
              ),
            ),
          ],
        ),
      ],
      errorBuilder: (_, _) => const NotFoundPage(),
    );
  }
}
