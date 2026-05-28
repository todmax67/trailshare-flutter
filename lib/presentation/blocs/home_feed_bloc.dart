import 'package:flutter/foundation.dart';

import '../../core/services/home_feed_aggregator.dart';
import '../../data/models/home_feed_data.dart';

enum HomeFeedStatus { idle, loading, ready, error }

/// Stato della Home Feed (ChangeNotifier, allineato al pattern del
/// codebase). Wrappa [HomeFeedAggregator] e mantiene l'ultimo
/// [HomeFeedData] caricato.
class HomeFeedBloc extends ChangeNotifier {
  HomeFeedBloc({HomeFeedAggregator? aggregator})
      : _aggregator = aggregator ?? HomeFeedAggregator();

  final HomeFeedAggregator _aggregator;

  HomeFeedStatus _status = HomeFeedStatus.idle;
  HomeFeedData? _data;
  String? _error;

  HomeFeedStatus get status => _status;
  HomeFeedData? get data => _data;
  String? get error => _error;

  /// True al primissimo load (skeleton full-page). Un refresh
  /// successivo mantiene i dati vecchi a schermo mentre carica.
  bool get isInitialLoading =>
      _status == HomeFeedStatus.loading && _data == null;

  Future<void> load() async {
    if (_status == HomeFeedStatus.loading) return;
    _status = HomeFeedStatus.loading;
    _error = null;
    notifyListeners();
    await _run();
  }

  /// Pull-to-refresh: ricarica tutto senza azzerare [_data] (anti-flash).
  Future<void> refresh() async {
    _status = HomeFeedStatus.loading;
    notifyListeners();
    await _run();
  }

  Future<void> _run() async {
    try {
      _data = await _aggregator.load();
      _status = HomeFeedStatus.ready;
    } catch (e) {
      _error = e.toString();
      _status = HomeFeedStatus.error;
    }
    notifyListeners();
  }
}
