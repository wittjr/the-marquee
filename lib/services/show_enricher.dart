import '../models/media_item.dart';
import '../models/watchlist_show.dart';
import 'concurrency.dart';
import 'tmdb_api.dart';
import 'trakt_api.dart';

/// Builds [WatchlistShow]s by combining Trakt watched-progress with TMDB
/// episode metadata. Shared by the watchlist and TV Shows pages so both resolve
/// "next episode" identically (including the unaired/unknown-air-date rules).
class ShowEnricher {
  final TraktApi trakt;
  final TmdbApi tmdb;

  ShowEnricher(this.trakt, this.tmdb);

  /// Fetches watched progress + next-episode metadata for a single show.
  /// Best-effort: leaves the show not-started with no next episode on failure.
  Future<WatchlistShow> buildShow(MediaItem show) async {
    final ws = WatchlistShow(show: show, releaseDate: show.releaseDate);
    try {
      final progress = await trakt.showProgress(show);
      ws.hasViews = progress.completed > 0 || progress.lastWatchedAt != null;
      ws.lastWatchedAt = progress.lastWatchedAt;
      ws.remainingReleased = progress.remainingReleased;
      if (progress.nextEpisode != null) {
        // Trakt's aired−watched count is the authority on whether the next
        // episode has actually aired; when it says episodes remain, trust that
        // so a missing/failed TMDB lookup can't make the episode disappear.
        ws.nextEpisode = await buildNextEpisode(show, progress.nextEpisode!,
            assumeAired: progress.remainingReleased > 0);
      }
      // Trakt reports no next_episode pointer in some cases where aired episodes
      // still remain — e.g. episodes watched out of order, or a gap before the
      // watched season. Fall back to the per-season breakdown so the show shows
      // its real next episode instead of being mislabeled "All caught up".
      if (ws.nextEpisode == null && progress.remainingReleased > 0) {
        final remaining = await remainingEpisodes(show);
        if (remaining.isNotEmpty) ws.nextEpisode = remaining.first;
      }
    } catch (_) {
      // Best-effort: leave as not-started with no next episode.
    }
    return ws;
  }

  /// Lists the already-aired episodes the user hasn't watched yet (the next
  /// episode first), combining Trakt's per-season watched breakdown with TMDB
  /// titles/stills/air dates. Only seasons with something left are fetched from
  /// TMDB, so a caught-up show costs a single Trakt call. Best-effort: returns
  /// what it can and never throws.
  Future<List<NextEpisode>> remainingEpisodes(MediaItem show) async {
    final tmdbId = show.ids.tmdb;
    if (tmdbId == null) return const [];
    try {
      final seasons = await trakt.seasonProgress(show);
      // Skip fully-watched seasons (and unaired ones) before hitting TMDB.
      final pending = seasons
          .where((s) => s.aired > 0 && s.completed < s.aired)
          .toList();

      final now = DateTime.now();
      final perSeason = await pooledMap(pending, (SeasonProgress s) async {
        final eps = await tmdb.seasonEpisodes(tmdbId, s.number);
        return [
          for (final ep in eps)
            if (ep.airDate != null &&
                !ep.airDate!.isAfter(now) &&
                !s.watchedNumbers.contains(ep.number))
              NextEpisode(
                season: s.number,
                number: ep.number,
                title: ep.name,
                overview: ep.overview,
                stillPath: ep.stillPath,
                airDate: ep.airDate,
              ),
        ];
      });

      final out = [for (final list in perSeason) ...list];
      out.sort((a, b) => a.season != b.season
          ? a.season.compareTo(b.season)
          : a.number.compareTo(b.number));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Combines Trakt's next-episode pointer with TMDB still/title/air date.
  /// Returns null only when we're confident the episode hasn't aired yet, so
  /// unreleased episodes aren't surfaced as something to watch.
  ///
  /// [assumeAired] should be set when Trakt already reports aired-but-unwatched
  /// episodes for this show: it means the next episode has aired regardless of
  /// what TMDB says, so a missing/failed TMDB lookup still yields a usable next
  /// episode (built from Trakt's raw pointer, minus the still image) rather than
  /// silently dropping the show. Without it, we only surface episodes TMDB
  /// confirms have aired.
  Future<NextEpisode?> buildNextEpisode(
      MediaItem show, RawNextEpisode raw,
      {bool assumeAired = false}) async {
    final tmdbId = show.ids.tmdb;
    TmdbEpisode? ep;
    try {
      if (tmdbId != null) {
        ep = await tmdb.episodeDetails(tmdbId, raw.season, raw.number);
      }
    } catch (_) {
      // TMDB metadata unavailable; fall back to Trakt's raw pointer below.
    }
    final airDate = ep?.airDate;
    final aired =
        assumeAired || (airDate != null && !airDate.isAfter(DateTime.now()));
    if (!aired) return null;
    return NextEpisode(
      season: raw.season,
      number: raw.number,
      title: ep?.name ?? raw.title,
      overview: ep?.overview,
      stillPath: ep?.stillPath,
      airDate: ep?.airDate,
      traktId: raw.traktId,
    );
  }
}
