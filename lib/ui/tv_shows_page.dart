import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/watchlist_show.dart';
import '../state/auth_controller.dart';
import '../state/shows_controller.dart';
import 'main_shell.dart';
import 'widgets/account_bar.dart';
import 'widgets/media_card.dart';
import 'widgets/refresh_bar.dart';
import 'widgets/show_detail_dialog.dart';
import 'widgets/show_episode_card.dart';

/// The TV Shows tab: search Trakt for shows to add to the watchlist, and resume
/// shows parked on the "Watch Later" list.
class TvShowsPage extends StatelessWidget {
  const TvShowsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Loading is driven by tab selection (see [_TvShowsViewState]) rather than
    // eagerly at startup, so it doesn't pile onto the startup request burst and
    // it refreshes whenever the user returns to the tab.
    return ChangeNotifierProvider(
      create: (_) => ShowsController(auth: context.read<AuthController>()),
      child: const _TvShowsView(),
    );
  }
}

class _TvShowsView extends StatefulWidget {
  const _TvShowsView();

  @override
  State<_TvShowsView> createState() => _TvShowsViewState();
}

class _TvShowsViewState extends State<_TvShowsView> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  ValueNotifier<int>? _tab;

  @override
  void initState() {
    super.initState();
    _tab = context.read<ShellTabs>().selected;
    _tab!.addListener(_onTabChanged);
    // Load now if this tab is the one already showing.
    if (_tab!.value == ShellTab.tvShows) _reload();
  }

  void _onTabChanged() {
    if (_tab?.value == ShellTab.tvShows) _reload();
  }

  /// Refreshes the Watch Later list (the controller ignores re-entrant calls),
  /// so shows moved to/from the list on other tabs are reflected on return.
  /// Deferred so we don't notify listeners during build.
  void _reload() => Future.microtask(context.read<ShowsController>().load);

  @override
  void dispose() {
    _tab?.removeListener(_onTabChanged);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      context.read<ShowsController>().search(value);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _searchController.clear();
    context.read<ShowsController>().clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    final shows = context.watch<ShowsController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('TV Shows',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: const [AccountBarActions()],
        bottom: shows.isRefreshing ? const RefreshBar() : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Search for a show to add…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: shows.query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _clear,
                      )
                    : null,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          Expanded(
            child: shows.query.isNotEmpty
                ? _SearchResults(shows: shows)
                : _WatchLaterList(shows: shows),
          ),
        ],
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  final ShowsController shows;
  const _SearchResults({required this.shows});

  @override
  Widget build(BuildContext context) {
    if (shows.searching && shows.results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (shows.results.isEmpty) {
      return const _Hint(
        icon: Icons.search_off,
        message: 'No shows found',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.5,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: shows.results.length,
      itemBuilder: (context, i) {
        final item = shows.results[i];
        return MediaCard(
          item: item,
          busy: shows.isBusy(item),
          onToggleWatchlist: () => _run(
            context,
            shows.toggleWatchlist(item),
            item.onWatchlist
                ? 'Removed “${item.title}” from watchlist'
                : 'Added “${item.title}” to watchlist',
          ),
        );
      },
    );
  }
}

class _WatchLaterList extends StatelessWidget {
  final ShowsController shows;
  const _WatchLaterList({required this.shows});

  @override
  Widget build(BuildContext context) {
    switch (shows.state) {
      case ShowsState.loading:
        return const Center(child: CircularProgressIndicator());
      case ShowsState.error:
        return _Hint(
          icon: Icons.error_outline,
          message: shows.error ?? 'Something went wrong',
        );
      case ShowsState.ready:
        if (shows.watchLaterShows.isEmpty) {
          return RefreshIndicator(
            onRefresh: shows.load,
            child: ListView(
              children: const [
                SizedBox(height: 120),
                _Hint(
                  icon: Icons.watch_later_outlined,
                  message: 'Your Watch Later list is empty',
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: shows.load,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: shows.watchLaterShows.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(0, 8, 0, 8),
                  child: Text('Watch Later',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                );
              }
              final ws = shows.watchLaterShows[i - 1];
              return ShowEpisodeCard(
                show: ws,
                busy: shows.isShowBusy(ws),
                onWatch: ws.nextEpisode != null
                    ? () => _watch(context, ws)
                    : null,
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => ShowDetailDialog(
                    show: ws,
                    onWatch: ws.nextEpisode != null
                        ? () => shows.markNextEpisodeWatched(ws)
                        : null,
                    onRemoveFromHistory: () => shows.removeFromHistory(ws),
                  ),
                ),
              );
            },
          ),
        );
    }
  }

  void _watch(BuildContext context, WatchlistShow ws) => _run(
        context,
        shows.markNextEpisodeWatched(ws),
        'Marked ${ws.nextEpisode!.code} of “${ws.show.title}” watched · moved to Watchlist',
      );
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String message;
  const _Hint({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.white24),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60)),
          ),
        ],
      ),
    );
  }
}

/// Awaits a mutation and reports the outcome as a snackbar.
Future<void> _run(
  BuildContext context,
  Future<void> action,
  String successMessage,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action;
    messenger.showSnackBar(SnackBar(content: Text(successMessage)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Action failed: $e')));
  }
}
