import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../../models/movie_details.dart';
import '../../services/tmdb_api.dart';

/// A dismissible dialog showing rich detail for a movie, with optional
/// Watchlist, Watched and Ignore actions supplied by the calling page. Closing
/// it leaves the underlying page (and its scroll position) untouched.
class MovieDetailDialog extends StatefulWidget {
  final MediaItem item;

  /// Toggle watchlist membership. Stays open unless [closeOnWatchlist] is set.
  final Future<void> Function()? onToggleWatchlist;
  final bool closeOnWatchlist;

  /// Mark watched. Closes the dialog on success.
  final Future<void> Function()? onWatched;

  /// Ignore locally. Closes the dialog on success.
  final Future<void> Function()? onIgnore;

  const MovieDetailDialog({
    super.key,
    required this.item,
    this.onToggleWatchlist,
    this.closeOnWatchlist = false,
    this.onWatched,
    this.onIgnore,
  });

  @override
  State<MovieDetailDialog> createState() => _MovieDetailDialogState();
}

class _MovieDetailDialogState extends State<MovieDetailDialog> {
  late final Future<MovieDetails> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final id = widget.item.ids.tmdb;
    _future = id != null
        ? TmdbApi().movieDetails(id)
        : Future.error(StateError('No TMDB id'));
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
        child: FutureBuilder<MovieDetails>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return _ErrorBody(
                title: widget.item.title,
                onClose: () => Navigator.of(context).pop(),
              );
            }
            return _DetailBody(
              details: snapshot.data!,
              actions: _buildActions(),
            );
          },
        ),
      ),
    );
  }

  Widget _buildActions() {
    final buttons = <Widget>[
      if (widget.onToggleWatchlist != null)
        _actionButton(
          icon: widget.item.onWatchlist
              ? Icons.bookmark_added
              : Icons.bookmark_add_outlined,
          label: widget.item.onWatchlist ? 'On List' : 'Watchlist',
          background: widget.item.onWatchlist
              ? const Color(0xFFF9A825)
              : const Color(0xFF1565C0),
          foreground: widget.item.onWatchlist ? Colors.black : Colors.white,
          onPressed: _runWatchlist,
        ),
      if (widget.onWatched != null)
        _actionButton(
          icon: Icons.check_rounded,
          label: 'Watched',
          background: const Color(0xFF2E7D32),
          foreground: Colors.white,
          onPressed: _runWatched,
        ),
      if (widget.onIgnore != null)
        _actionButton(
          icon: Icons.visibility_off_outlined,
          label: 'Ignore',
          background: const Color(0xFF424242),
          foreground: Colors.white,
          onPressed: _runIgnore,
        ),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();

    final row = <Widget>[];
    for (var i = 0; i < buttons.length; i++) {
      if (i > 0) row.add(const SizedBox(width: 8));
      row.add(Expanded(child: buttons[i]));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(children: row),
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

  Future<void> _runWatchlist() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final wasOnList = widget.item.onWatchlist;
    setState(() => _busy = true);
    try {
      await widget.onToggleWatchlist!();
      if (widget.closeOnWatchlist) navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(wasOnList
            ? 'Removed “${widget.item.title}” from watchlist'
            : 'Added “${widget.item.title}” to watchlist'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Action failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runWatched() => _runClosing(
        widget.onWatched!,
        'Marked “${widget.item.title}” watched',
      );

  Future<void> _runIgnore() => _runClosing(
        widget.onIgnore!,
        'Ignored “${widget.item.title}”',
      );

  Future<void> _runClosing(
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
}

class _DetailBody extends StatelessWidget {
  final MovieDetails details;
  final Widget actions;

  const _DetailBody({required this.details, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(details: details),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(details.title,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
                if (details.tagline != null) ...[
                  const SizedBox(height: 4),
                  Text(details.tagline!,
                      style: const TextStyle(
                          color: Colors.white60,
                          fontStyle: FontStyle.italic)),
                ],
                const SizedBox(height: 10),
                _MetaRow(details: details),
                if (details.genres.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final g in details.genres)
                        Chip(
                          label: Text(g, style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                ],
                if (details.overview != null) ...[
                  const SizedBox(height: 16),
                  Text(details.overview!, style: const TextStyle(height: 1.4)),
                ],
                if (details.directors.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _LabelValue(
                    label: details.directors.length > 1
                        ? 'Directors'
                        : 'Director',
                    value: details.directors.join(', '),
                  ),
                ],
                if (details.cast.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Cast',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _CastStrip(cast: details.cast),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        actions,
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final MovieDetails details;
  const _Header({required this.details});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: details.backdropUrl != null
              ? CachedNetworkImage(
                  imageUrl: details.backdropUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      const ColoredBox(color: Color(0xFF1C1C22)),
                  errorWidget: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFF1C1C22)),
                )
              : const ColoredBox(color: Color(0xFF1C1C22)),
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
  final MovieDetails details;
  const _MetaRow({required this.details});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (details.releaseDate != null) '${details.releaseDate!.year}',
      if (_runtime != null) _runtime!,
      if (details.certification != null) details.certification!,
      if (details.voteAverage != null && details.voteAverage! > 0)
        '★ ${details.voteAverage!.toStringAsFixed(1)}',
    ];
    return Text(parts.join('  •  '),
        style: const TextStyle(color: Colors.white70));
  }

  String? get _runtime {
    final m = details.runtime;
    if (m == null || m == 0) return null;
    final h = m ~/ 60;
    final min = m % 60;
    if (h > 0 && min > 0) return '${h}h ${min}m';
    if (h > 0) return '${h}h';
    return '${min}m';
  }
}

class _LabelValue extends StatelessWidget {
  final String label;
  final String value;
  const _LabelValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _CastStrip extends StatelessWidget {
  final List<CastMember> cast;
  const _CastStrip({required this.cast});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cast.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final member = cast[i];
          return SizedBox(
            width: 80,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: const Color(0xFF1C1C22),
                  backgroundImage: member.profileUrl != null
                      ? CachedNetworkImageProvider(member.profileUrl!)
                      : null,
                  child: member.profileUrl == null
                      ? const Icon(Icons.person, color: Colors.white24)
                      : null,
                ),
                const SizedBox(height: 6),
                Text(member.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600)),
                if (member.character != null)
                  Text(member.character!,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.white54)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  const _ErrorBody({required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          Text('Couldn’t load details for “$title”.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onClose, child: const Text('Close')),
        ],
      ),
    );
  }
}
