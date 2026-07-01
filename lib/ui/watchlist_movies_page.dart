import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../state/auth_controller.dart';
import '../state/watchlist_movies_controller.dart';
import 'main_shell.dart';
import 'widgets/account_bar.dart';
import 'widgets/media_card.dart';
import 'widgets/movie_detail_dialog.dart';
import 'widgets/refresh_bar.dart';

/// The Watchlist tab: the full list of movies on the user's Trakt watchlist,
/// sorted by release date (oldest first).
class WatchlistMoviesPage extends StatelessWidget {
  const WatchlistMoviesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          WatchlistMoviesController(auth: context.read<AuthController>()),
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
  ValueNotifier<int>? _tab;

  @override
  void initState() {
    super.initState();
    // Loading is driven by tab selection (like the TV Shows tab) so it stays in
    // step with watchlist changes made on the Coming Soon / Up Next tabs, and
    // doesn't pile onto the startup request burst.
    _tab = context.read<ShellTabs>().selected;
    _tab!.addListener(_onTabChanged);
    if (_tab!.value == ShellTab.watchlist) _reload();
  }

  void _onTabChanged() {
    if (_tab?.value == ShellTab.watchlist) _reload();
  }

  /// Deferred so we don't notify listeners during build. The controller ignores
  /// re-entrant calls.
  void _reload() =>
      Future.microtask(context.read<WatchlistMoviesController>().load);

  @override
  void dispose() {
    _tab?.removeListener(_onTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WatchlistMoviesController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Watchlist',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: const [AccountBarActions()],
        bottom: controller.isRefreshing ? const RefreshBar() : null,
      ),
      body: RefreshIndicator(
        onRefresh: controller.load,
        child: _body(context, controller),
      ),
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
        return GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            childAspectRatio: 0.5,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: controller.movies.length,
          itemBuilder: (context, i) =>
              _card(context, controller, controller.movies[i]),
        );
    }
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
