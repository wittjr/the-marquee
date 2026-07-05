import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/media_item.dart';

/// A full-width row for a movie, mirroring [ShowEpisodeCard]'s compact layout
/// (poster thumbnail + title + release date) with a Watched button. Other
/// actions (watchlist) live in the detail dialog opened via [onTap].
class MovieRowCard extends StatelessWidget {
  final MediaItem item;
  final bool busy;

  /// Mark watched. Null hides the button (e.g. for unreleased movies).
  final VoidCallback? onWatched;

  /// Opens the movie detail dialog when the row (outside the button) is tapped.
  final VoidCallback? onTap;

  const MovieRowCard({
    super.key,
    required this.item,
    this.busy = false,
    this.onWatched,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF15151A),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 47,
                      height: 70,
                      child: _image(),
                    ),
                  ),
                  if (item.watched)
                    const Positioned(top: 4, left: 4, child: _WatchedDot()),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (onWatched != null) _watchedButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _image() {
    return CachedNetworkImage(
      imageUrl: item.posterUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => const ColoredBox(color: Color(0xFF1C1C22)),
      errorWidget: (_, __, ___) => const ColoredBox(
        color: Color(0xFF1C1C22),
        child: Icon(Icons.movie_outlined, color: Colors.white24),
      ),
    );
  }

  Widget _watchedButton() {
    return SizedBox(
      width: 116,
      height: 40,
      child: FilledButton.icon(
        onPressed: busy ? null : onWatched,
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_rounded, size: 18),
        label: Text(busy ? '' : 'Watched', maxLines: 1, softWrap: false),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }

  String get _subtitle {
    final date = item.releaseDate;
    if (date == null) return item.year?.toString() ?? 'TBA';
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$d';
  }
}

/// A small green check pinned to the poster corner when the movie is watched.
class _WatchedDot extends StatelessWidget {
  const _WatchedDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: Color(0xE62E7D32),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
    );
  }
}
