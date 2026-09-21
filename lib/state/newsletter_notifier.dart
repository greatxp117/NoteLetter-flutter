import 'package:flutter/foundation.dart';
import '../models/newsletter.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/firestore_service.dart';
import '../services/error_text.dart';

/// Newsletter history (INV-09: query by recency, never construct IDs) +
/// "send now" via `fn_request_newsletter`. See spec/screens/letters.md.
///
/// **One query, two kinds** (2.24.0, ADR-029 §3). The collection holds both
/// letters and is read once, then split here — `kind != 'scripture'` for the
/// daily list, never `kind == 'daily'`, because the field is absent on every
/// pre-2.24.0 record and equality would drop a real reader's whole history.
class NewsletterNotifier extends ChangeNotifier {
  List<Newsletter> _all = [];
  bool _isLoading = false;
  bool _isSending = false;
  String? _error;
  bool _loaded = false;

  /// The daily letters — everything that is not a readings letter.
  List<Newsletter> get history =>
      List.unmodifiable(_all.where((n) => !n.isScripture));

  /// The readings letters, the other side of the same filter.
  List<Newsletter> get readings =>
      List.unmodifiable(_all.where((n) => n.isScripture));

  /// The most recent daily letter that can actually be opened. `empty`/`error`
  /// rows have no body to preview; they still appear in the list below.
  Newsletter? get latest {
    for (final n in history) {
      if (n.isReadable && n.status != 'empty' && n.status != 'error') return n;
    }
    return null;
  }

  bool get isLoading => _isLoading;
  bool get isSending => _isSending;

  /// INV-24 (ADR-071): a failed read is not an empty archive. Until [loaded] is
  /// true and this is null, a screen may not say "no letters yet".
  String? get error => _error;
  bool get loaded => _loaded;

  Future<void> load({int limit = 30}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _all = await FirestoreService.instance.listAllNewsletters(limit: limit);
      _loaded = true;
    } catch (e) {
      _error = describeSdkError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// "Send now" — 60s cooldown against double-taps is enforced server-side.
  ///
  /// The build is asynchronous and **always** produces a visible record
  /// (2.2.0, ADR-011): `sent`, `error`, or `empty`. The caller reloads the
  /// history to find it; nothing here polls a function (INV-02).
  Future<String?> requestNewsletter() async {
    _isSending = true;
    notifyListeners();
    try {
      await Api.instance.requestNewsletter();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Failed to request newsletter. Please try again.';
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }
}
