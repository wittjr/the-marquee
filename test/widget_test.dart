import 'package:flutter_test/flutter_test.dart';

import 'package:the_marquee/models/media_item.dart';

void main() {
  test('parses a Trakt show watchlist entry', () {
    final item = MediaItem.fromTraktEntry({
      'type': 'show',
      'listed_at': '2024-01-02T03:04:05.000Z',
      'show': {
        'title': 'Severance',
        'year': 2022,
        'ids': {'trakt': 1, 'slug': 'severance', 'tmdb': 95396},
      },
    });

    expect(item.type, MediaType.show);
    expect(item.title, 'Severance');
    expect(item.ids.tmdb, 95396);
  });

  test('parses a Trakt movie watchlist entry', () {
    final item = MediaItem.fromTraktEntry({
      'type': 'movie',
      'movie': {
        'title': 'Dune',
        'year': 2021,
        'ids': {'trakt': 2, 'tmdb': 438631},
      },
    });

    expect(item.type, MediaType.movie);
    expect(item.title, 'Dune');
    expect(item.ids.tmdb, 438631);
  });
}
