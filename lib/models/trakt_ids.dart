/// The set of cross-service identifiers Trakt returns for every movie/show.
/// `tmdb` is the bridge we use to enrich items with TMDB metadata.
class TraktIds {
  final int? trakt;
  final String? slug;
  final String? imdb;
  final int? tmdb;
  final int? tvdb;

  const TraktIds({this.trakt, this.slug, this.imdb, this.tmdb, this.tvdb});

  factory TraktIds.fromJson(Map<String, dynamic> json) => TraktIds(
        trakt: json['trakt'] as int?,
        slug: json['slug'] as String?,
        imdb: json['imdb'] as String?,
        tmdb: json['tmdb'] as int?,
        tvdb: json['tvdb'] as int?,
      );

  Map<String, dynamic> toJson() => {
        if (trakt != null) 'trakt': trakt,
        if (slug != null) 'slug': slug,
        if (imdb != null) 'imdb': imdb,
        if (tmdb != null) 'tmdb': tmdb,
        if (tvdb != null) 'tvdb': tvdb,
      };
}
