/// §20.1 Shelf picker — the matching rules (contract 4.104.0, ADR-137).
///
/// Mirrors the reference's `NoteLetter-web/src/shared/shelfPick.js`; the rules
/// are normative in `component-kit.md` §20.1 §Matching, so every client ranks
/// alike. Pure, so they are asserted rather than eyeballed
/// (`test/kit/shelf_picker_test.dart`).
library;

import '../models/tag.dart';

/// Latin-script letters with their diacritics removed. Dart has no NFD, so the
/// fold is a table — the letters a shelf title in this app is written with.
/// A character not in it folds to itself, lower-cased: the rule degrades to
/// "case-insensitive", never to "no match".
const Map<String, String> _plain = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
  'ç': 'c', 'č': 'c', 'ć': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ě': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
  'ñ': 'n', 'ń': 'n', 'ň': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ō': 'o', 'ø': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u',
  'ý': 'y', 'ÿ': 'y', 'š': 's', 'ś': 's', 'ž': 'z', 'ź': 'z', 'ż': 'z',
  'ř': 'r', 'ď': 'd', 'ť': 't', 'ł': 'l', 'ß': 'ss', 'æ': 'ae', 'œ': 'oe',
};

/// A title folded for matching, with `map[i]` the index in the ORIGINAL title
/// of folded character i — one character at a time, so a highlight drawn from
/// a folded match lands on the characters the reader typed against ("ß" folds
/// to two characters that both map to the one they came from).
class Folded {
  final String text;
  final List<int> map;
  const Folded(this.text, this.map);
}

Folded fold(String s) {
  final out = StringBuffer();
  final map = <int>[];
  var at = 0;
  for (final rune in s.runes) {
    final c = String.fromCharCode(rune);
    final lower = c.toLowerCase();
    final f = _plain[lower] ?? lower;
    for (var k = 0; k < f.length; k++) {
      out.write(f[k]);
      map.add(at);
    }
    at += c.length;
  }
  map.add(at);
  return Folded(out.toString(), map);
}

String foldQuery(String q) => fold(q.trim()).text;

/// Where a query matched a title: [rank] 0 — the title starts with it; 1 — a
/// word in it does; 2 — it is anywhere inside. [start]/[end] index the
/// ORIGINAL title; an empty query matches at rank 0 with no run.
class ShelfMatch {
  final int rank;
  final int start;
  final int end;
  const ShelfMatch(this.rank, this.start, this.end);
}

final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

ShelfMatch? matchShelf(String title, String q) {
  final needle = foldQuery(q);
  if (needle.isEmpty) return const ShelfMatch(0, 0, 0);
  final f = fold(title);
  final any = f.text.indexOf(needle);
  if (any == -1) return null;
  // The first occurrence that begins a word is the one to rank and draw.
  var word = -1;
  for (var p = any; p != -1; p = f.text.indexOf(needle, p + 1)) {
    if (p == 0 || !_wordChar.hasMatch(f.text[p - 1])) {
      word = p;
      break;
    }
  }
  final at = word == -1 ? any : word;
  final rank = word == 0 ? 0 : (word > 0 ? 1 : 2);
  return ShelfMatch(rank, f.map[at], f.map[at + needle.length]);
}

class PickRow {
  final Tag shelf;
  final ShelfMatch match;
  const PickRow(this.shelf, this.match);
}

/// The rows the picker lists: the shelves the item does not carry, filtered
/// and ranked. Equal ranks keep the order they arrived in — the tags
/// subscription's, the rail's — so the list never reshuffles among equals.
List<PickRow> pickRows(List<Tag> addable, String q) {
  final rows = <(PickRow, int)>[];
  for (var i = 0; i < addable.length; i++) {
    final m = matchShelf(addable[i].title, q);
    if (m != null) rows.add((PickRow(addable[i], m), i));
  }
  rows.sort((a, b) {
    final r = a.$1.match.rank.compareTo(b.$1.match.rank);
    return r != 0 ? r : a.$2.compareTo(b.$2);
  });
  return [for (final r in rows) r.$1];
}

/// What the create row offers and what an empty list says.
///
/// [createName] is the name *Create "…"* offers, or `''` for *New shelf…*;
/// [empty] is the sentence for an empty list, or null when rows exist. A query
/// that exactly names a shelf (folded) never offers a second one: on the item
/// the list says so; off it, that shelf is the first row already.
class PickState {
  final String createName;
  final String? empty;
  const PickState(this.createName, this.empty);
}

PickState pickState({
  required List<Tag> onItem,
  required List<Tag> addable,
  required String q,
  required List<PickRow> rows,
}) {
  final name = q.trim();
  final needle = foldQuery(name);
  Tag? here;
  if (needle.isNotEmpty) {
    for (final s in onItem) {
      if (foldQuery(s.title) == needle) {
        here = s;
        break;
      }
    }
  }
  final exists = here != null ||
      (needle.isNotEmpty && addable.any((s) => foldQuery(s.title) == needle));
  String? empty;
  if (rows.isEmpty) {
    if (here != null) {
      empty = '“${here.title}” is already here.';
    } else if (needle.isNotEmpty) {
      empty = 'No shelf matches “$name”.';
    } else if (onItem.isNotEmpty) {
      empty = 'Every shelf is already here.';
    } else {
      empty = 'No shelves yet.';
    }
  }
  return PickState(exists ? '' : name, empty);
}
