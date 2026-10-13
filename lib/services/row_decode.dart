import 'package:flutter/foundation.dart';

/// Decodes a query's rows one at a time, so **one row that cannot be read
/// costs that row, never the list**.
///
/// Every list read here was `snap.docs.map(X.fromJson).toList()`, and a model's
/// `as bool?` / `as String?` throws on a value of another type. Inside a
/// stream's `map` that throw is the stream's error, so one malformed document
/// drew the whole screen's §14 failure: a readings letter whose `lead` was not
/// a bool failed the entire letters list (TODO 2026-10-13). The web reference
/// cannot fail this way — `api.js` hands the row through as data and a field
/// of the wrong type is read for what it is worth — so the row stays there.
///
/// Here a row whose decode throws is **dropped and logged** (collection, id,
/// the error), and every other row is returned in order. A read that fails as
/// a whole (refused, offline, a missing index) is not a row and still fails
/// as a whole: this sits inside the snapshot, after the query answered.
///
/// [onDropped] is for tests; production logs through [debugPrint].
List<T> decodeRows<D, T>(
  String collection,
  Iterable<D> rows,
  String Function(D row) idOf,
  T Function(D row) decode, {
  void Function(String collection, String id, Object error)? onDropped,
}) {
  final out = <T>[];
  for (final row in rows) {
    try {
      out.add(decode(row));
    } catch (e) {
      final id = idOf(row);
      (onDropped ?? _logDropped)(collection, id, e);
    }
  }
  return out;
}

void _logDropped(String collection, String id, Object error) =>
    debugPrint('firestore: dropped $collection/$id — it could not be read '
        '($error); the rest of the list stands.');
