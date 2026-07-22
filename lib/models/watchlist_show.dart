import 'media_item.dart';

/// The next episode a user should watch for a show, combining Trakt progress
/// (season/number/ids) with TMDB metadata (title, still image, air date).
class NextEpisode {
  final int season;
  final int number;
  final String? title;
  final String? overview;
  final String? stillPath;
  final DateTime? airDate;

  /// Trakt episode id, used to mark this episode watched.
  final int? traktId;

  /// Whether the user has already watched this episode. Only meaningful for
  /// entries coming from [ShowEnricher.remainingEpisodes], which lists every
  /// episode of an in-progress season (not just the unwatched ones); the
  /// single "next episode" pointer is always unwatched by definition.
  final bool watched;

  const NextEpisode({
    required this.season,
    required this.number,
    this.title,
    this.overview,
    this.stillPath,
    this.airDate,
    this.traktId,
    this.watched = false,
  });

  String get code => 'S${_pad(season)}E${_pad(number)}';

  String? get stillUrl => stillPath != null
      ? 'https://image.tmdb.org/t/p/w500$stillPath'
      : null;

  static String _pad(int v) => v.toString().padLeft(2, '0');

  Map<String, dynamic> toJson() => {
        'season': season,
        'number': number,
        if (title != null) 'title': title,
        if (overview != null) 'overview': overview,
        if (stillPath != null) 'stillPath': stillPath,
        if (airDate != null) 'airDate': airDate!.toIso8601String(),
        if (traktId != null) 'traktId': traktId,
        if (watched) 'watched': watched,
      };

  factory NextEpisode.fromJson(Map<String, dynamic> json) => NextEpisode(
        season: json['season'] as int? ?? 0,
        number: json['number'] as int? ?? 0,
        title: json['title'] as String?,
        overview: json['overview'] as String?,
        stillPath: json['stillPath'] as String?,
        airDate: parseIsoOrNull(json['airDate']),
        traktId: json['traktId'] as int?,
        watched: json['watched'] as bool? ?? false,
      );
}

/// A watchlist TV show together with its viewing progress and next episode.
class WatchlistShow {
  final MediaItem show;

  /// Whether any episode has been watched.
  bool hasViews;

  /// When the most recent episode was watched.
  DateTime? lastWatchedAt;

  /// Most recently aired episode date (from show enrichment) — used to decide
  /// "released within the last month".
  final DateTime? releaseDate;

  /// The next episode to watch; null when fully caught up.
  NextEpisode? nextEpisode;

  /// Count of already-aired episodes the user hasn't watched yet (aired −
  /// watched). Drives the "remaining episodes" badge on the show card.
  int remainingReleased;

  WatchlistShow({
    required this.show,
    this.hasViews = false,
    this.lastWatchedAt,
    this.releaseDate,
    this.nextEpisode,
    this.remainingReleased = 0,
  });

  bool get caughtUp => nextEpisode == null;

  /// TMDB statuses that mean a show hasn't started airing yet.
  static const _preAirStatuses = {'Planned', 'In Production', 'Post Production'};

  /// True when the show hasn't premiered yet — no episodes have aired to watch.
  /// Primary signal is a first air date still in the future (for aired shows
  /// [releaseDate] is the most recent aired episode, always in the past). When
  /// the air date is unknown (unannounced), fall back to the production status
  /// so an in-production show isn't misfiled as "Not Started".
  bool get upcoming {
    final d = releaseDate;
    if (d != null) return d.isAfter(DateTime.now());
    return _preAirStatuses.contains(show.status);
  }

  /// Sort key for the "Recently Watched / Just Released" section: the later of
  /// the last watch and the latest aired episode.
  DateTime? get sortDate {
    final a = lastWatchedAt;
    final b = releaseDate;
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  Map<String, dynamic> toJson() => {
        'show': show.toJson(),
        'hasViews': hasViews,
        if (lastWatchedAt != null)
          'lastWatchedAt': lastWatchedAt!.toIso8601String(),
        if (releaseDate != null) 'releaseDate': releaseDate!.toIso8601String(),
        if (nextEpisode != null) 'nextEpisode': nextEpisode!.toJson(),
        if (remainingReleased > 0) 'remainingReleased': remainingReleased,
      };

  factory WatchlistShow.fromJson(Map<String, dynamic> json) => WatchlistShow(
        show: MediaItem.fromJson(json['show'] as Map<String, dynamic>),
        hasViews: json['hasViews'] as bool? ?? false,
        lastWatchedAt: parseIsoOrNull(json['lastWatchedAt']),
        releaseDate: parseIsoOrNull(json['releaseDate']),
        nextEpisode: json['nextEpisode'] != null
            ? NextEpisode.fromJson(json['nextEpisode'] as Map<String, dynamic>)
            : null,
        remainingReleased: json['remainingReleased'] as int? ?? 0,
      );
}

/// A show from Trakt's "watched shows" endpoint, with enough detail to tell
/// whether the user still has aired episodes left to watch — so we only resolve
/// full next-episode progress for shows that are actually in progress.
class WatchedShow {
  final MediaItem show;
  final DateTime? lastWatchedAt;

  /// Total episode plays for the show (Trakt's `plays`). The watched-shows list
  /// endpoint no longer returns a per-season episode breakdown, so this is the
  /// only watched-volume signal available without a per-show progress call. It
  /// counts rewatches, so it's a heuristic, not a distinct-episode count.
  final int plays;

  /// Total episodes that have aired (from the show's full metadata).
  final int airedEpisodes;

  const WatchedShow(
    this.show,
    this.lastWatchedAt, {
    this.plays = 0,
    this.airedEpisodes = 0,
  });

  /// True when the user likely still has aired episodes left to watch — used to
  /// avoid a per-show progress call for shows they've finished. Compares total
  /// plays against aired episodes: fewer plays than aired means something's
  /// left. When the aired count is unknown (0) we can't tell, so assume
  /// in-progress rather than drop the show. This is a cheap pre-filter; the
  /// accurate next-episode is still resolved by [ShowEnricher] for kept shows.
  /// Caveat: heavy rewatching can inflate plays past the aired count and hide a
  /// genuinely in-progress show — watchlisting it bypasses this path entirely.
  bool get inProgress => airedEpisodes == 0 || plays < airedEpisodes;
}

/// Raw watched-progress for a show from Trakt's progress endpoint.
class ShowProgress {
  final int completed;

  /// Episodes that have already aired (excluding specials).
  final int aired;
  final DateTime? lastWatchedAt;
  final RawNextEpisode? nextEpisode;

  const ShowProgress({
    this.completed = 0,
    this.aired = 0,
    this.lastWatchedAt,
    this.nextEpisode,
  });

  /// Already-aired episodes the user hasn't watched yet.
  int get remainingReleased => (aired - completed).clamp(0, aired).toInt();
}

/// The next-episode pointer as Trakt returns it (no images/metadata).
class RawNextEpisode {
  final int season;
  final int number;
  final String? title;
  final int? traktId;

  const RawNextEpisode({
    required this.season,
    required this.number,
    this.title,
    this.traktId,
  });
}

/// TMDB episode metadata.
class TmdbEpisode {
  final int number;
  final String? name;
  final String? stillPath;
  final DateTime? airDate;
  final String? overview;

  const TmdbEpisode({
    this.number = 0,
    this.name,
    this.stillPath,
    this.airDate,
    this.overview,
  });
}

/// A show's per-season watched progress from Trakt: which episode numbers are
/// completed, plus the aired/completed counts so fully-watched seasons can be
/// skipped when listing what's left.
class SeasonProgress {
  final int number;
  final int aired;
  final int completed;
  final Set<int> watchedNumbers;

  const SeasonProgress({
    required this.number,
    this.aired = 0,
    this.completed = 0,
    this.watchedNumbers = const {},
  });
}
