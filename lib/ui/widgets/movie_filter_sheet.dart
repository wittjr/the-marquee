import 'package:flutter/material.dart';

import '../../models/movie_filters.dart';

/// Shows the Movies filter bottom sheet. Returns the new filters if the user
/// applied changes, or null if they dismissed without applying.
Future<MovieFilters?> showMovieFilterSheet(
  BuildContext context,
  MovieFilters current,
) {
  return showModalBottomSheet<MovieFilters>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FilterSheet(initial: current),
  );
}

class _FilterSheet extends StatefulWidget {
  final MovieFilters initial;
  const _FilterSheet({required this.initial});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<int> _genreIds;
  late Set<int> _excludedGenreIds;
  late RangeValues _runtime;
  late bool _hideObscure;

  @override
  void initState() {
    super.initState();
    _genreIds = {...widget.initial.genreIds};
    _excludedGenreIds = {...widget.initial.excludedGenreIds};
    _runtime = RangeValues(
      widget.initial.minRuntime.toDouble(),
      widget.initial.maxRuntime.toDouble(),
    );
    _hideObscure = widget.initial.hideObscure;
  }

  void _reset() {
    setState(() {
      _genreIds = {};
      _excludedGenreIds = {};
      _runtime = RangeValues(0, MovieFilters.maxRuntimeCap.toDouble());
      _hideObscure = false;
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      MovieFilters(
        genreIds: _genreIds,
        excludedGenreIds: _excludedGenreIds,
        minRuntime: _runtime.start.round(),
        maxRuntime: _runtime.end.round(),
        hideObscure: _hideObscure,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Filters',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(onPressed: _reset, child: const Text('Reset')),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Include genres',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final genre in kMovieGenres)
                  FilterChip(
                    label: Text(genre.name),
                    selected: _genreIds.contains(genre.id),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _genreIds.add(genre.id);
                        _excludedGenreIds.remove(genre.id);
                      } else {
                        _genreIds.remove(genre.id);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Exclude genres',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Hides any movie matching a selected genre',
                style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final genre in kMovieGenres)
                  FilterChip(
                    label: Text(genre.name),
                    selectedColor: const Color(0xFF8E2A2A),
                    checkmarkColor: Colors.white,
                    selected: _excludedGenreIds.contains(genre.id),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _excludedGenreIds.add(genre.id);
                        _genreIds.remove(genre.id);
                      } else {
                        _excludedGenreIds.remove(genre.id);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text('Runtime',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(_runtimeLabel, style: const TextStyle(color: Colors.white70)),
              ],
            ),
            RangeSlider(
              values: _runtime,
              min: 0,
              max: MovieFilters.maxRuntimeCap.toDouble(),
              divisions: MovieFilters.maxRuntimeCap ~/ 10,
              labels: RangeLabels(
                '${_runtime.start.round()}m',
                _runtime.end.round() >= MovieFilters.maxRuntimeCap
                    ? '${MovieFilters.maxRuntimeCap}m+'
                    : '${_runtime.end.round()}m',
              ),
              onChanged: (v) => setState(() => _runtime = v),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hide obscure releases'),
              subtitle: const Text(
                  'Hides released movies with very few ratings'),
              value: _hideObscure,
              onChanged: (v) => setState(() => _hideObscure = v),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _apply,
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _runtimeLabel {
    final min = _runtime.start.round();
    final max = _runtime.end.round();
    final noMin = min == 0;
    final noMax = max >= MovieFilters.maxRuntimeCap;
    if (noMin && noMax) return 'Any';
    if (noMin) return 'Up to ${max}m';
    if (noMax) return '${min}m+';
    return '${min}m – ${max}m';
  }
}
