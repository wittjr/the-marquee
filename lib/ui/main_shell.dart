import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'discover_page.dart';
import 'home_page.dart';
import 'profile_page.dart';
import 'watchlist_page.dart';
import 'widgets/rate_limit_indicator.dart';

/// Root shell shown once signed in: a bottom navigation bar switching between
/// the Up Next dashboard, Discover (movies + TV), Watchlist (movies + TV) and
/// Profile. Discover and Watchlist each carry a Movies / TV segmented control.
/// The username on the Up Next app bar also opens Profile as a shortcut. Pages
/// are kept alive across tab switches so scroll position and loaded data are
/// preserved.
///
/// The selected index is exposed to descendants via a [ValueNotifier] so pages
/// can refresh themselves when (re)selected — e.g. the Watchlist tab reloads its
/// movie and TV lists, which may have changed on another tab.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final ValueNotifier<int> _index = ValueNotifier(0);
  late final ShellTabs _tabs = ShellTabs(_index);

  static const _pages = [
    HomePage(),
    DiscoverPage(),
    WatchlistPage(),
    ProfilePage(),
  ];

  @override
  void dispose() {
    _index.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Provider<ShellTabs>.value(
      value: _tabs,
      child: ValueListenableBuilder<int>(
        valueListenable: _index,
        builder: (context, index, _) => Scaffold(
          body: IndexedStack(index: index, children: _pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => _index.value = i,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.upcoming_outlined),
                selectedIcon: Icon(Icons.upcoming),
                label: 'Up Next',
              ),
              const NavigationDestination(
                icon: Icon(Icons.search_outlined),
                selectedIcon: Icon(Icons.search),
                label: 'Discover',
              ),
              const NavigationDestination(
                icon: Icon(Icons.bookmarks_outlined),
                selectedIcon: Icon(Icons.bookmarks),
                label: 'Watchlist',
              ),
              NavigationDestination(
                // The Trakt rate-limit badges (remaining calls + reset
                // countdown) ride on the Profile icon.
                icon: const RateLimitBadges(
                    child: Icon(Icons.person_outline)),
                selectedIcon:
                    const RateLimitBadges(child: Icon(Icons.person)),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tab index of each [MainShell] page, for pages that refresh on selection.
class ShellTab {
  static const upNext = 0;
  static const discover = 1;
  static const watchlist = 2;
  static const profile = 3;
}

/// Holds the shell's selected-tab notifier so descendants can react to tab
/// changes. Wrapped in a plain object because `Provider` rejects providing a
/// [Listenable] (like [ValueNotifier]) directly; pages add their own listener.
class ShellTabs {
  final ValueNotifier<int> selected;
  const ShellTabs(this.selected);
}
