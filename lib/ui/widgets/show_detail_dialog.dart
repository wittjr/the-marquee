import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/watchlist_show.dart';

/// A dismissible dialog showing detail for a watchlist TV show and its next
/// episode, with Watch / Stop Watching actions supplied by the calling page.
/// Mirrors [MovieDetailDialog] but is fed entirely from already-loaded data, so
/// it needs no network fetch.
class ShowDetailDialog extends StatefulWidget {
  final WatchlistShow show;

  /// Mark the next episode watched. Closes the dialog on success.
  final Future<void> Function()? onWatch;

  /// Park the show on the Watch Later list. Closes the dialog on success.
  final Future<void> Function()? onStopWatching;

  /// Clear the show's watch history and remove it from the watchlist / Watch
  /// Later list. Closes the dialog on success.
  final Future<void> Function()? onRemoveFromHistory;

  /// Lazily loads the already-aired episodes of every in-progress season (next
  /// first), each flagged watched or not. When null (or it returns empty), the
  /// dialog falls back to the single known next episode.
  final Future<List<NextEpisode>> Function()? loadRemaining;

  /// Marks a specific episode from the loaded list watched. Required to show a
  /// per-episode Watch button; without it, watched episodes still show their
  /// checkmark but unwatched ones show no inline action.
  final Future<void> Function(NextEpisode ep)? onWatchEpisode;

  const ShowDetailDialog({
    super.key,
    required this.show,
    this.onWatch,
    this.onStopWatching,
    this.onRemoveFromHistory,
    this.loadRemaining,
    this.onWatchEpisode,
  });

  @override
  State<ShowDetailDialog> createState() => _ShowDetailDialogState();
}

class _ShowDetailDialogState extends State<ShowDetailDialog> {
  bool _busy = false;

  /// Aired episodes of in-progress seasons (watched and unwatched); null
  /// until loaded.
  List<NextEpisode>? _remaining;
  bool _loadingRemaining = false;

  /// The episode currently being marked watched via its row button, if any —
  /// used to show a per-row spinner without disabling the rest of the dialog.
  NextEpisode? _busyEpisode;

  @override
  void initState() {
    super.initState();
    _loadRemaining();
  }

  Future<void> _loadRemaining() async {
    final loader = widget.loadRemaining;
    if (loader == null) return;
    // Nothing to fetch for a caught-up show.
    if (widget.show.remainingReleased == 0 && widget.show.nextEpisode == null) {
      return;
    }
    setState(() => _loadingRemaining = true);
    List<NextEpisode> eps;
    try {
      eps = await loader();
    } catch (_) {
      eps = const [];
    }
    if (!mounted) return;
    setState(() {
      _remaining = eps;
      _loadingRemaining = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Header(show: widget.show),
            Flexible(child: _body()),
            const Divider(height: 1),
            _actions(),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final show = widget.show.show;
    final ep = widget.show.nextEpisode;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(show.title,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _MetaRow(show: widget.show),
          if (show.genres.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final g in show.genres)
                  Chip(
                    label: Text(g, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
          ..._remainingSection(ep),
          if (show.overview != null && show.overview!.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('About the show',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(show.overview!, style: const TextStyle(height: 1.4)),
          ],
        ],
      ),
    );
  }

  /// The "Remaining episodes" section: the aired episodes still left to watch.
  /// Shows a loading row while fetching, the list once loaded, and falls back to
  /// the single known [next] episode when no list is available.
  List<Widget> _remainingSection(NextEpisode? next) {
    final list = _remaining;

    // Loaded a real list — show it (next episode first).
    if (list != null && list.isNotEmpty) {
      final left = list.where((e) => !e.watched).length;
      return [
        const SizedBox(height: 16),
        _sectionTitle('Episodes', count: list.length, subtitle: '$left left'),
        const SizedBox(height: 8),
        for (final ep in list) _episodeRow(ep),
      ];
    }

    // Still fetching — header + spinner (only when we expect something).
    if (_loadingRemaining) {
      return [
        const SizedBox(height: 16),
        _sectionTitle('Remaining episodes'),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ];
    }

    // No list available (no loader, or it came back empty) — fall back to the
    // single next episode we already know about.
    if (next != null) {
      return [
        const SizedBox(height: 16),
        _sectionTitle('Next episode'),
        const SizedBox(height: 8),
        _episodeRow(next),
      ];
    }

    return const [];
  }

  Widget _sectionTitle(String title, {int? count, String? subtitle}) {
    final label = count != null ? '$title ($count)' : title;
    return Row(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        if (subtitle != null) ...[
          const SizedBox(width: 6),
          Text(subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _episodeRow(NextEpisode ep) {
    final dimmed = ep.watched ? 0.55 : 1.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(opacity: dimmed, child: _thumb(ep)),
          const SizedBox(width: 12),
          Expanded(
            child: Opacity(
              opacity: dimmed,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ep.title != null ? '${ep.code} · ${ep.title}' : ep.code,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (ep.airDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(_date(ep.airDate!),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _episodeStatus(ep),
        ],
      ),
    );
  }

  /// Trailing control for an episode row: a spinner while it's being marked, a
  /// checkmark once watched, or a tappable Watch button when it isn't (and a
  /// handler was supplied) — otherwise nothing.
  Widget _episodeStatus(NextEpisode ep) {
    final busy = _busyEpisode != null &&
        _busyEpisode!.season == ep.season &&
        _busyEpisode!.number == ep.number;
    if (busy) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (ep.watched) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 22),
      );
    }
    if (widget.onWatchEpisode == null) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.radio_button_unchecked),
      tooltip: 'Mark ${ep.code} watched',
      onPressed: () => _markEpisodeWatched(ep),
    );
  }

  /// Marks a single episode watched via [ShowDetailDialog.onWatchEpisode],
  /// then reloads the episode list so its row picks up the new watched state
  /// (and the next-episode pointer, if it moved). The dialog stays open.
  Future<void> _markEpisodeWatched(NextEpisode ep) async {
    final callback = widget.onWatchEpisode;
    if (callback == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyEpisode = ep);
    try {
      await callback(ep);
      if (!mounted) return;
      messenger
          .showSnackBar(SnackBar(content: Text('Marked ${ep.code} watched')));
      final loader = widget.loadRemaining;
      if (loader != null) {
        try {
          final eps = await loader();
          if (mounted) setState(() => _remaining = eps);
        } catch (_) {
          // Keep showing the stale list rather than losing it.
        }
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Action failed: $e')));
    } finally {
      if (mounted) setState(() => _busyEpisode = null);
    }
  }

  Widget _thumb(NextEpisode ep) {
    final url = ep.stillUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 96,
        height: 54,
        child: url != null
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    const ColoredBox(color: Color(0xFF1C1C22)),
                errorWidget: (_, __, ___) => const _ThumbFallback(),
              )
            : const _ThumbFallback(),
      ),
    );
  }

  Widget _actions() {
    final title = widget.show.show.title;
    // widget.show is mutated in place by the controller, so re-check
    // nextEpisode here (not just onWatch's presence) — a row-level Watch can
    // catch the show up while this dialog stays open, and a stale button would
    // otherwise null-check-crash on the code below.
    final nextEpisode = widget.show.nextEpisode;
    final primary = <Widget>[
      if (widget.onWatch != null && nextEpisode != null)
        _actionButton(
          icon: Icons.check_rounded,
          label: 'Watch',
          background: const Color(0xFF2E7D32),
          foreground: Colors.white,
          onPressed: () => _run(widget.onWatch!,
              'Marked ${nextEpisode.code} of “$title” watched'),
        ),
      if (widget.onStopWatching != null)
        _actionButton(
          icon: Icons.watch_later_outlined,
          label: 'Stop Watching',
          background: const Color(0xFFB23C17),
          foreground: Colors.white,
          onPressed: () => _run(widget.onStopWatching!,
              'Moved “$title” to Watch Later'),
        ),
    ];
    final hasRemove = widget.onRemoveFromHistory != null;
    if (primary.isEmpty && !hasRemove) return const SizedBox.shrink();

    final primaryRow = <Widget>[];
    for (var i = 0; i < primary.length; i++) {
      if (i > 0) primaryRow.add(const SizedBox(width: 8));
      primaryRow.add(Expanded(child: primary[i]));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (primaryRow.isNotEmpty) Row(children: primaryRow),
          if (hasRemove) ...[
            if (primaryRow.isNotEmpty) const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(widget.onRemoveFromHistory!,
                        'Removed “$title” from history'),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove from History',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE57373),
                  side: const BorderSide(color: Color(0xFF7F1D1D)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color background,
    required Color foreground,
    required Future<void> Function() onPressed,
  }) {
    return FilledButton.icon(
      onPressed: _busy ? null : onPressed,
      icon: Icon(icon),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
      ),
    );
  }

  Future<void> _run(
      Future<void> Function() action, String successMessage) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await action();
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Action failed: $e')));
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF1C1C22),
      child: Icon(Icons.tv_outlined, color: Colors.white24, size: 20),
    );
  }
}

class _Header extends StatelessWidget {
  final WatchlistShow show;
  const _Header({required this.show});

  @override
  Widget build(BuildContext context) {
    final url = show.nextEpisode?.stillUrl ?? show.show.posterUrl;
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, __) => const ColoredBox(color: Color(0xFF1C1C22)),
            errorWidget: (_, __, ___) => const ColoredBox(
              color: Color(0xFF1C1C22),
              child: Icon(Icons.tv_outlined, color: Colors.white24),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  final WatchlistShow show;
  const _MetaRow({required this.show});

  @override
  Widget build(BuildContext context) {
    final item = show.show;
    final year = item.year ?? item.releaseDate?.year;
    final parts = <String>[
      if (year != null) '$year',
      if (_runtime != null) _runtime!,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(parts.join('  •  '),
        style: const TextStyle(color: Colors.white70));
  }

  String? get _runtime {
    final m = show.show.runtime;
    if (m == null || m == 0) return null;
    return '${m}m';
  }
}
