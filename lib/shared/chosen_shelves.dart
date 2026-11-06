/// Kit §20.3's choice (contract 5.73.0, ADR-238, INV-38) — web's
/// `useChosenShelves` (`shared/AddShelves.jsx`), the one rule that tells a shelf
/// that has gone from a shelf that is on its way. Pure, so it is asserted
/// (`test/kit/chosen_shelves_test.dart`).
library;

import 'package:flutter/foundation.dart';

import '../models/tag.dart';

/// What a host's next add should carry. [ids] leaves out a shelf deleted since it
/// was chosen: its chip draws nothing (§20), so a reader refused over it could
/// not take it off. It keeps one the tags read has never shown, because that is
/// a shelf just made from the row's create form, on its way here.
///
/// A choice is never without its chip: a shelf made here draws from what its form
/// knew ([addMade]) until the read delivers it, which on a subscription that
/// failed would be never. Once delivered it is a shelf like any other.
class ChosenShelves extends ChangeNotifier {
  final List<String> _picked = [];
  final Set<String> _seen = {};
  final Map<String, Tag> _made = {};
  Map<String, Tag> _byId = const {};

  /// What the tags read says now. The row calls it as it builds, so it does not
  /// notify.
  void read(Iterable<Tag> shelves) {
    _byId = {for (final s in shelves) s.id: s};
    _seen.addAll(_byId.keys);
  }

  /// A copy, taken when it is asked for: an add holds the row as it stood when
  /// pressed, whatever a chip does afterwards.
  List<String> get ids => List.unmodifiable([
        for (final id in _picked)
          if (_byId.containsKey(id) || !_seen.contains(id)) id,
      ]);

  /// The shelves that draw a chip: what the read says, or what the form knew for
  /// a shelf the read has not delivered yet.
  List<Tag> get chips => [
        for (final id in _picked)
          if ((_byId[id] ?? (_seen.contains(id) ? null : _made[id])) case final s?)
            s,
      ];

  void add(String id) {
    if (_picked.contains(id)) return;
    _picked.add(id);
    notifyListeners();
  }

  /// A shelf just made from the row's create form: chosen, with its chip.
  void addMade(Tag shelf) {
    _made[shelf.id] = shelf;
    if (!_picked.contains(shelf.id)) _picked.add(shelf.id);
    notifyListeners();
  }

  void remove(String id) {
    if (_picked.remove(id)) notifyListeners();
  }

  void clear() {
    if (_picked.isEmpty) return;
    _picked.clear();
    notifyListeners();
  }
}
