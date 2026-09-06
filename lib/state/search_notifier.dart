import 'package:flutter/foundation.dart';
import '../models/cohesive_reading.dart';
import '../models/search_result.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class SearchNotifier extends ChangeNotifier {
  List<SearchResult> _results = [];
  bool _isLoading = false;
  String? _error;
  /// The envelope's `request_id`, kept so the Failure block can render it
  /// (component-kit §14.1, ADR-070). `ApiException` has parsed it since it was
  /// written and nothing had ever read it.
  String? _requestId;
  String _query = '';

  List<SearchResult> get results => List.unmodifiable(_results);
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get requestId => _requestId;
  String get query => _query;
  bool get hasResults => _results.isNotEmpty;

  Future<void> search(
    String query, {
    List<String>? sourceTypes,
    int limit = 10,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clear();
      return;
    }

    _query = trimmed;
    _isLoading = true;
    _error = null;
    _requestId = null;
    notifyListeners();

    try {
      final data = await Api.instance
          .searchNotes(trimmed, sourceTypes: sourceTypes, limit: limit);

      final rawList = data['results'] as List? ?? [];
      _results = rawList
          .map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
          .toList();
      _error = null;
    } on UnauthorizedException {
      await AuthService.instance.signOut();
    } on ApiException catch (e) {
      _error = e.message;
      _requestId = e.requestId;
    } catch (_) {
      _error = 'Search failed. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Cohesive mode (4.40.0, ADR-078) ────────────────────────────────────────
  //
  // A second request over the same query, with its OWN loading, error and
  // request id. Not a variant of the fields above: the two modes are on screen
  // at the same moment — switching to Cohesive moves the control at once and
  // leaves the passages list standing until the reading lands (the
  // write-before-move rule applied to the frame, `screens/search.md` §States) —
  // so a shared error field would paint a cohesive failure over a healthy list,
  // and a shared loading flag would blank one for the other's request.

  CohesiveReading? _reading;
  bool _cohesiveLoading = false;
  String? _cohesiveError;
  String? _cohesiveRequestId;

  CohesiveReading? get reading => _reading;
  bool get cohesiveLoading => _cohesiveLoading;
  String? get cohesiveError => _cohesiveError;
  String? get cohesiveRequestId => _cohesiveRequestId;

  /// Ask for the reading. [breadth] is `tight | normal | broad`.
  ///
  /// `sourceTypes` is sent to the SERVER here even though the passages mode
  /// filters its list on the client: the arrangement is built server-side, so a
  /// chip that narrowed only what we already hold would narrow nothing at all —
  /// a control that looks like it filters and does not.
  Future<void> synthesize(
    String query, {
    List<String>? sourceTypes,
    String breadth = 'normal',
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clearCohesive();
      return;
    }

    _cohesiveLoading = true;
    _cohesiveError = null;
    _cohesiveRequestId = null;
    notifyListeners();

    try {
      final data = await Api.instance.synthesizeSearch(trimmed,
          sourceTypes: sourceTypes, breadth: breadth);
      _reading = CohesiveReading.fromJson(data);
      _cohesiveError = null;
    } on UnauthorizedException {
      await AuthService.instance.signOut();
    } on ApiException catch (e) {
      // The reading is dropped, not kept beside its own failure: a stale
      // arrangement under a failure block reads as the answer to the query the
      // reader just changed.
      _reading = null;
      _cohesiveError = e.message;
      _cohesiveRequestId = e.requestId;
    } catch (_) {
      _reading = null;
      _cohesiveError = 'The cohesive reading could not be built.';
    } finally {
      _cohesiveLoading = false;
      notifyListeners();
    }
  }

  void clearCohesive() {
    _reading = null;
    _cohesiveError = null;
    _cohesiveRequestId = null;
    _cohesiveLoading = false;
    notifyListeners();
  }

  void clear() {
    _results = [];
    _query = '';
    _error = null;
    _requestId = null;
    _isLoading = false;
    _reading = null;
    _cohesiveError = null;
    _cohesiveRequestId = null;
    _cohesiveLoading = false;
    notifyListeners();
  }
}
