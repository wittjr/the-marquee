import 'trakt_ids.dart';

enum MediaType { movie, show }

/// Parses a nullable ISO-8601 string back into a [DateTime] for the cache
/// deserializers. Returns null for missing/invalid values.
DateTime? parseIsoOrNull(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// A single watchlist / library entry. Generic over movies and shows so the
/// rest of the app treats them uniformly. Core fields come from Trakt; the
/// remaining (nullable) fields are filled in by TMDB enrichment.
class MediaItem {
  final MediaType type;
  final String title;
  final int? year;
  final TraktIds ids;
  final DateTime? listedAt;

  // --- TMDB enrichment (populated lazily) ---
  String? overview;
  String? posterPath;
  List<String> genres;
  int? runtime;

  /// Date used for sorting on the home page (most recent first).
  /// Movies: theatrical/limited/digital release. Shows: most recently aired
  /// episode, falling back to first air date.
  DateTime? releaseDate;

  /// Whether this item is currently on the user's Trakt watchlist.
  bool onWatchlist;

  /// Whether this item has been marked watched in this session.
  bool watched;

  /// TMDB vote count, used by the "hide obscure" filter on the browse page.
  int? voteCount;

  MediaItem({
    required this.type,
    required this.title,
    required this.ids,
    this.year,
    this.listedAt,
    this.overview,
    this.posterPath,
    List<String>? genres,
    this.runtime,
    this.releaseDate,
    this.onWatchlist = false,
    this.watched = false,
    this.voteCount,
  }) : genres = genres ?? const [];

  bool get isMovie => type == MediaType.movie;
  bool get isShow => type == MediaType.show;

  /// True once the release date has passed (used to gate the Watched action).
  bool get isReleased =>
      releaseDate != null && !releaseDate!.isAfter(DateTime.now());

  String get posterUrl => posterPath != null
      ? 'https://image.tmdb.org/t/p/w500$posterPath'
      : 'https://placehold.co/500x750?text=No+Poster';

  /// Builds an item from a Trakt watchlist/list/history entry, which wraps the
  /// payload under a `movie` or `show` key alongside a `type` discriminator.
  factory MediaItem.fromTraktEntry(Map<String, dynamic> entry) {
    final typeStr = entry['type'] as String? ??
        (entry.containsKey('show') ? 'show' : 'movie');
    final type = typeStr == 'show' ? MediaType.show : MediaType.movie;
    final payload = (entry[typeStr] ?? entry['movie'] ?? entry['show'])
        as Map<String, dynamic>;

    return MediaItem(
      type: type,
      title: payload['title'] as String? ?? 'Untitled',
      year: payload['year'] as int?,
      ids: TraktIds.fromJson(payload['ids'] as Map<String, dynamic>? ?? {}),
      listedAt: entry['listed_at'] != null
          ? DateTime.tryParse(entry['listed_at'] as String)
          : null,
    );
  }

  /// Serializes the full item — including the lazily-populated TMDB enrichment —
  /// for the local cache, so it can be rendered without re-hitting the network.
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'title': title,
        if (year != null) 'year': year,
        'ids': ids.toJson(),
        if (listedAt != null) 'listedAt': listedAt!.toIso8601String(),
        if (overview != null) 'overview': overview,
        if (posterPath != null) 'posterPath': posterPath,
        if (genres.isNotEmpty) 'genres': genres,
        if (runtime != null) 'runtime': runtime,
        if (releaseDate != null) 'releaseDate': releaseDate!.toIso8601String(),
        'onWatchlist': onWatchlist,
        'watched': watched,
        if (voteCount != null) 'voteCount': voteCount,
      };

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
        type: MediaType.values.byName(json['type'] as String? ?? 'movie'),
        title: json['title'] as String? ?? 'Untitled',
        year: json['year'] as int?,
        ids: TraktIds.fromJson(json['ids'] as Map<String, dynamic>? ?? const {}),
        listedAt: parseIsoOrNull(json['listedAt']),
        overview: json['overview'] as String?,
        posterPath: json['posterPath'] as String?,
        genres: (json['genres'] as List<dynamic>?)?.cast<String>(),
        runtime: json['runtime'] as int?,
        releaseDate: parseIsoOrNull(json['releaseDate']),
        onWatchlist: json['onWatchlist'] as bool? ?? false,
        watched: json['watched'] as bool? ?? false,
        voteCount: json['voteCount'] as int?,
      );
}
