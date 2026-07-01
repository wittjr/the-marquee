import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_controller.dart';
import '../profile_page.dart';

/// Shared app-bar actions shown on every main tab: a tappable username that
/// opens the profile page as a route, plus a sign-out button. Placed last in an
/// [AppBar.actions] list so page-specific actions sit to its left.
class AccountBarActions extends StatelessWidget {
  const AccountBarActions({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (auth.username != null)
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            ),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text('@${auth.username}',
                  style: const TextStyle(color: Colors.white60)),
            ),
          ),
        IconButton(
          tooltip: 'Sign out',
          onPressed: auth.signOut,
          icon: const Icon(Icons.logout),
        ),
      ],
    );
  }
}
