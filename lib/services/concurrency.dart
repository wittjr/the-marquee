/// Maps [items] with [task], running at most [concurrency] tasks at a time and
/// preserving input order in the result. Use instead of `Future.wait(map(...))`
/// when the task hits a rate-limited API, so requests don't all fire at once.
Future<List<R>> pooledMap<T, R>(
  Iterable<T> items,
  Future<R> Function(T item) task, {
  int concurrency = 5,
}) async {
  final list = items.toList();
  final results = List<R?>.filled(list.length, null);
  var next = 0;

  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= list.length) break;
      results[i] = await task(list[i]);
    }
  }

  final workerCount = list.length < concurrency ? list.length : concurrency;
  await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
  return results.cast<R>();
}

/// Like [pooledMap] but for tasks whose result is discarded (e.g. in-place
/// enrichment). Runs at most [concurrency] tasks at a time.
Future<void> pooledForEach<T>(
  Iterable<T> items,
  Future<void> Function(T item) task, {
  int concurrency = 5,
}) async {
  final list = items.toList();
  var next = 0;

  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= list.length) break;
      await task(list[i]);
    }
  }

  final workerCount = list.length < concurrency ? list.length : concurrency;
  await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
}
