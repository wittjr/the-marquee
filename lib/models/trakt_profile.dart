/// The signed-in Trakt user's profile, from `/users/settings`.
class TraktUser {
  final String username;
  final String? name;
  final bool vip;
  final String? location;
  final String? about;
  final DateTime? joinedAt;
  final String? avatarUrl;

  const TraktUser({
    required this.username,
    this.name,
    this.vip = false,
    this.location,
    this.about,
    this.joinedAt,
    this.avatarUrl,
  });

  String get displayName => (name?.isNotEmpty == true) ? name! : username;

  factory TraktUser.fromSettings(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? const {};
    final images = user['images'] as Map<String, dynamic>?;
    final avatar = images?['avatar'] as Map<String, dynamic>?;
    return TraktUser(
      username: user['username'] as String? ?? 'unknown',
      name: user['name'] as String?,
      vip: user['vip'] as bool? ?? false,
      location: user['location'] as String?,
      about: user['about'] as String?,
      joinedAt: DateTime.tryParse(user['joined_at'] as String? ?? ''),
      avatarUrl: avatar?['full'] as String?,
    );
  }
}

/// Aggregate watch stats from `/users/me/stats`.
class TraktStats {
  final int moviesWatched;
  final int moviesMinutes;
  final int showsWatched;
  final int episodesWatched;
  final int episodesMinutes;

  const TraktStats({
    this.moviesWatched = 0,
    this.moviesMinutes = 0,
    this.showsWatched = 0,
    this.episodesWatched = 0,
    this.episodesMinutes = 0,
  });

  int get totalMinutes => moviesMinutes + episodesMinutes;

  factory TraktStats.fromJson(Map<String, dynamic> json) {
    final movies = json['movies'] as Map<String, dynamic>?;
    final shows = json['shows'] as Map<String, dynamic>?;
    final episodes = json['episodes'] as Map<String, dynamic>?;
    return TraktStats(
      moviesWatched: movies?['watched'] as int? ?? 0,
      moviesMinutes: movies?['minutes'] as int? ?? 0,
      showsWatched: shows?['watched'] as int? ?? 0,
      episodesWatched: episodes?['watched'] as int? ?? 0,
      episodesMinutes: episodes?['minutes'] as int? ?? 0,
    );
  }
}

/// The user's Plex connection status, from `/users/settings/plex`.
class PlexStatus {
  final bool connected;
  final String? username;
  final DateTime? connectedAt;

  const PlexStatus({
    this.connected = false,
    this.username,
    this.connectedAt,
  });
}

enum HistoryType { movie, episode }

/// A single watched entry from `/sync/history`.
class HistoryItem {
  final HistoryType type;
  final String title;
  final String? subtitle;
  final DateTime? watchedAt;

  const HistoryItem({
    required this.type,
    required this.title,
    this.subtitle,
    this.watchedAt,
  });

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    final watchedAt = DateTime.tryParse(json['watched_at'] as String? ?? '');

    if (json['type'] == 'episode') {
      final show = json['show'] as Map<String, dynamic>? ?? const {};
      final ep = json['episode'] as Map<String, dynamic>? ?? const {};
      final season = ep['season'];
      final number = ep['number'];
      final epTitle = ep['title'] as String?;
      final code = 'S${_pad(season)}E${_pad(number)}';
      return HistoryItem(
        type: HistoryType.episode,
        title: show['title'] as String? ?? 'Unknown show',
        subtitle: epTitle != null ? '$code · $epTitle' : code,
        watchedAt: watchedAt,
      );
    }

    final movie = json['movie'] as Map<String, dynamic>? ?? const {};
    final year = movie['year'];
    return HistoryItem(
      type: HistoryType.movie,
      title: movie['title'] as String? ?? 'Unknown movie',
      subtitle: year?.toString(),
      watchedAt: watchedAt,
    );
  }

  static String _pad(Object? value) =>
      (value is int ? value : 0).toString().padLeft(2, '0');
}
