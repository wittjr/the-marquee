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
        ws.nextEpisode = await buildNextEpisode(show, progress.nextEpisode!);
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
  /// Returns null when the episode has no known air date or hasn't aired yet,
  /// so unreleased episodes aren't surfaced as something to watch.
  Future<NextEpisode?> buildNextEpisode(
      MediaItem show, RawNextEpisode raw) async {
    final tmdbId = show.ids.tmdb;
    final ep = tmdbId != null
        ? await tmdb.episodeDetails(tmdbId, raw.season, raw.number)
        : null;
    final airDate = ep?.airDate;
    if (airDate == null || airDate.isAfter(DateTime.now())) return null;
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
