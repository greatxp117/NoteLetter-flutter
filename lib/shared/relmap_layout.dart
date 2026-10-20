/// The shelf map's graph and layout (component-kit §24, 5.25.0, ADR-177) —
/// pure, so the node and edge rules and the normative layout are asserted
/// rather than eyeballed (`test/widgets/relmap_layout_test.dart`, web's
/// `tests/contract/shelf-map.test.js` case for case).
///
/// Ported from the WEB reference, `pages/map/relmapGraph.js` and
/// `pages/map/relmapLayout.js`, line for line; 10MB's `map_source.dart` is
/// where this started, not what it matches. Two things differ from a naive
/// port, both so the two clients place one library alike:
///   · JS's `Array.prototype.sort` is stable and Dart's `List.sort` is not, so
///     the barycenter sweeps break ties on the column index, explicitly;
///   · a JS object keeps its string keys in insertion order, and so does a
///     Dart literal map — the columns are seeded from that order on both.
///
/// A wire is drawn centre to centre, beneath the chips (web's geometry): no
/// chip width enters it. 10MB assumed a fixed 172 and drew its ends at a
/// chip edge that was not there (ADR-177 §Rationale).
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'shelf_pick.dart' show fold, foldQuery;

String nodeKey(String kind, String id) => '$kind:$id';

/// The documents subscription's window (`FirestoreService.subscribeDocuments`
/// limit 200, web App.jsx's `subscribeDocuments(200, …)`). Every figure the
/// map shows is counted inside it, and a full window says so.
const int documentWindow = 200;

/// A shelf as the map reads it — the tags subscription's fields it needs.
class MapShelf {
  final String id;
  final String? title;
  final String? color;
  final String? parentTagId;

  const MapShelf(this.id, {this.title, this.color, this.parentTagId});
}

/// A document as the map reads it — the documents subscription's fields.
class MapDoc {
  final String id;
  final String? title;
  final String? type;
  final bool complete;
  final List<String> tagIds;

  const MapDoc(
    this.id, {
    this.title,
    this.type,
    this.complete = true,
    this.tagIds = const [],
  });
}

class MapNode {
  final String key;

  /// `volume` · `shelf`.
  final String kind;
  final String id;
  final String label;

  /// A volume's document `type`, for its §6.4 plate.
  final String? type;

  /// A shelf's colour token.
  final String? color;

  /// A shelf's figure: every volume beneath it, each once.
  int count;

  MapNode({
    required this.key,
    required this.kind,
    required this.id,
    required this.label,
    this.type,
    this.color,
    this.count = 0,
  });

  bool get isShelf => kind == 'shelf';
}

class MapEdge {
  final String child;
  final String parent;

  /// `volume-shelf` · `shelf-parent`.
  final String type;

  const MapEdge(this.child, this.parent, this.type);
}

class MapCounts {
  final int shelves;
  final int volumes;
  final int links;
  final int unshelved;

  const MapCounts({
    required this.shelves,
    required this.volumes,
    required this.links,
    required this.unshelved,
  });

  @override
  bool operator ==(Object other) =>
      other is MapCounts &&
      other.shelves == shelves &&
      other.volumes == volumes &&
      other.links == links &&
      other.unshelved == unshelved;

  @override
  int get hashCode => Object.hash(shelves, volumes, links, unshelved);

  @override
  String toString() =>
      'MapCounts(shelves: $shelves, volumes: $volumes, links: $links, unshelved: $unshelved)';
}

class MapGraph {
  /// Insertion order is the layout's seed: volumes, then shelves.
  final Map<String, MapNode> nodes;
  final List<MapEdge> edges;

  /// child key → parent keys.
  final Map<String, List<String>> up;

  /// parent key → child keys.
  final Map<String, List<String>> down;
  late final MapCounts counts;
  late final bool windowFull;

  MapGraph._(this.nodes, this.edges, this.up, this.down);
}

/// shelves   — the tags subscription, in its order (it already omits a shelf
///             whose `status` is "deleting", ADR-136).
/// documents — the documents subscription, `created_at desc`.
/// parentOf  — shelf → its parent shelf's id, or null. Nothing at 5.25.0:
///             `parent_tag_id` is still provenance (ADR-025 §3) and draws
///             nothing until shelves nest.
MapGraph buildShelfGraph(
  List<MapShelf> shelves,
  List<MapDoc> documents, {
  String? Function(MapShelf)? parentOf,
}) {
  final shelfById = <String, MapShelf>{};
  for (final s in shelves) {
    if (s.id.isNotEmpty) shelfById[s.id] = s;
  }

  final nodes = <String, MapNode>{};
  final edges = <MapEdge>[];
  final up = <String, List<String>>{};
  final down = <String, List<String>>{};
  void link(String child, String parent, String type) {
    edges.add(MapEdge(child, parent, type));
    (up[child] ??= []).add(parent);
    (down[parent] ??= []).add(child);
  }

  // Volumes first, then shelves: the layout seeds each column in this order,
  // which is subscription order on both sides (ADR-177 §3).
  var unshelved = 0;
  var volumes = 0;
  for (final d in documents) {
    if (!d.complete) continue;
    final on = d.tagIds.toSet().where(shelfById.containsKey);
    if (on.isEmpty) {
      unshelved += 1;
      continue;
    }
    final key = nodeKey('volume', d.id);
    nodes.putIfAbsent(
      key,
      () => MapNode(
        key: key,
        kind: 'volume',
        id: d.id,
        label: _orElse(d.title, 'Untitled'),
        type: d.type,
      ),
    );
    volumes += 1;
  }
  for (final s in shelfById.values) {
    final key = nodeKey('shelf', s.id);
    nodes[key] = MapNode(
      key: key,
      kind: 'shelf',
      id: s.id,
      label: _orElse(s.title, 'Untitled shelf'),
      color: s.color,
    );
  }

  for (final d in documents) {
    final key = nodeKey('volume', d.id);
    if (!nodes.containsKey(key)) continue;
    for (final id in d.tagIds.toSet()) {
      if (shelfById.containsKey(id)) {
        link(key, nodeKey('shelf', id), 'volume-shelf');
      }
    }
  }
  if (parentOf != null) {
    for (final s in shelfById.values) {
      final p = parentOf(s);
      if (p != null && p.isNotEmpty && p != s.id && shelfById.containsKey(p)) {
        link(nodeKey('shelf', s.id), nodeKey('shelf', p), 'shelf-parent');
      }
    }
  }

  final graph = MapGraph._(nodes, edges, up, down);
  // A shelf's figure is every volume beneath it, each counted once — the same
  // number at 5.25.0 as its direct volumes, and the rolled-up one when shelves
  // nest, without a second rule.
  for (final n in nodes.values) {
    if (!n.isShelf) continue;
    n.count = _walk(
      down,
      n.key,
    ).where((k) => nodes[k]!.kind == 'volume').length;
  }
  graph.counts = MapCounts(
    shelves: shelfById.length,
    volumes: volumes,
    links: edges.length,
    unshelved: unshelved,
  );
  graph.windowFull = documents.length >= documentWindow;
  return graph;
}

// `d.title || 'Untitled'` — an empty title takes the fallback too.
String _orElse(String? s, String fallback) =>
    (s == null || s.isEmpty) ? fallback : s;

Set<String> _walk(Map<String, List<String>> adj, String key) {
  final seen = <String>{};
  final stack = <String>[key];
  while (stack.isNotEmpty) {
    final k = stack.removeLast();
    for (final n in adj[k] ?? const <String>[]) {
      if (seen.add(n)) stack.add(n);
    }
  }
  seen.remove(key);
  return seen;
}

class MapPath {
  final Set<String> nodes;

  /// Edge indexes.
  final Set<int> edges;

  const MapPath(this.nodes, this.edges);
  static const empty = MapPath(<String>{}, <int>{});
}

/// Ancestors ∪ the node ∪ descendants, and the edges among them (by index).
MapPath connectedPath(MapGraph graph, String? key) {
  if (key == null || !graph.nodes.containsKey(key)) return MapPath.empty;
  final set = <String>{key, ..._walk(graph.up, key), ..._walk(graph.down, key)};
  final eset = <int>{};
  for (var i = 0; i < graph.edges.length; i++) {
    final e = graph.edges[i];
    if (set.contains(e.child) && set.contains(e.parent)) eset.add(i);
  }
  return MapPath(set, eset);
}

class MapSection {
  final String label;
  final List<MapNode> nodes;

  const MapSection(this.label, this.nodes);
}

class MapRelations {
  final MapNode node;
  final List<MapSection> sections;

  const MapRelations(this.node, this.sections);
}

/// What the inspector names, read the way the arrows read (kit §24).
MapRelations? relationsOf(MapGraph graph, String? key) {
  final node = key == null ? null : graph.nodes[key];
  if (node == null) return null;
  List<MapNode> nodesOf(List<String>? keys) => [
    for (final k in keys ?? const <String>[])
      if (graph.nodes[k] != null) graph.nodes[k]!,
  ];
  if (node.kind == 'volume') {
    return MapRelations(node, [
      MapSection('On shelves', nodesOf(graph.up[key])),
    ]);
  }
  final below = nodesOf(graph.down[key]);
  final sections = <MapSection>[];
  // Nesting's two sections appear only once nesting exists; a flat map has
  // nothing to put in either, and "Inside · 0" on every shelf would describe a
  // relation the library cannot have yet.
  if (graph.edges.any((e) => e.type == 'shelf-parent')) {
    sections.add(MapSection('Inside', nodesOf(graph.up[key])));
    sections.add(
      MapSection('Sub-shelves', below.where((n) => n.isShelf).toList()),
    );
  }
  sections.add(
    MapSection('Volumes', below.where((n) => n.kind == 'volume').toList()),
  );
  return MapRelations(node, sections);
}

/// Keys whose label contains the folded query (§20.1 rule 1), in node order.
Set<String> searchMatches(MapGraph graph, String query) {
  final q = foldQuery(query);
  final out = <String>{};
  if (q.isEmpty) return out;
  for (final n in graph.nodes.values) {
    if (fold(n.label).text.contains(q)) out.add(n.key);
  }
  return out;
}

// ----- Layout (ADR-177 §3) --------------------------------------------------
//
// Ported from 10MB's `layerGraph` (the mind-map variant) by way of web's
// `relmapLayout.js`. A layered DAG that reads child → parent, left to right,
// like its arrows:
//   · volumes always sit in column 0;
//   · a shelf sits at `maxDepth − rank`, where rank is its LONGEST chain of
//     parent shelves — every top-level shelf is in the rightmost column and a
//     shelf nested deeper sits further left, nearer what it holds;
//   · within a column, six barycenter sweeps reduce crossings;
//   · a column taller than three fields wraps round-robin into several, every
//     other one half a row lower, and the canvas grows rather than packs.

const double rowStep = 72;
const double colStep = 260;
const double colStepMax = 330;
const double sideRoom = 86;
const double pad = 30;
const double _top = pad + 30;
const int _colFields = 3;
const double _halfRow = rowStep / 2;
const int _sweeps = 6;

class MapHeader {
  final double x;
  final String label;

  const MapHeader(this.x, this.label);

  @override
  bool operator ==(Object other) =>
      other is MapHeader && other.x == x && other.label == label;

  @override
  int get hashCode => Object.hash(x, label);
}

class MapLayout {
  /// A node's CENTRE.
  final Map<String, Offset> pos;
  final List<MapHeader> headers;
  final double width;
  final double height;
  final int columns;

  const MapLayout({
    required this.pos,
    required this.headers,
    required this.width,
    required this.height,
    required this.columns,
  });

  @override
  bool operator ==(Object other) {
    if (other is! MapLayout) return false;
    if (other.width != width ||
        other.height != height ||
        other.columns != columns ||
        other.pos.length != pos.length ||
        other.headers.length != headers.length) {
      return false;
    }
    for (final e in pos.entries) {
      if (other.pos[e.key] != e.value) return false;
    }
    for (var i = 0; i < headers.length; i++) {
      if (other.headers[i] != headers[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(width, height, columns, pos.length);
}

class _Slot {
  final int d;
  final int j;
  final List<String> col;

  const _Slot(this.d, this.j, this.col);
}

MapLayout layoutGraph(MapGraph graph, double W, double H) {
  final keys = graph.nodes.keys.toList();
  bool isShelf(String k) => graph.nodes[k]?.isShelf ?? false;

  // Longest chain of parent shelves, memoised and cycle-guarded: a cycle can
  // only come from data no writer should produce, and it must cost a column,
  // never a hang.
  final rank = <String, int>{};
  final visiting = <String>{};
  int rankOf(String k) {
    final known = rank[k];
    if (known != null) return known;
    if (visiting.contains(k)) return 0;
    visiting.add(k);
    var r = 0;
    for (final p in graph.up[k] ?? const <String>[]) {
      if (isShelf(p)) r = math.max(r, rankOf(p) + 1);
    }
    visiting.remove(k);
    return rank[k] = r;
  }

  final shelfKeys = keys.where(isShelf).toList();
  shelfKeys.forEach(rankOf);
  final maxDepth = shelfKeys.isEmpty
      ? 0
      : shelfKeys.fold<int>(0, (m, k) => math.max(m, rank[k]!)) + 1;
  final depth = <String, int>{
    for (final k in keys) k: isShelf(k) ? maxDepth - rank[k]! : 0,
  };

  // Neighbours by SIDE, which the sweeps need: a wire's left end is whichever
  // node sits in the lower column.
  final left = <String, List<String>>{};
  final right = <String, List<String>>{};
  for (final e in graph.edges) {
    final childLeft = depth[e.child]! <= depth[e.parent]!;
    final l = childLeft ? e.child : e.parent;
    final r = childLeft ? e.parent : e.child;
    (right[l] ??= []).add(r);
    (left[r] ??= []).add(l);
  }

  // Columns seeded in the graph's own insertion order — subscription order.
  final cols = <List<String>>[
    for (var d = 0; d <= maxDepth; d++)
      keys.where((k) => depth[k] == d).toList(),
  ];

  final ny = <String, double>{};
  void reindex(int d) {
    final col = cols[d];
    for (var i = 0; i < col.length; i++) {
      ny[col[i]] = col.length > 1 ? i / (col.length - 1) : 0.5;
    }
  }

  for (var d = 0; d < cols.length; d++) {
    reindex(d);
  }
  double? bary(String k, Map<String, List<String>> side) {
    final ns = (side[k] ?? const <String>[]).where(ny.containsKey).toList();
    if (ns.isEmpty) return ny[k];
    return ns.fold<double>(0, (s, n) => s + ny[n]!) / ns.length;
  }

  // JS's sort is stable; Dart's is not, so equal barycenters keep their order
  // by the index they held.
  void order(int d, Map<String, List<String>> side) {
    final col = cols[d];
    final scored = [
      for (var i = 0; i < col.length; i++) (col[i], bary(col[i], side), i),
    ];
    scored.sort((a, b) {
      final c = _jsCompare(a.$2, b.$2);
      return c != 0 ? c : a.$3.compareTo(b.$3);
    });
    cols[d] = [for (final s in scored) s.$1];
    reindex(d);
  }

  for (var s = 0; s < _sweeps; s++) {
    for (var d = 1; d <= maxDepth; d++) {
      order(d, left);
    }
    for (var d = maxDepth - 1; d >= 0; d--) {
      order(d, right);
    }
  }

  // Wrapping. One readable column is COL_FIELDS fields tall; past that the
  // depth deals its nodes round-robin into as many columns as it takes, so a
  // node's row still tracks its order and its wires stay short.
  final naturalH = H - pad - 22 - _top;
  int rowsIn(double room) => math.max(2, (room / rowStep).floor() + 1);
  final perCol = rowsIn(_colFields * naturalH);
  final perStaggered = rowsIn(_colFields * naturalH - _halfRow);
  final groups = <List<List<String>>>[
    for (final col in cols)
      _deal(col, col.length > perCol ? (col.length / perStaggered).ceil() : 1),
  ];

  // An empty depth takes no column and no header — a library whose shelves
  // hold nothing yet has no Volumes column to label.
  final slots = <_Slot>[];
  for (var d = 0; d < groups.length; d++) {
    for (var j = 0; j < groups[d].length; j++) {
      if (groups[d][j].isNotEmpty) slots.add(_Slot(d, j, groups[d][j]));
    }
  }

  final room = W - (pad + sideRoom) * 2;
  final step = slots.length > 1
      ? math.min(colStepMax, math.max(colStep, room / (slots.length - 1)))
      : 0.0;
  final contentW = (slots.length - 1) * step;
  final width = math.max(W, contentW + (pad + sideRoom) * 2);
  final leftX = (width - contentW) / 2;
  double slotX(int i) => leftX + i * step;

  bool wrapped(int d) => groups[d].where((c) => c.isNotEmpty).length > 1;
  double span(_Slot slot) => wrapped(slot.d)
      ? (groups[slot.d][0].length - 1) * rowStep + _halfRow
      : (slot.col.length - 1) * rowStep;
  final tallest = slots.fold<double>(0, (m, s) => math.max(m, span(s)));
  final neededH = math.max(naturalH, tallest);
  final height = math.max(H, _top + neededH + pad + 22);
  final midY = _top + neededH / 2;

  final pos = <String, Offset>{};
  for (var i = 0; i < slots.length; i++) {
    final slot = slots[i];
    final x = slotX(i);
    final colTop = midY - span(slot) / 2 + (slot.j.isOdd ? _halfRow : 0);
    for (var r = 0; r < slot.col.length; r++) {
      pos[slot.col[r]] = Offset(x, colTop + r * rowStep);
    }
  }

  // One header per depth that holds anything, centred over every column it
  // wrapped into.
  final headers = <MapHeader>[];
  for (var d = 0; d < groups.length; d++) {
    final xs = [
      for (var i = 0; i < slots.length; i++)
        if (slots[i].d == d) slotX(i),
    ];
    if (xs.isEmpty) continue;
    headers.add(
      MapHeader(
        (xs.reduce(math.min) + xs.reduce(math.max)) / 2,
        d == 0
            ? 'Volumes'
            : d == maxDepth
            ? 'Shelves'
            : 'Sub-shelves',
      ),
    );
  }

  return MapLayout(
    pos: pos,
    headers: headers,
    width: width,
    height: height,
    columns: slots.length,
  );
}

List<List<String>> _deal(List<String> col, int k) {
  final slices = List.generate(k, (_) => <String>[]);
  for (var i = 0; i < col.length; i++) {
    slices[i % k].add(col[i]);
  }
  return slices;
}

// `(a, b) => a[1] - b[1]` with JS's undefined → NaN → "equal". A barycenter is
// never null in practice (every key is indexed before the first sweep); the
// branch is the explicit one a port from JS owes (CLAUDE.md).
int _jsCompare(double? a, double? b) {
  if (a == null || b == null) return 0;
  return a < b
      ? -1
      : a > b
      ? 1
      : 0;
}

/// Wire geometry: a cubic that leaves each end HORIZONTALLY toward the other,
/// with its midpoint and the tangent there sampled from the same maths the
/// path encodes, so the arrowhead sits ON the curve.
///   cubic  P(.5) = (a + 3c1 + 3c2 + b)/8   P'(.5) ∝ (b − a) + (c2 − c1)
class WireGeometry {
  final Offset a;
  final Offset c1;
  final Offset c2;
  final Offset b;
  final Offset mid;
  final Offset tan;

  const WireGeometry(this.a, this.c1, this.c2, this.b, this.mid, this.tan);
}

WireGeometry wireGeometry(Offset a, Offset b) {
  final s = b.dx < a.dx ? -1 : 1;
  final dx = math.max(40.0, (b.dx - a.dx).abs() * 0.5);
  final c1 = Offset(a.dx + s * dx, a.dy);
  final c2 = Offset(b.dx - s * dx, b.dy);
  return WireGeometry(
    a,
    c1,
    c2,
    b,
    (a + c1 * 3 + c2 * 3 + b) / 8,
    (b - a) + (c2 - c1),
  );
}

/// The arrowhead, at the wire's MIDPOINT: a chip is drawn over the wire layer,
/// so a head parked at a node is covered by it. It points along [dir]:
/// `[tip, base-left, base-right]`.
List<Offset> arrowHead(Offset mid, Offset dir, double len, double wide) {
  final m = dir.distance == 0 ? 1.0 : dir.distance;
  final ux = dir.dx / m, uy = dir.dy / m;
  final nx = -uy, ny = ux;
  final tip = Offset(mid.dx + ux * (len / 2), mid.dy + uy * (len / 2));
  final base = Offset(mid.dx - ux * (len / 2), mid.dy - uy * (len / 2));
  return [
    tip,
    Offset(base.dx + nx * (wide / 2), base.dy + ny * (wide / 2)),
    Offset(base.dx - nx * (wide / 2), base.dy - ny * (wide / 2)),
  ];
}

/// The first of [keys] in layout order: leftmost column, then top to bottom.
String? firstInLayout(Iterable<String> keys, Map<String, Offset> pos) {
  final ks = keys.where(pos.containsKey).toList();
  if (ks.isEmpty) return null;
  ks.sort((a, b) {
    final x = pos[a]!.dx.compareTo(pos[b]!.dx);
    return x != 0 ? x : pos[a]!.dy.compareTo(pos[b]!.dy);
  });
  return ks.first;
}
