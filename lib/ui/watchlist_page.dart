import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import '../state/show_watchlist_controller.dart';
import '../state/watchlist_movies_controller.dart';
import 'main_shell.dart';
import 'tv_shows_page.dart';
import 'watchlist_movies_page.dart';
import 'widgets/account_bar.dart';
import 'widgets/library_segment.dart';
import 'widgets/scroll_to_top_title.dart';

/// The Watchlist tab: what the user is tracking. A Movies / TV segmented control
/// swaps between the full movie watchlist (Coming Soon + All Movies) and the TV
/// Watch Later list. Both controllers are provided here; loads are driven by tab
/// (re)selection so the lists stay in step with edits made on other tabs.
class WatchlistPage extends StatelessWidget {
  const WatchlistPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => WatchlistMoviesController(auth: auth)),
        ChangeNotifierProvider(
            create: (_) => ShowWatchlistController(auth: auth)),
      ],
      child: const _WatchlistView(),
    );
  }
}

class _WatchlistView extends StatefulWidget {
  const _WatchlistView();

  @override
  State<_WatchlistView> createState() => _WatchlistViewState();
}

class _WatchlistViewState extends State<_WatchlistView> {
  var _segment = LibrarySegment.movies;
  ValueNotifier<int>? _tab;
  // One scroll controller per segment; the app-bar title scrolls whichever
  // segment is active back to the top.
  final _moviesScroll = ScrollController();
  final _showsScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _tab = context.read<ShellTabs>().selected;
    _tab!.addListener(_onTabChanged);
    if (_tab!.value == ShellTab.watchlist) _reload();
  }

  void _onTabChanged() {
    if (_tab?.value == ShellTab.watchlist) _reload();
  }

  /// Refreshes both watchlists (the controllers ignore re-entrant calls).
  /// Deferred so we don't notify listeners during build.
  void _reload() {
    final movies = context.read<WatchlistMoviesController>();
    final shows = context.read<ShowWatchlistController>();
    Future.microtask(() {
      movies.load();
      shows.load();
    });
  }

  @override
  void dispose() {
    _tab?.removeListener(_onTabChanged);
    _moviesScroll.dispose();
    _showsScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ScrollToTopTitle(
          'Watchlist',
          controller: _segment == LibrarySegment.movies
              ? _moviesScroll
              : _showsScroll,
        ),
        actions: const [AccountBarActions()],
        bottom: LibrarySegmentBar(
          selected: _segment,
          onChanged: (s) => setState(() => _segment = s),
        ),
      ),
      body: IndexedStack(
        index: _segment.index,
        children: [
          MovieWatchlistBody(scrollController: _moviesScroll),
          ShowWatchlistBody(scrollController: _showsScroll),
        ],
      ),
    );
  }
}
