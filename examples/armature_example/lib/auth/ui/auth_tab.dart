import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import '../auth_store.dart';

class AuthTab extends StatefulWidget {
  final AuthStore store;

  const AuthTab({super.key, required this.store});

  @override
  State<AuthTab> createState() => _AuthTabState();
}

class _AuthTabState extends State<AuthTab> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: StateObserver(
            builder: (_) {
              final user = widget.store.state.user;
              if (user != null) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.account_circle,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Logged in as ${user.name}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.name == 'admin'
                          ? 'Admin tab is visible while you are logged in as "admin".'
                          : 'Log in as "admin" to reveal the Admin tab reactively.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: widget.store.logout,
                      child: const Text('Log out'),
                    ),
                  ],
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Log in', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    onSubmitted: (v) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'User name',
                      helperText: 'Try "admin" to unlock Admin tab',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.login),
                    label: const Text('Log in'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    widget.store.login(name);
    _controller.clear();
  }
}
