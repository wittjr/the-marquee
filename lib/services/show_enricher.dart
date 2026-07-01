import '../models/media_item.dart';
import '../models/watchlist_show.dart';
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
      if (progress.nextEpisode != null) {
        ws.nextEpisode = await buildNextEpisode(show, progress.nextEpisode!);
      }
    } catch (_) {
      // Best-effort: leave as not-started with no next episode.
    }
    return ws;
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
