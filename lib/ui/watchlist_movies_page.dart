import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../state/watchlist_movies_controller.dart';
import 'widgets/media_card.dart';
import 'widgets/movie_detail_dialog.dart';

/// The Movies segment of the Watchlist tab: the full list of movies on the
/// user's Trakt watchlist, split into a "Coming Soon" section (unreleased,
/// soonest first) and "All Movies".
///
/// Body-only: a [WatchlistMoviesController] must be provided above this widget,
/// and the hosting shell owns the app bar.
class MovieWatchlistBody extends StatelessWidget {
  /// Drives the movie list so the hosting shell's app-bar title can scroll it
  /// back to the top when tapped.
  final ScrollController? scrollController;

  const MovieWatchlistBody({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WatchlistMoviesController>();
    return RefreshIndicator(
      onRefresh: controller.load,
      child: _body(context, controller),
    );
  }

  Widget _body(BuildContext context, WatchlistMoviesController controller) {
    switch (controller.state) {
      case WatchlistLoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case WatchlistLoadState.error:
        return _ErrorView(
          message: controller.error ?? 'Something went wrong',
          onRetry: controller.load,
        );
      case WatchlistLoadState.ready:
        if (controller.isEmpty) return const _EmptyView();
        // The controller sorts by release date ascending; "Coming Soon" is the
        // unreleased head of that list, everything else falls under "All Movies".
        final comingSoon =
            controller.movies.where((m) => !m.isReleased).toList();
        final rest = controller.movies.where((m) => m.isReleased).toList();
        return CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (comingSoon.isNotEmpty) ...[
              _sectionHeader('Coming Soon'),
              _grid(context, controller, comingSoon),
            ],
            if (rest.isNotEmpty) ...[
              _sectionHeader(comingSoon.isEmpty ? 'Watchlist' : 'All Movies'),
              _grid(context, controller, rest),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        );
    }
  }

  Widget _sectionHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    WatchlistMoviesController controller,
    List<MediaItem> movies,
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
          (context, i) => _card(context, controller, movies[i]),
          childCount: movies.length,
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    WatchlistMoviesController controller,
    MediaItem item,
  ) {
    return MediaCard(
      item: item,
      busy: controller.isBusy(item),
      onTap: () => showDialog(
        context: context,
        builder: (_) => MovieDetailDialog(
          item: item,
          onToggleWatchlist: () => controller.removeFromWatchlist(item),
          closeOnWatchlist: true,
          onWatched:
              item.isReleased ? () => controller.markWatched(item) : null,
        ),
      ),
      onToggleWatchlist: () => _run(
        context,
        controller.removeFromWatchlist(item),
        'Removed “${item.title}” from watchlist',
      ),
      onWatched: item.isReleased
          ? () => _run(
                context,
                controller.markWatched(item),
                'Marked “${item.title}” watched',
              )
          : null,
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
        Icon(Icons.bookmarks_outlined, size: 64, color: Colors.white24),
        SizedBox(height: 16),
        Center(
          child: Text('No movies on your watchlist',
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
