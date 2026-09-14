import 'package:flutter/foundation.dart';
import '../models/cohesive_reading.dart';
import '../models/scripture_lookup.dart';
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

  // ── Verse search (2.28.0 + 4.9.0, ADR-027 §2 / ADR-045) ───────────────────
  //
  // A citation is a DIFFERENT QUESTION, so it takes a different path. The
  // client parse is the cheap prefilter that decides which; the server parses
  // again and its answer is what the results describe.
  //
  // Its own loading, error and request id, for the reason the cohesive pair
  // has its own: a lookup that failed is not a search that failed, and the
  // screen names the reference it could not read rather than saying search is
  // unavailable.

  ScriptureLookup? _scripture;
  bool _scriptureLoading = false;
  String? _scriptureError;
  String? _scriptureRequestId;

  /// The query the SERVER said was not a citation. Recording which one is what
  /// releases the fall-through: without it the screen keeps taking the
  /// citation branch for a query it has never actually searched for, and
  /// renders "no passages" for a search it never made.
  String? _notCitation;

  ScriptureLookup? get scripture => _scripture;
  bool get scriptureLoading => _scriptureLoading;
  String? get scriptureError => _scriptureError;
  String? get scriptureRequestId => _scriptureRequestId;

  /// Has the server already told us [query] is not a citation?
  bool rejectedAsCitation(String query) => _notCitation == query.trim();

  /// Look the citation up. Resolves to `true` when the screen should **stay on
  /// the citation branch** — the server read it as a citation, or the lookup
  /// failed and the reader is owed the reference it could not read.
  ///
  /// `false` is `parsed: false`: it was an ordinary query after all, which is a
  /// **normal answer**, and the caller falls through to the vector search
  /// rather than showing anything at all.
  Future<bool> lookupScripture(String reference) async {
    final trimmed = reference.trim();
    if (trimmed.isEmpty) return false;

    _scriptureLoading = true;
    _scriptureError = null;
    _scriptureRequestId = null;
    notifyListeners();

    try {
      final data = await Api.instance.scriptureLookup(trimmed);
      final parsed = ScriptureLookup.fromJson(data);
      if (parsed.parsed) {
        _scripture = parsed;
        return true;
      }
      _scripture = null;
      _notCitation = trimmed;
      return false;
    } on UnauthorizedException {
      await AuthService.instance.signOut();
      return false;
    } on ApiException catch (e) {
      // A FAILED lookup is not `parsed: false`. One is the server unable to
      // read the reference; the other is the server saying it was ordinary
      // text. Falling through on a failure would hide an outage behind a
      // search that happens to return something.
      _scripture = null;
      _scriptureError = e.message;
      _scriptureRequestId = e.requestId;
      return true;
    } catch (_) {
      _scripture = null;
      _scriptureError = 'The citation could not be looked up.';
      return true;
    } finally {
      _scriptureLoading = false;
      notifyListeners();
    }
  }

  void clearScripture() {
    _scripture = null;
    _scriptureError = null;
    _scriptureRequestId = null;
    _scriptureLoading = false;
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
    _scripture = null;
    _scriptureError = null;
    _scriptureRequestId = null;
    _scriptureLoading = false;
    _notCitation = null;
    notifyListeners();
  }
}
