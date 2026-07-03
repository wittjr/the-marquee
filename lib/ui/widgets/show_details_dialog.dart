import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../../models/show_details.dart';
import '../../services/tmdb_api.dart';

/// A dismissible dialog showing rich detail for a TV show in Discover, fetched
/// from TMDB, with a Watchlist toggle. The browse-side counterpart to
/// [MovieDetailDialog]; distinct from `ShowDetailDialog`, which shows watch
/// progress for a show already on the watchlist.
class ShowDetailsDialog extends StatefulWidget {
  final MediaItem item;

  /// Toggle watchlist membership. The dialog stays open and reflects the new
  /// state on its button.
  final Future<void> Function()? onToggleWatchlist;

  const ShowDetailsDialog({
    super.key,
    required this.item,
    this.onToggleWatchlist,
  });

  @override
  State<ShowDetailsDialog> createState() => _ShowDetailsDialogState();
}

class _ShowDetailsDialogState extends State<ShowDetailsDialog> {
  late final Future<ShowDetails> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final id = widget.item.ids.tmdb;
    _future = id != null
        ? TmdbApi().showDetails(id)
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
        child: FutureBuilder<ShowDetails>(
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
    if (widget.onToggleWatchlist == null) return const SizedBox.shrink();
    final onList = widget.item.onWatchlist;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _busy ? null : _runWatchlist,
          icon: Icon(onList
              ? Icons.bookmark_added
              : Icons.bookmark_add_outlined),
          label: Text(onList ? 'On List' : 'Add to Watchlist',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          style: FilledButton.styleFrom(
            backgroundColor:
                onList ? const Color(0xFFF9A825) : const Color(0xFF1565C0),
            foregroundColor: onList ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }

  Future<void> _runWatchlist() async {
    final messenger = ScaffoldMessenger.of(context);
    final wasOnList = widget.item.onWatchlist;
    setState(() => _busy = true);
    try {
      await widget.onToggleWatchlist!();
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
}

class _DetailBody extends StatelessWidget {
  final ShowDetails details;
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
                          color: Colors.white60, fontStyle: FontStyle.italic)),
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
                if (details.creators.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _LabelValue(
                    label: details.creators.length > 1 ? 'Creators' : 'Creator',
                    value: details.creators.join(', '),
                  ),
                ],
                if (details.status != null) ...[
                  const SizedBox(height: 8),
                  _LabelValue(label: 'Status', value: details.status!),
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
  final ShowDetails details;
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
  final ShowDetails details;
  const _MetaRow({required this.details});

  @override
  Widget build(BuildContext context) {
    final seasons = details.numberOfSeasons;
    final parts = <String>[
      if (details.firstAirDate != null) '${details.firstAirDate!.year}',
      if (seasons != null && seasons > 0)
        '$seasons ${seasons == 1 ? 'Season' : 'Seasons'}',
      if (_runtime != null) _runtime!,
      if (details.voteAverage != null && details.voteAverage! > 0)
        '★ ${details.voteAverage!.toStringAsFixed(1)}',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(parts.join('  •  '),
        style: const TextStyle(color: Colors.white70));
  }

  String? get _runtime {
    final m = details.episodeRuntime;
    if (m == null || m == 0) return null;
    return '${m}m';
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
                      style:
                          const TextStyle(fontSize: 10, color: Colors.white54)),
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
