import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/trakt_api.dart';
import '../../services/trakt_rate_limit.dart';

/// Overlays the live Trakt rate-limit indicator on [child]: the number of
/// remaining API calls in the upper-right corner and a mm:ss countdown to the
/// window reset in the lower-right (both driven by [TraktApi.rateLimit]).
///
/// When no rate-limit data is available yet, [child] is shown unchanged. A
/// one-second ticker keeps the countdown current.
class RateLimitBadges extends StatefulWidget {
  final Widget child;
  const RateLimitBadges({super.key, required this.child});

  @override
  State<RateLimitBadges> createState() => _RateLimitBadgesState();
}

class _RateLimitBadgesState extends State<RateLimitBadges> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresh the countdown label once a second.
    _ticker =
        Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TraktRateLimit?>(
      valueListenable: TraktApi.rateLimit,
      builder: (context, rl, child) {
        if (rl == null) return child!;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child!,
            Positioned(top: -6, right: -10, child: _remainingBadge(rl)),
            Positioned(bottom: -6, right: -12, child: _resetBadge(rl)),
          ],
        );
      },
      child: widget.child,
    );
  }

  /// Remaining-call count, tinted green→orange→red as the budget runs down.
  Widget _remainingBadge(TraktRateLimit rl) {
    final frac = rl.limit > 0 ? rl.remaining / rl.limit : 1.0;
    final color = frac > 0.5
        ? Colors.green
        : frac > 0.2
            ? Colors.orange
            : Colors.red;
    return _badge('${rl.remaining}', color);
  }

  /// mm:ss countdown until the current rate-limit window resets.
  Widget _resetBadge(TraktRateLimit rl) =>
      _badge(_formatDuration(rl.timeToReset), Colors.blueGrey);

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 9,
            height: 1,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
