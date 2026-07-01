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

  const ShowDetailDialog({
    super.key,
    required this.show,
    this.onWatch,
    this.onStopWatching,
    this.onRemoveFromHistory,
  });

  @override
  State<ShowDetailDialog> createState() => _ShowDetailDialogState();
}

class _ShowDetailDialogState extends State<ShowDetailDialog> {
  bool _busy = false;

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
          if (ep != null) ...[
            const SizedBox(height: 16),
            const Text('Next episode',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              ep.title != null ? '${ep.code} · ${ep.title}' : ep.code,
              style: const TextStyle(color: Colors.white70),
            ),
            if (ep.airDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(_date(ep.airDate!),
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            if (ep.overview != null && ep.overview!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(ep.overview!, style: const TextStyle(height: 1.4)),
            ],
          ],
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

  Widget _actions() {
    final title = widget.show.show.title;
    final primary = <Widget>[
      if (widget.onWatch != null)
        _actionButton(
          icon: Icons.check_rounded,
          label: 'Watch',
          background: const Color(0xFF2E7D32),
          foreground: Colors.white,
          onPressed: () => _run(widget.onWatch!,
              'Marked ${widget.show.nextEpisode!.code} of “$title” watched'),
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
