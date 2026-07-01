/// A cast member from TMDB credits.
class CastMember {
  final String name;
  final String? character;
  final String? profilePath;

  const CastMember({required this.name, this.character, this.profilePath});

  String? get profileUrl => profilePath != null
      ? 'https://image.tmdb.org/t/p/w185$profilePath'
      : null;

  factory CastMember.fromJson(Map<String, dynamic> json) => CastMember(
        name: json['name'] as String? ?? '',
        character: (json['character'] as String?)?.isNotEmpty == true
            ? json['character'] as String
            : null,
        profilePath: json['profile_path'] as String?,
      );
}

/// Rich movie detail used by the detail dialog. Sourced from TMDB
/// `/movie/{id}?append_to_response=credits,release_dates`.
class MovieDetails {
  final String title;
  final String? overview;
  final String? tagline;
  final int? runtime;
  final List<String> genres;
  final double? voteAverage;
  final DateTime? releaseDate;
  final String? certification;
  final String? backdropPath;
  final String? posterPath;
  final List<String> directors;
  final List<CastMember> cast;

  const MovieDetails({
    required this.title,
    this.overview,
    this.tagline,
    this.runtime,
    this.genres = const [],
    this.voteAverage,
    this.releaseDate,
    this.certification,
    this.backdropPath,
    this.posterPath,
    this.directors = const [],
    this.cast = const [],
  });

  String? get backdropUrl => backdropPath != null
      ? 'https://image.tmdb.org/t/p/w780$backdropPath'
      : null;

  factory MovieDetails.fromJson(Map<String, dynamic> json) {
    final credits = json['credits'] as Map<String, dynamic>?;

    final cast = (credits?['cast'] as List<dynamic>? ?? const [])
        .take(15)
        .map((c) => CastMember.fromJson(c as Map<String, dynamic>))
        .toList();

    final directors = (credits?['crew'] as List<dynamic>? ?? const [])
        .where((c) => (c as Map<String, dynamic>)['job'] == 'Director')
        .map((c) => (c as Map<String, dynamic>)['name'] as String)
        .toList();

    final genres = (json['genres'] as List<dynamic>? ?? const [])
        .map((g) => (g as Map<String, dynamic>)['name'] as String)
        .toList();

    return MovieDetails(
      title: json['title'] as String? ?? 'Untitled',
      overview: (json['overview'] as String?)?.isNotEmpty == true
          ? json['overview'] as String
          : null,
      tagline: (json['tagline'] as String?)?.isNotEmpty == true
          ? json['tagline'] as String
          : null,
      runtime: json['runtime'] as int?,
      genres: genres,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      releaseDate: _parseDate(json['release_date'] as String?),
      certification: _usCertification(json),
      backdropPath: json['backdrop_path'] as String?,
      posterPath: json['poster_path'] as String?,
      directors: directors,
      cast: cast,
    );
  }

  static DateTime? _parseDate(String? value) =>
      (value == null || value.isEmpty) ? null : DateTime.tryParse(value);

  /// Pulls the first non-empty US certification (e.g. PG-13) if present.
  static String? _usCertification(Map<String, dynamic> json) {
    final results =
        (json['release_dates'] as Map<String, dynamic>?)?['results']
            as List<dynamic>?;
    if (results == null) return null;
    for (final r in results) {
      if ((r as Map<String, dynamic>)['iso_3166_1'] != 'US') continue;
      for (final d in (r['release_dates'] as List<dynamic>)) {
        final cert = (d as Map<String, dynamic>)['certification'] as String?;
        if (cert != null && cert.isNotEmpty) return cert;
      }
    }
    return null;
  }
}
