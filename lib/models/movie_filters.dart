/// A single TMDB movie genre.
class MovieGenre {
  final int id;
  final String name;
  const MovieGenre(this.id, this.name);
}

/// The stable TMDB movie genre list (avoids an API round-trip).
const List<MovieGenre> kMovieGenres = [
  MovieGenre(28, 'Action'),
  MovieGenre(12, 'Adventure'),
  MovieGenre(16, 'Animation'),
  MovieGenre(35, 'Comedy'),
  MovieGenre(80, 'Crime'),
  MovieGenre(99, 'Documentary'),
  MovieGenre(18, 'Drama'),
  MovieGenre(10751, 'Family'),
  MovieGenre(14, 'Fantasy'),
  MovieGenre(36, 'History'),
  MovieGenre(27, 'Horror'),
  MovieGenre(10402, 'Music'),
  MovieGenre(9648, 'Mystery'),
  MovieGenre(10749, 'Romance'),
  MovieGenre(878, 'Science Fiction'),
  MovieGenre(53, 'Thriller'),
  MovieGenre(10752, 'War'),
  MovieGenre(37, 'Western'),
];

/// User-configurable filters for the Movies browse page. Persisted across
/// sessions. Genre and runtime are applied server-side via TMDB discover;
/// "hide obscure" is applied client-side so it never hides unreleased movies
/// (which legitimately have no votes yet).
class MovieFilters {
  /// Genres to include (OR semantics). Empty means "any genre".
  final Set<int> genreIds;

  /// Genres to exclude: a movie matching any of these is hidden.
  final Set<int> excludedGenreIds;

  /// Minimum runtime in minutes; 0 means no minimum.
  final int minRuntime;

  /// Maximum runtime in minutes; [maxRuntimeCap] means no maximum.
  final int maxRuntime;

  /// Hide already-released movies with very few ratings.
  final bool hideObscure;

  const MovieFilters({
    this.genreIds = const {},
    this.excludedGenreIds = const {},
    this.minRuntime = 0,
    this.maxRuntime = maxRuntimeCap,
    this.hideObscure = false,
  });

  /// Released movies need at least this many votes to pass "hide obscure".
  static const int obscureVoteThreshold = 50;

  /// Top of the runtime slider; treated as "no upper limit".
  static const int maxRuntimeCap = 240;

  bool get hasRuntimeFilter => minRuntime > 0 || maxRuntime < maxRuntimeCap;

  bool get isActive =>
      genreIds.isNotEmpty ||
      excludedGenreIds.isNotEmpty ||
      hasRuntimeFilter ||
      hideObscure;

  /// Number of distinct active filter groups (for the app-bar badge).
  int get activeCount =>
      (genreIds.isNotEmpty ? 1 : 0) +
      (excludedGenreIds.isNotEmpty ? 1 : 0) +
      (hasRuntimeFilter ? 1 : 0) +
      (hideObscure ? 1 : 0);

  MovieFilters copyWith({
    Set<int>? genreIds,
    Set<int>? excludedGenreIds,
    int? minRuntime,
    int? maxRuntime,
    bool? hideObscure,
  }) =>
      MovieFilters(
        genreIds: genreIds ?? this.genreIds,
        excludedGenreIds: excludedGenreIds ?? this.excludedGenreIds,
        minRuntime: minRuntime ?? this.minRuntime,
        maxRuntime: maxRuntime ?? this.maxRuntime,
        hideObscure: hideObscure ?? this.hideObscure,
      );

  Map<String, dynamic> toJson() => {
        'genreIds': genreIds.toList(),
        'excludedGenreIds': excludedGenreIds.toList(),
        'minRuntime': minRuntime,
        'maxRuntime': maxRuntime,
        'hideObscure': hideObscure,
      };

  factory MovieFilters.fromJson(Map<String, dynamic> json) => MovieFilters(
        genreIds: (json['genreIds'] as List<dynamic>? ?? const [])
            .map((e) => e as int)
            .toSet(),
        excludedGenreIds:
            (json['excludedGenreIds'] as List<dynamic>? ?? const [])
                .map((e) => e as int)
                .toSet(),
        minRuntime: json['minRuntime'] as int? ?? 0,
        maxRuntime: json['maxRuntime'] as int? ?? maxRuntimeCap,
        hideObscure: json['hideObscure'] as bool? ?? false,
      );
}
