/// The shelf tree (contract 5.28.0, ADR-185, INV-33) — web's
/// `src/shared/shelfTree.js`, rule for rule, over the same cases
/// (`test/contract/shelf_tree_test.dart`). Pure.
///
/// `parentTagId` is the nesting edge. A stored id is a claim, not an edge: it
/// counts only when it names another shelf in [shelves] — the caller's own
/// live shelves, which is exactly what the tags subscription holds (it asks
/// for `user_id == uid` and drops `deleting`). A shelf on a stored cycle, or
/// whose stored chain runs past [shelfHops], is top-level; one whose chain only
/// REACHES a cycle above it keeps its parent. The backend's
/// `area_tags._ShelfTree` is the same rule; two rules would be two answers to
/// "is this inside that".
library;

import '../models/tag.dart';

const shelfHops = 64;
const shelfPathSep = ' › ';

/// A row of [ShelfTree.ordered]: the shelf, its depth, and its ancestors root
/// first.
class ShelfTreeRow {
  final Tag shelf;
  final int depth;
  final List<Tag> path;
  const ShelfTreeRow(this.shelf, this.depth, this.path);
}

/// The letter mode a shelf reads, and the shelf that set it (null: the
/// default, set by nobody).
class ShelfLetterMode {
  final String mode;
  final Tag? from;
  const ShelfLetterMode(this.mode, this.from);
}

class ShelfTree {
  final Map<String, Tag> byId;
  final Map<String, String?> parent;
  final Map<String, List<Tag>> _children;
  final List<Tag> roots;

  ShelfTree._(this.byId, this.parent, this._children, this.roots);

  factory ShelfTree(List<Tag> shelves) {
    final byId = {for (final s in shelves) s.id: s};
    String? raw(String id) {
      final p = byId[id]?.parentTagId;
      return p != null && p != id && byId.containsKey(p) ? p : null;
    }

    final parent = <String, String?>{};
    for (final s in shelves) {
      var p = raw(s.id);
      var cur = p;
      final seen = {s.id};
      var hops = 1;
      while (cur != null) {
        if (cur == s.id || hops > shelfHops) {
          p = null; // on a cycle, or too deep
          break;
        }
        if (seen.contains(cur)) break; // a cycle above, not through s
        seen.add(cur);
        cur = raw(cur);
        hops += 1;
      }
      parent[s.id] = p;
    }

    // Children keep subscription order — the order the rail always listed.
    final children = <String, List<Tag>>{};
    final roots = <Tag>[];
    for (final s in shelves) {
      final p = parent[s.id];
      if (p == null) {
        roots.add(s);
      } else {
        (children[p] ??= []).add(s);
      }
    }
    return ShelfTree._(byId, parent, children, roots);
  }

  List<Tag> childrenOf(String id) => _children[id] ?? const [];

  /// Nearest first.
  List<Tag> ancestors(String id) {
    final out = <Tag>[];
    for (var cur = parent[id]; cur != null; cur = parent[cur]) {
      out.add(byId[cur]!);
    }
    return out;
  }

  /// The shelf and every shelf below it: what "in this shelf" means.
  Set<String> subtreeIds(String id) {
    final out = <String>{};
    final stack = [id];
    while (stack.isNotEmpty) {
      final t = stack.removeLast();
      if (!out.add(t)) continue;
      for (final c in childrenOf(t)) {
        stack.add(c.id);
      }
    }
    return out;
  }

  /// Depth first, siblings in subscription order: what the rail, the picker
  /// and the select list.
  List<ShelfTreeRow> ordered() {
    final out = <ShelfTreeRow>[];
    void walk(Tag s, List<Tag> path) {
      out.add(ShelfTreeRow(s, path.length, path));
      for (final c in childrenOf(s.id)) {
        walk(c, [...path, s]);
      }
    }

    for (final r in roots) {
      walk(r, const []);
    }
    return out;
  }

  /// The nearest explicit letter mode up the chain, default mixed
  /// (ADR-185 §4).
  ShelfLetterMode letterMode(String id) {
    for (final s in [if (byId[id] != null) byId[id]!, ...ancestors(id)]) {
      final m = s.ownLetterMode;
      if (m != null) return ShelfLetterMode(m, s);
    }
    return const ShelfLetterMode('mixed', null);
  }

  /// Where [id] may move: a shelf whose STORED chain does not pass through it
  /// (the backend refuses those), or the top level (null). The stored chain,
  /// not the resolved one, so a select never offers what a 400 refuses.
  bool canHold(String id, String? parentId) {
    if (parentId == null) return true;
    if (!byId.containsKey(parentId)) return false;
    String? cur = parentId;
    for (var hops = 0; cur != null && hops <= shelfHops; hops += 1) {
      if (cur == id) return false;
      cur = byId[cur]?.parentTagId;
    }
    return true;
  }

  String pathLabel(String id) => ancestors(id)
      .reversed
      .map((s) => s.title.isEmpty ? 'Untitled' : s.title)
      .join(shelfPathSep);
}

/// A document is in shelf S when any of its shelves is S or below it (INV-33).
bool inSubtree(Iterable<String> ids, Set<String> subtree) =>
    ids.any(subtree.contains);
