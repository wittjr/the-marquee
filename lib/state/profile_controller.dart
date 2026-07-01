import 'package:flutter/foundation.dart';

import '../models/trakt_profile.dart';
import '../services/trakt_api.dart';
import 'auth_controller.dart';

enum ProfileState { loading, ready, error }

/// Loads the signed-in user's profile, watch stats and recent history for the
/// Profile page.
class ProfileController extends ChangeNotifier {
  final TraktApi _trakt;

  ProfileController({required AuthController auth, TraktApi? trakt})
      : _trakt = trakt ?? TraktApi(auth);

  ProfileState _state = ProfileState.loading;
  ProfileState get state => _state;

  String? _error;
  String? get error => _error;

  TraktUser? _user;
  TraktUser? get user => _user;

  TraktStats? _stats;
  TraktStats? get stats => _stats;

  List<HistoryItem> _history = const [];
  List<HistoryItem> get history => _history;

  PlexStatus? _plex;
  PlexStatus? get plex => _plex;

  Future<void> load() async {
    _state = ProfileState.loading;
    _error = null;
    notifyListeners();

    try {
      // Profile is required; the rest are best-effort.
      final results = await Future.wait([
        _trakt.userProfile(),
        _trakt.userStats().catchError((_) => const TraktStats()),
        _trakt.history().catchError((_) => <HistoryItem>[]),
        _trakt.plexStatus(),
      ]);
      _user = results[0] as TraktUser;
      _stats = results[1] as TraktStats;
      _history = results[2] as List<HistoryItem>;
      _plex = results[3] as PlexStatus;
      _state = ProfileState.ready;
    } catch (e) {
      _error = e.toString();
      _state = ProfileState.error;
    }
    notifyListeners();
  }
}
