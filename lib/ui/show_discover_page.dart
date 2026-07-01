import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../state/show_discover_controller.dart';
import 'widgets/media_card.dart';

/// The TV segment of the Discover tab: search Trakt for shows to add to the
/// watchlist, and — with no active search — browse Trending and Coming Soon
/// (most-anticipated) rows.
///
/// Body-only: a [ShowDiscoverController] must be provided above this widget, and
/// the hosting shell owns the app bar.
class ShowDiscoverBody extends StatefulWidget {
  const ShowDiscoverBody({super.key});

  @override
  State<ShowDiscoverBody> createState() => _ShowDiscoverBodyState();
}

class _ShowDiscoverBodyState extends State<ShowDiscoverBody> {
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
      context.read<ShowDiscoverController>().search(value);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _searchController.clear();
    context.read<ShowDiscoverController>().clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    final shows = context.watch<ShowDiscoverController>();

    return Column(
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
              : _DiscoverRows(shows: shows),
        ),
      ],
    );
  }
}

class _SearchResults extends StatelessWidget {
  final ShowDiscoverController shows;
  const _SearchResults({required this.shows});

  @override
  Widget build(BuildContext context) {
    if (shows.searching && shows.results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (shows.results.isEmpty) {
      return const _Hint(icon: Icons.search_off, message: 'No shows found');
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
      itemBuilder: (context, i) => _card(context, shows, shows.results[i]),
    );
  }
}

class _DiscoverRows extends StatelessWidget {
  final ShowDiscoverController shows;
  const _DiscoverRows({required this.shows});

  @override
  Widget build(BuildContext context) {
    switch (shows.state) {
      case ShowDiscoverState.loading:
        return const Center(child: CircularProgressIndicator());
      case ShowDiscoverState.error:
        return _Hint(
          icon: Icons.error_outline,
          message: shows.error ?? 'Something went wrong',
        );
      case ShowDiscoverState.ready:
        return RefreshIndicator(
          onRefresh: shows.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (shows.trending.isNotEmpty) ...[
                _header('Trending'),
                _grid(context, shows, shows.trending),
              ],
              if (shows.anticipated.isNotEmpty) ...[
                _header('Coming Soon'),
                _grid(context, shows, shows.anticipated),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        );
    }
  }

  Widget _header(String title) {
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
    ShowDiscoverController shows,
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
          (context, i) => _card(context, shows, items[i]),
          childCount: items.length,
        ),
      ),
    );
  }
}

Widget _card(
  BuildContext context,
  ShowDiscoverController shows,
  MediaItem item,
) {
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
