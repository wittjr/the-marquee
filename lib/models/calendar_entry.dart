import 'media_item.dart';
import 'trakt_ids.dart';

/// A single upcoming episode from Trakt's personalized calendar
/// (`/calendars/my/shows/...`). Pairs the airing episode with its parent show
/// (as a [MediaItem] so it can flow through TMDB enrichment and the existing
/// show cards) plus the exact air time.
class CalendarEntry {
  /// When the episode airs, in the user's local time (Trakt returns UTC).
  final DateTime airsAt;

  final int season;
  final int number;
  final String? episodeTitle;
  final String? overview;

  /// Trakt episode id, usable to mark this episode watched later.
  final int? episodeTraktId;

  /// The parent show, carrying the ids TMDB enrichment keys off of.
  final MediaItem show;

  CalendarEntry({
    required this.airsAt,
    required this.season,
    required this.number,
    required this.show,
    this.episodeTitle,
    this.overview,
    this.episodeTraktId,
  });

  String get code => 'S${_pad(season)}E${_pad(number)}';

  /// True for a season premiere (the calendar doesn't flag these itself, but a
  /// first-episode airing is a useful "new season" signal for the UI).
  bool get isSeasonPremiere => number == 1;

  static String _pad(int v) => v.toString().padLeft(2, '0');

  /// Parses one row of the `/calendars/my/shows` response, which nests the
  /// episode under `episode` and the show under `show`, alongside a top-level
  /// `first_aired` timestamp.
  factory CalendarEntry.fromTrakt(Map<String, dynamic> json) {
    final episode = json['episode'] as Map<String, dynamic>? ?? const {};
    final showJson = json['show'] as Map<String, dynamic>? ?? const {};
    final airedUtc = DateTime.tryParse(json['first_aired'] as String? ?? '');

    return CalendarEntry(
      airsAt: (airedUtc ?? DateTime.now()).toLocal(),
      season: episode['season'] as int? ?? 0,
      number: episode['number'] as int? ?? 0,
      episodeTitle: episode['title'] as String?,
      overview: episode['overview'] as String?,
      episodeTraktId:
          (episode['ids'] as Map<String, dynamic>?)?['trakt'] as int?,
      show: MediaItem(
        type: MediaType.show,
        title: showJson['title'] as String? ?? 'Untitled',
        year: showJson['year'] as int?,
        ids: TraktIds.fromJson(
            showJson['ids'] as Map<String, dynamic>? ?? const {}),
      ),
    );
  }

  /// Serializes the entry (including its enriched show) for the local snapshot,
  /// so the upcoming section renders instantly on a cold start.
  Map<String, dynamic> toJson() => {
        'airsAt': airsAt.toIso8601String(),
        'season': season,
        'number': number,
        if (episodeTitle != null) 'episodeTitle': episodeTitle,
        if (overview != null) 'overview': overview,
        if (episodeTraktId != null) 'episodeTraktId': episodeTraktId,
        'show': show.toJson(),
      };

  factory CalendarEntry.fromJson(Map<String, dynamic> json) => CalendarEntry(
        airsAt: parseIsoOrNull(json['airsAt']) ?? DateTime.now(),
        season: json['season'] as int? ?? 0,
        number: json['number'] as int? ?? 0,
        episodeTitle: json['episodeTitle'] as String?,
        overview: json['overview'] as String?,
        episodeTraktId: json['episodeTraktId'] as int?,
        show: MediaItem.fromJson(json['show'] as Map<String, dynamic>),
      );
}
