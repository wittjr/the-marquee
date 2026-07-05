import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/watchlist_show.dart';
import '../state/show_watchlist_controller.dart';
import 'widgets/show_detail_dialog.dart';
import 'widgets/show_episode_card.dart';

/// The TV segment of the Watchlist tab: the full show watchlist, split into
/// Coming Soon (not premiered yet), Continue Watching (started), and Not
/// Started (aired but unwatched).
///
/// Body-only: a [ShowWatchlistController] must be provided above this widget,
/// and the hosting shell owns the app bar.
class ShowWatchlistBody extends StatelessWidget {
  /// Drives the show list so the hosting shell's app-bar title can scroll it
  /// back to the top when tapped.
  final ScrollController? scrollController;

  const ShowWatchlistBody({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final shows = context.watch<ShowWatchlistController>();

    switch (shows.state) {
      case ShowWatchlistState.loading:
        return const Center(child: CircularProgressIndicator());
      case ShowWatchlistState.error:
        return _Hint(
          icon: Icons.error_outline,
          message: shows.error ?? 'Something went wrong',
        );
      case ShowWatchlistState.ready:
        if (shows.isEmpty) {
          return RefreshIndicator(
            onRefresh: shows.load,
            child: ListView(
              children: const [
                SizedBox(height: 120),
                _Hint(
                  icon: Icons.tv_off_outlined,
                  message: 'Your TV watchlist is empty',
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: shows.load,
          child: CustomScrollView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              ..._section(context, shows, 'Coming Soon', shows.comingSoon),
              ..._section(
                  context, shows, 'Continue Watching', shows.continueWatching),
              ..._section(context, shows, 'Not Started', shows.notStarted),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        );
    }
  }

  /// A titled section of show cards, or nothing when [items] is empty.
  List<Widget> _section(
    BuildContext context,
    ShowWatchlistController shows,
    String title,
    List<WatchlistShow> items,
  ) {
    if (items.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(title,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _card(context, shows, items[i]),
            childCount: items.length,
          ),
        ),
      ),
    ];
  }

  Widget _card(
    BuildContext context,
    ShowWatchlistController shows,
    WatchlistShow ws,
  ) {
    return ShowEpisodeCard(
      show: ws,
      busy: shows.isShowBusy(ws),
      onWatch: ws.nextEpisode != null
          ? () => _run(
                context,
                shows.markNextEpisodeWatched(ws),
                'Marked ${ws.nextEpisode!.code} of “${ws.show.title}” watched',
              )
          : null,
      onTap: () => showDialog(
        context: context,
        builder: (_) => ShowDetailDialog(
          show: ws,
          loadRemaining: () => shows.remainingEpisodes(ws),
          onWatch: ws.nextEpisode != null
              ? () => shows.markNextEpisodeWatched(ws)
              : null,
          onRemoveFromHistory: () => shows.removeFromHistory(ws),
        ),
      ),
    );
  }
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
