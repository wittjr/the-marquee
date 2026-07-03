import 'movie_details.dart' show CastMember;

export 'movie_details.dart' show CastMember;

/// Rich TV show detail used by the Discover show detail dialog. Sourced from
/// TMDB `/tv/{id}?append_to_response=credits`. The show equivalent of
/// [MovieDetails].
class ShowDetails {
  final String title;
  final String? overview;
  final String? tagline;
  final List<String> genres;
  final double? voteAverage;
  final DateTime? firstAirDate;
  final int? numberOfSeasons;
  final int? numberOfEpisodes;

  /// Typical episode runtime in minutes (first of TMDB's list), if known.
  final int? episodeRuntime;

  /// TMDB production status (e.g. "Returning Series", "Ended", "In Production").
  final String? status;
  final String? backdropPath;
  final String? posterPath;
  final List<String> creators;
  final List<CastMember> cast;

  const ShowDetails({
    required this.title,
    this.overview,
    this.tagline,
    this.genres = const [],
    this.voteAverage,
    this.firstAirDate,
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.episodeRuntime,
    this.status,
    this.backdropPath,
    this.posterPath,
    this.creators = const [],
    this.cast = const [],
  });

  String? get backdropUrl => backdropPath != null
      ? 'https://image.tmdb.org/t/p/w780$backdropPath'
      : null;

  factory ShowDetails.fromJson(Map<String, dynamic> json) {
    final credits = json['credits'] as Map<String, dynamic>?;

    final cast = (credits?['cast'] as List<dynamic>? ?? const [])
        .take(15)
        .map((c) => CastMember.fromJson(c as Map<String, dynamic>))
        .toList();

    final creators = (json['created_by'] as List<dynamic>? ?? const [])
        .map((c) => (c as Map<String, dynamic>)['name'] as String?)
        .whereType<String>()
        .toList();

    final genres = (json['genres'] as List<dynamic>? ?? const [])
        .map((g) => (g as Map<String, dynamic>)['name'] as String)
        .toList();

    final runtimes = json['episode_run_time'] as List<dynamic>?;

    return ShowDetails(
      title: json['name'] as String? ?? 'Untitled',
      overview: (json['overview'] as String?)?.isNotEmpty == true
          ? json['overview'] as String
          : null,
      tagline: (json['tagline'] as String?)?.isNotEmpty == true
          ? json['tagline'] as String
          : null,
      genres: genres,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      firstAirDate: _parseDate(json['first_air_date'] as String?),
      numberOfSeasons: json['number_of_seasons'] as int?,
      numberOfEpisodes: json['number_of_episodes'] as int?,
      episodeRuntime: (runtimes != null && runtimes.isNotEmpty)
          ? runtimes.first as int?
          : null,
      status: json['status'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      posterPath: json['poster_path'] as String?,
      creators: creators,
      cast: cast,
    );
  }

  static DateTime? _parseDate(String? value) =>
      (value == null || value.isEmpty) ? null : DateTime.tryParse(value);
}
