import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/watchlist_show.dart';

/// A full-width row for a watchlist show, showing the next episode to watch
/// (still image + title + air date) and a Watch button that marks it watched.
class ShowEpisodeCard extends StatelessWidget {
  final WatchlistShow show;
  final bool busy;
  final VoidCallback? onWatch;

  /// Opens the show detail dialog when the row (outside the Watch button) is
  /// tapped.
  final VoidCallback? onTap;

  const ShowEpisodeCard({
    super.key,
    required this.show,
    this.busy = false,
    this.onWatch,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ep = show.nextEpisode;

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
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 124,
              height: 70,
              child: _image(ep),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(show.show.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                if (ep != null) ...[
                  Text(
                    ep.title != null ? '${ep.code} · ${ep.title}' : ep.code,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  if (ep.airDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(_date(ep.airDate!),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ),
                ] else
                  const Text('All caught up',
                      style: TextStyle(
                          color: Color(0xFF4CAF50),
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (ep != null) _watchButton(),
        ],
          ),
        ),
      ),
    );
  }

  Widget _image(NextEpisode? ep) {
    final url = ep?.stillUrl ?? show.show.posterUrl;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => const ColoredBox(color: Color(0xFF1C1C22)),
      errorWidget: (_, __, ___) => const ColoredBox(
        color: Color(0xFF1C1C22),
        child: Icon(Icons.tv_outlined, color: Colors.white24),
      ),
    );
  }

  Widget _watchButton() {
    return SizedBox(
      width: 96,
      height: 40,
      child: FilledButton.icon(
        onPressed: busy ? null : onWatch,
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_rounded, size: 18),
        label: Text(busy ? '' : 'Watch'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
}
