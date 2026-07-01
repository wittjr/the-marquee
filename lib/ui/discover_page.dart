import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import '../state/browse_controller.dart';
import '../state/show_discover_controller.dart';
import 'movies_browse_page.dart';
import 'show_discover_page.dart';
import 'widgets/account_bar.dart';
import 'widgets/library_segment.dart';

/// The Discover tab: find new movies and shows to add to the watchlist. A
/// Movies / TV segmented control swaps between the movie browse/search body and
/// the TV search + Trending/Coming Soon body. Both controllers are provided
/// here so the shared app bar (e.g. the movie filter action) can reach them.
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  var _segment = LibrarySegment.movies;
  // The TV discovery rows are loaded lazily the first time that segment shows,
  // so opening Discover doesn't fire the TV requests unless the user asks.
  bool _tvLoaded = false;

  /// [context] must be below the [MultiProvider] (i.e. the Builder's context) so
  /// the TV controller can be read.
  void _select(BuildContext context, LibrarySegment segment) {
    setState(() => _segment = segment);
    if (segment == LibrarySegment.tv && !_tvLoaded) {
      _tvLoaded = true;
      Future.microtask(context.read<ShowDiscoverController>().load);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BrowseController(auth: auth)..init()),
        ChangeNotifierProvider(create: (_) => ShowDiscoverController(auth: auth)),
      ],
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Discover',
                style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              if (_segment == LibrarySegment.movies) const _MovieFilterAction(),
              const AccountBarActions(),
            ],
            bottom: LibrarySegmentBar(
              selected: _segment,
              onChanged: (s) => _select(context, s),
            ),
          ),
          body: IndexedStack(
            index: _segment.index,
            children: const [
              MovieDiscoverBody(),
              ShowDiscoverBody(),
            ],
          ),
        );
      }),
    );
  }
}

/// The filter action for the movie Discover segment, showing a badge with the
/// active filter count.
class _MovieFilterAction extends StatelessWidget {
  const _MovieFilterAction();

  @override
  Widget build(BuildContext context) {
    final browse = context.watch<BrowseController>();
    final activeCount = browse.filters.activeCount;
    return IconButton(
      tooltip: 'Filters',
      onPressed: () => openMovieFilters(context, browse),
      icon: activeCount > 0
          ? Badge.count(count: activeCount, child: const Icon(Icons.filter_list))
          : const Icon(Icons.filter_list),
    );
  }
}
