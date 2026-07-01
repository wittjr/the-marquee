import 'package:flutter/material.dart';

/// Which media library a segmented tab (Discover / Watchlist) is showing.
enum LibrarySegment { movies, tv }

/// The Movies / TV segmented control shown under the app bar of the Discover and
/// Watchlist tabs. Sized to sit in an [AppBar.bottom] slot.
class LibrarySegmentBar extends StatelessWidget implements PreferredSizeWidget {
  final LibrarySegment selected;
  final ValueChanged<LibrarySegment> onChanged;

  const LibrarySegmentBar({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: SegmentedButton<LibrarySegment>(
        segments: const [
          ButtonSegment(
            value: LibrarySegment.movies,
            label: Text('Movies'),
            icon: Icon(Icons.movie_outlined),
          ),
          ButtonSegment(
            value: LibrarySegment.tv,
            label: Text('TV'),
            icon: Icon(Icons.live_tv_outlined),
          ),
        ],
        selected: {selected},
        showSelectedIcon: false,
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}
