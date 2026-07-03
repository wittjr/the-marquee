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

  const NextEpisode({
    required this.season,
    required this.number,
    this.title,
    this.overview,
    this.stillPath,
    this.airDate,
    this.traktId,
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
      };

  factory NextEpisode.fromJson(Map<String, dynamic> json) => NextEpisode(
        season: json['season'] as int? ?? 0,
        number: json['number'] as int? ?? 0,
        title: json['title'] as String?,
        overview: json['overview'] as String?,
        stillPath: json['stillPath'] as String?,
        airDate: parseIsoOrNull(json['airDate']),
        traktId: json['traktId'] as int?,
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

  /// Episodes the user has watched (excluding specials).
  final int watchedEpisodes;

  /// Total episodes that have aired (from the show's full metadata).
  final int airedEpisodes;

  const WatchedShow(
    this.show,
    this.lastWatchedAt, {
    this.watchedEpisodes = 0,
    this.airedEpisodes = 0,
  });

  /// True when there are aired episodes the user hasn't watched yet. When the
  /// aired count is unknown (0), we can't tell, so assume in-progress rather
  /// than hide a show.
  bool get inProgress =>
      airedEpisodes == 0 || watchedEpisodes < airedEpisodes;
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
