import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../state/auth_controller.dart';
import '../state/library_controller.dart';
import '../models/watchlist_show.dart';
import 'widgets/account_bar.dart';
import 'widgets/media_card.dart';
import 'widgets/movie_detail_dialog.dart';
import 'widgets/movie_row_card.dart';
import 'widgets/refresh_bar.dart';
import 'widgets/show_detail_dialog.dart';
import 'widgets/show_episode_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          LibraryController(auth: context.read<AuthController>())..load(),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Up Next',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: const [AccountBarActions()],
        bottom: library.isRefreshing ? const RefreshBar() : null,
      ),
      body: RefreshIndicator(
        onRefresh: library.load,
        child: _body(context, library),
      ),
    );
  }

  Widget _body(BuildContext context, LibraryController library) {
    switch (library.state) {
      case LoadState.idle:
      case LoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case LoadState.error:
        return _ErrorView(
            message: library.error ?? 'Something went wrong',
            onRetry: library.load);
      case LoadState.ready:
        if (library.isEmpty) {
          return const _EmptyView();
        }
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (library.recentShows.isNotEmpty) ...[
              _sectionHeader('Recently Watched / Just Released'),
              _showList(context, library, library.recentShows,
                  canStopWatching: true),
            ],
            if (library.staleShows.isNotEmpty) ...[
              _sectionHeader('Not watched in a while'),
              _showList(context, library, library.staleShows,
                  canStopWatching: true),
            ],
            if (library.movies.isNotEmpty) ...[
              _sectionHeader('Movies'),
              _movieList(context, library, library.movies),
            ],
            if (library.upcomingMovies.isNotEmpty) ...[
              _sectionHeader('Upcoming Movies'),
              _grid(context, library, library.upcomingMovies),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        );
    }
  }

  Widget _showList(
    BuildContext context,
    LibraryController library,
    List<WatchlistShow> shows, {
    bool canStopWatching = false,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final ws = shows[i];
            return ShowEpisodeCard(
              show: ws,
              busy: library.isShowBusy(ws),
              onWatch: ws.nextEpisode != null
                  ? () => _run(
                        context,
                        library.markNextEpisodeWatched(ws),
                        'Marked ${ws.nextEpisode!.code} of “${ws.show.title}” watched',
                      )
                  : null,
              onTap: () => showDialog(
                context: context,
                builder: (_) => ShowDetailDialog(
                  show: ws,
                  loadRemaining: () => library.remainingEpisodes(ws),
                  onWatch: ws.nextEpisode != null
                      ? () => library.markNextEpisodeWatched(ws)
                      : null,
                  onStopWatching:
                      canStopWatching ? () => library.stopWatching(ws) : null,
                  onRemoveFromHistory: () => library.removeFromHistory(ws),
                ),
              ),
            );
          },
          childCount: shows.length,
        ),
      ),
    );
  }

  /// Renders the Movies section as compact full-width rows (matching the show
  /// rows) instead of poster tiles, to save vertical space.
  Widget _movieList(
    BuildContext context,
    LibraryController library,
    List<MediaItem> items,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final item = items[i];
            return MovieRowCard(
              item: item,
              busy: library.isBusy(item),
              onWatched: item.isReleased
                  ? () => _run(
                        context,
                        library.markWatched(item),
                        'Marked “${item.title}” watched',
                      )
                  : null,
              onTap: () => showDialog(
                context: context,
                builder: (_) => MovieDetailDialog(
                  item: item,
                  onToggleWatchlist: () => library.removeFromWatchlist(item),
                  closeOnWatchlist: true,
                  onWatched:
                      item.isReleased ? () => library.markWatched(item) : null,
                ),
              ),
            );
          },
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    LibraryController library,
    List<MediaItem> items,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          childAspectRatio: 0.5,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final item = items[i];
            return MediaCard(
              item: item,
              busy: library.isBusy(item),
              onTap: item.isMovie
                  ? () => showDialog(
                        context: context,
                        builder: (_) => MovieDetailDialog(
                          item: item,
                          onToggleWatchlist: () =>
                              library.removeFromWatchlist(item),
                          closeOnWatchlist: true,
                          onWatched: item.isReleased
                              ? () => library.markWatched(item)
                              : null,
                        ),
                      )
                  : null,
              onToggleWatchlist: () => _run(
                context,
                library.removeFromWatchlist(item),
                'Removed “${item.title}” from watchlist',
              ),
              onWatched: item.isMovie && item.isReleased
                  ? () => _run(
                        context,
                        library.markWatched(item),
                        'Marked “${item.title}” watched',
                      )
                  : null,
            );
          },
          childCount: items.length,
        ),
      ),
    );
  }

  /// Awaits a watchlist/watched mutation and shows the outcome as a snackbar.
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
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Icon(Icons.movie_filter_outlined, size: 64, color: Colors.white24),
        SizedBox(height: 16),
        Center(
          child: Text('Your watchlist is empty',
              style: TextStyle(color: Colors.white60)),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.error_outline, size: 64, color: Colors.white24),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      ],
    );
  }
}
