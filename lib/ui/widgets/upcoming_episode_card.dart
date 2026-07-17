import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/calendar_entry.dart';

/// A full-width row for an upcoming episode from Trakt's calendar, mirroring
/// [MovieRowCard]'s compact layout (poster thumbnail + title + subtitle). There
/// is no action button — the episode hasn't aired yet, so there's nothing to
/// mark watched.
class UpcomingEpisodeCard extends StatelessWidget {
  final CalendarEntry entry;
  final VoidCallback? onTap;

  const UpcomingEpisodeCard({
    super.key,
    required this.entry,
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
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(width: 47, height: 70, child: _image()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(entry.show.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      _episodeLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _airLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _daysBadge(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Right-aligned countdown: the day count over a "days" caption, or "Today"
  /// / "Aired" when a count doesn't apply.
  Widget _daysBadge() {
    final days = _daysUntilAir;
    if (days <= 0) {
      return Text(
        days == 0 ? 'Today' : 'Aired',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$days',
            style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        Text(days == 1 ? 'day' : 'days',
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }

  Widget _image() {
    return CachedNetworkImage(
      imageUrl: entry.show.posterUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => const ColoredBox(color: Color(0xFF1C1C22)),
      errorWidget: (_, __, ___) => const ColoredBox(
        color: Color(0xFF1C1C22),
        child: Icon(Icons.tv_outlined, color: Colors.white24),
      ),
    );
  }

  String get _episodeLine {
    final t = entry.episodeTitle;
    return t != null ? '${entry.code} · $t' : entry.code;
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Whole calendar days from today until the air date (0 = today, negative =
  /// already aired).
  int get _daysUntilAir {
    final d = entry.airsAt;
    final now = DateTime.now();
    final airDay = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    return airDay.difference(today).inDays;
  }

  /// A friendly air line: "Today", "Tomorrow", or "Mon, Jul 8" for dates within
  /// the week, otherwise "Jul 8, 2026". A season premiere is flagged.
  String get _airLine {
    final d = entry.airsAt;
    final days = _daysUntilAir;

    String label;
    if (days == 0) {
      label = 'Today';
    } else if (days == 1) {
      label = 'Tomorrow';
    } else if (days > 1 && days < 7) {
      label = '${_weekday(d)}, ${_months[d.month - 1]} ${d.day}';
    } else {
      label = '${_months[d.month - 1]} ${d.day}, ${d.year}';
    }
    return entry.isSeasonPremiere ? '$label · Season premiere' : label;
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static String _weekday(DateTime d) => _weekdays[d.weekday - 1];
}
