import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../state/browse_controller.dart';
import 'widgets/media_card.dart';
import 'widgets/movie_detail_dialog.dart';
import 'widgets/movie_filter_sheet.dart';

/// The Movies segment of the Discover tab: browse upcoming and recent movie
/// releases from TMDB (starting four weeks before today and extending into the
/// future a month at a time), plus a search bar to find any movie to add to the
/// watchlist.
///
/// Body-only: a [BrowseController] must be provided above this widget, and the
/// hosting shell owns the app bar (title, filter action, account bar).
class MovieDiscoverBody extends StatefulWidget {
  const MovieDiscoverBody({super.key});

  @override
  State<MovieDiscoverBody> createState() => _MovieDiscoverBodyState();
}

class _MovieDiscoverBodyState extends State<MovieDiscoverBody> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      context.read<BrowseController>().search(value);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _searchController.clear();
    context.read<BrowseController>().clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    final browse = context.watch<BrowseController>();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: _onQueryChanged,
            decoration: InputDecoration(
              hintText: 'Search for a movie to add…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: browse.query.isNotEmpty
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
          child: browse.query.isNotEmpty
              ? _searchResults(context, browse)
              : _discoverBody(context, browse),
        ),
      ],
    );
  }

  Widget _discoverBody(BuildContext context, BrowseController browse) {
    return switch (browse.state) {
      BrowseState.loading => const Center(child: CircularProgressIndicator()),
      BrowseState.error => _ErrorView(
          message: browse.error ?? 'Something went wrong',
          onRetry: browse.refresh,
        ),
      BrowseState.ready => RefreshIndicator(
          onRefresh: browse.refresh,
          child: _grid(context, browse),
        ),
    };
  }

  Widget _searchResults(BuildContext context, BrowseController browse) {
    if (browse.searching && browse.results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (browse.results.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Icon(Icons.search_off, size: 56, color: Colors.white24),
          SizedBox(height: 12),
          Center(
            child: Text('No movies found',
                style: TextStyle(color: Colors.white60)),
          ),
        ],
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
      itemCount: browse.results.length,
      itemBuilder: (context, i) => _card(context, browse, browse.results[i]),
    );
  }

  Widget _grid(BuildContext context, BrowseController browse) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (!browse.loadingMore &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 600) {
          browse.loadMore();
        }
        return false;
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.5,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _card(context, browse, browse.items[i]),
                childCount: browse.items.length,
              ),
            ),
          ),
          SliverToBoxAdapter(child: _footer(context, browse)),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, BrowseController browse, MediaItem item) {
    return MediaCard(
      item: item,
      busy: browse.isBusy(item),
      onTap: () => showDialog(
        context: context,
        builder: (_) => MovieDetailDialog(
          item: item,
          onToggleWatchlist: () => browse.toggleWatchlist(item),
          onWatched: item.isReleased ? () => browse.markWatched(item) : null,
          onIgnore: () => browse.ignore(item),
        ),
      ),
      onToggleWatchlist: () => _run(
        context,
        browse.toggleWatchlist(item),
        item.onWatchlist
            ? 'Removed “${item.title}” from watchlist'
            : 'Added “${item.title}” to watchlist',
      ),
      onIgnore: () => browse.ignore(item),
    );
  }

  Widget _footer(BuildContext context, BrowseController browse) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Center(
        child: browse.loadingMore
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(),
              )
            : OutlinedButton.icon(
                onPressed: browse.loadMore,
                icon: const Icon(Icons.expand_more),
                label: const Text('Load next month'),
              ),
      ),
    );
  }
}

/// Opens the movie filter sheet and applies the result. Exposed for the hosting
/// shell's app-bar filter action.
Future<void> openMovieFilters(
    BuildContext context, BrowseController browse) async {
  final result = await showMovieFilterSheet(context, browse.filters);
  if (result != null) {
    await browse.applyFilters(result);
  }
}

/// Awaits a watchlist mutation and reports the outcome as a snackbar. The
/// success message is captured before the await since the item flips state.
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
