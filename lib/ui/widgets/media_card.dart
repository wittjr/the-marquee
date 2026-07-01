import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/media_item.dart';

/// A poster card for a single movie/show, with optional Watched, Watchlist and
/// Ignore actions. Buttons render only for the callbacks that are provided.
class MediaCard extends StatelessWidget {
  final MediaItem item;
  final bool busy;

  /// Mark watched. Null hides the button (e.g. for shows).
  final VoidCallback? onWatched;

  /// Add/remove from watchlist. Null hides the button.
  final VoidCallback? onToggleWatchlist;

  /// Hide this item locally. Null hides the button.
  final VoidCallback? onIgnore;

  /// Tapping the poster (e.g. to open details). Null disables the tap.
  final VoidCallback? onTap;

  const MediaCard({
    super.key,
    required this.item,
    this.busy = false,
    this.onWatched,
    this.onToggleWatchlist,
    this.onIgnore,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: item.posterUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      const ColoredBox(color: Color(0xFF1C1C22)),
                  errorWidget: (_, __, ___) => const ColoredBox(
                    color: Color(0xFF1C1C22),
                    child: Icon(Icons.movie_outlined, color: Colors.white24),
                  ),
                ),
                if (busy)
                  const ColoredBox(
                    color: Color(0x99000000),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                if (item.watched)
                  const Positioned(top: 6, left: 6, child: _WatchedBadge()),
              ],
            ),
          ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          _subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        ..._buildActions(),
      ],
    );
  }

  List<Widget> _buildActions() {
    final actions = <Widget>[
      if (onWatched != null)
        _ActionButton(
          icon: Icons.check_rounded,
          label: 'Watched',
          background: const Color(0xFF2E7D32), // green
          foreground: Colors.white,
          onPressed: busy ? null : onWatched,
        ),
      if (onToggleWatchlist != null)
        if (item.onWatchlist)
          _ActionButton(
            icon: Icons.bookmark_added,
            label: 'On List',
            background: const Color(0xFFF9A825), // amber — already saved
            foreground: Colors.black,
            onPressed: busy ? null : onToggleWatchlist,
          )
        else
          _ActionButton(
            icon: Icons.bookmark_add_outlined,
            label: 'Watchlist',
            background: const Color(0xFF1565C0), // blue — add
            foreground: Colors.white,
            onPressed: busy ? null : onToggleWatchlist,
          ),
      if (onIgnore != null)
        _ActionButton(
          icon: Icons.visibility_off_outlined,
          label: 'Ignore',
          background: const Color(0xFF424242), // neutral grey
          foreground: Colors.white,
          onPressed: busy ? null : onIgnore,
        ),
    ];
    if (actions.isEmpty) return const [];

    final row = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      if (i > 0) row.add(const SizedBox(width: 6));
      row.add(Expanded(child: actions[i]));
    }
    return [const SizedBox(height: 6), Row(children: row)];
  }

  String get _subtitle {
    final date = item.releaseDate;
    if (date == null) return item.year?.toString() ?? 'TBA';
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$d';
  }
}

/// A small "Watched" pill shown over the poster when the user has watched the
/// item.
class _WatchedBadge extends StatelessWidget {
  const _WatchedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xE62E7D32), // green, mostly opaque
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 13, color: Colors.white),
          SizedBox(width: 3),
          Text('Watched',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Compact, color-coded icon+label button sized to fit two-up in a grid cell.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.4),
          disabledForegroundColor: foreground.withValues(alpha: 0.7),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
