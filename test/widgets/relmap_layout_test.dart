// The shelf map (component-kit §24, 5.25.0, ADR-177): the graph's node and
// edge rules and the normative layout, asserted over the pure module. Web's
// `tests/contract/shelf-map.test.js`, case for case and in its order — the
// layout is what makes two clients place one library alike, so a case web has
// and this file lacks is a claim only one client is held to.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/shared/relmap_layout.dart';

MapShelf shelf(String id, String title, {String? parentTagId}) =>
    MapShelf(id, title: title, color: 'sage-500', parentTagId: parentTagId);
MapDoc doc(
  String id,
  List<String> tags, {
  String? title,
  bool complete = true,
}) => MapDoc(
  id,
  title: title ?? 'Doc $id',
  type: 'pdf',
  complete: complete,
  tagIds: tags,
);
String S(String id) => nodeKey('shelf', id);
String V(String id) => nodeKey('volume', id);
String? parentOf(MapShelf s) => s.parentTagId;

List<String> sorted(Iterable<String> xs) => xs.toList()..sort();

void main() {
  group('graph — nodes and edges (ADR-177 §2)', () {
    final shelves = [
      shelf('a', 'Catholic'),
      shelf('b', 'Poetry'),
      shelf('e', 'Empty'),
    ];
    final docs = [
      doc('1', ['a']),
      doc('2', ['a', 'b']),
      doc('3', []), // unshelved: counted, not drawn
      doc('4', ['gone']), // a deleted shelf's id: unshelved too
      doc('5', ['b'], complete: false), // not a volume yet: neither
      doc('6', ['a', 'a']), // a duplicated id is one wire
    ];
    final g = buildShelfGraph(shelves, docs);

    test('draws a complete document on a live shelf, and every live shelf', () {
      expect(
        sorted(g.nodes.keys),
        sorted([S('a'), S('b'), S('e'), V('1'), V('2'), V('6')]),
      );
    });
    test('one volume → shelf wire per (volume, live shelf)', () {
      expect(
        sorted(g.edges.map((e) => '${e.child}>${e.parent}')),
        sorted([
          '${V('1')}>${S('a')}',
          '${V('2')}>${S('a')}',
          '${V('2')}>${S('b')}',
          '${V('6')}>${S('a')}',
        ]),
      );
      expect(g.edges.every((e) => e.type == 'volume-shelf'), isTrue);
    });
    test('counts the legend: shelves, drawn volumes, links, unshelved', () {
      expect(
        g.counts,
        const MapCounts(shelves: 3, volumes: 3, links: 4, unshelved: 2),
      );
    });
    test('a shelf counts the volumes beneath it, an empty shelf 0', () {
      expect(g.nodes[S('a')]!.count, 3);
      expect(g.nodes[S('b')]!.count, 1);
      expect(g.nodes[S('e')]!.count, 0);
    });
    test('parent_tag_id draws nothing at 5.25.0', () {
      final split = buildShelfGraph(
        [shelf('p', 'Parent'), shelf('c', 'Child', parentTagId: 'p')],
        [
          doc('1', ['c']),
        ],
      );
      expect(split.edges.any((e) => e.type == 'shelf-parent'), isFalse);
      expect(split.nodes[S('p')]!.count, 0);
    });
    test('the window is full at the subscription limit, not before', () {
      List<MapDoc> many(int n) => [
        for (var i = 0; i < n; i++) doc('$i', ['a']),
      ];
      expect(
        buildShelfGraph(shelves, many(documentWindow - 1)).windowFull,
        isFalse,
      );
      expect(buildShelfGraph(shelves, many(documentWindow)).windowFull, isTrue);
    });
  });

  group('graph — nesting is one more edge kind (ready for nesting)', () {
    final shelves = [
      shelf('cath', 'Catholic'),
      shelf('mary', 'Mary', parentTagId: 'cath'),
      shelf('app', 'Apparitions', parentTagId: 'mary'),
    ];
    final docs = [
      doc('1', ['app']),
      doc('2', ['mary']),
      doc('3', ['cath', 'app']),
    ];
    final g = buildShelfGraph(shelves, docs, parentOf: parentOf);

    test('a parent counts every volume beneath it once (the roll-up)', () {
      // 3 sits on Catholic AND on Apparitions: one volume, counted once under each.
      expect(g.nodes[S('cath')]!.count, 3);
      expect(g.nodes[S('mary')]!.count, 3);
      expect(g.nodes[S('app')]!.count, 2);
    });
    test(
      'the connected path is ancestors ∪ self ∪ descendants, with the wires among them',
      () {
        final p = connectedPath(g, S('mary'));
        expect(
          sorted(p.nodes),
          sorted([S('cath'), S('mary'), S('app'), V('1'), V('2'), V('3')]),
        );
        // 3 → cath is a wire between two lit nodes, so it lights too.
        expect(p.edges.length, g.edges.length);
        final leaf = connectedPath(g, V('1'));
        expect(
          sorted(leaf.nodes),
          sorted([V('1'), S('app'), S('mary'), S('cath')]),
        );
      },
    );
    test('the inspector reads the way the arrows do', () {
      expect(
        relationsOf(g, S('mary'))!.sections
            .map((s) => [s.label, s.nodes.map((n) => n.id).toList()])
            .toList(),
        [
          [
            'Inside',
            ['cath'],
          ],
          [
            'Sub-shelves',
            ['app'],
          ],
          [
            'Volumes',
            ['2'],
          ],
        ],
      );
      final v3 = relationsOf(g, V('3'))!.sections;
      expect(v3.map((s) => s.label).toList(), ['On shelves']);
      expect(v3.single.nodes, [g.nodes[S('cath')], g.nodes[S('app')]]);
    });
    test('a flat map names no nesting sections', () {
      final flat = buildShelfGraph(
        [shelf('a', 'A')],
        [
          doc('1', ['a']),
        ],
      );
      expect(relationsOf(flat, S('a'))!.sections.map((s) => s.label).toList(), [
        'Volumes',
      ]);
    });
    test('a cycle in the data neither hangs nor double-counts', () {
      final loop = buildShelfGraph(
        [shelf('x', 'X', parentTagId: 'y'), shelf('y', 'Y', parentTagId: 'x')],
        [
          doc('1', ['x']),
        ],
        parentOf: parentOf,
      );
      expect(loop.nodes[S('y')]!.count, 1);
      final lay = layoutGraph(loop, 1000, 600);
      expect(lay.pos.length, 3);
    });
  });

  group('search folds like the shelf picker (§20.1 rule 1)', () {
    final g = buildShelfGraph(
      [shelf('a', 'Mária'), shelf('b', 'Humility')],
      [
        doc('1', ['a'], title: 'On the Rosary'),
      ],
    );
    test('lower-cases, strips accents, trims, matches a substring', () {
      expect(searchMatches(g, '  MARIA ').toList(), [S('a')]);
      expect(searchMatches(g, 'ros').toList(), [V('1')]);
      expect(searchMatches(g, '   ').length, 0);
    });
  });

  group('layout (ADR-177 §3)', () {
    test('volumes in column 0, shelves in the one column to their right', () {
      final g = buildShelfGraph(
        [shelf('a', 'A'), shelf('b', 'B')],
        [
          doc('1', ['a']),
          doc('2', ['b']),
        ],
      );
      final l = layoutGraph(g, 1000, 600);
      expect(l.columns, 2);
      expect(l.pos[V('1')]!.dx, l.pos[V('2')]!.dx);
      expect(l.pos[S('a')]!.dx, greaterThan(l.pos[V('1')]!.dx));
      expect(l.headers.map((h) => h.label).toList(), ['Volumes', 'Shelves']);
    });
    test(
      'a nested shelf sits left of its parent; top-level shelves take the rightmost column',
      () {
        final shelves = [
          shelf('top', 'Top'),
          shelf('mid', 'Mid', parentTagId: 'top'),
          shelf('leaf', 'Leaf', parentTagId: 'mid'),
          shelf('solo', 'Solo'),
        ];
        final g = buildShelfGraph(shelves, [
          doc('1', ['leaf']),
          doc('2', ['solo']),
        ], parentOf: parentOf);
        final l = layoutGraph(g, 1400, 600);
        expect(l.pos[S('top')]!.dx, l.pos[S('solo')]!.dx);
        expect(l.pos[S('mid')]!.dx, lessThan(l.pos[S('top')]!.dx));
        expect(l.pos[S('leaf')]!.dx, lessThan(l.pos[S('mid')]!.dx));
        expect(l.pos[V('1')]!.dx, lessThan(l.pos[S('leaf')]!.dx));
        expect(l.headers.map((h) => h.label).toList(), [
          'Volumes',
          'Sub-shelves',
          'Sub-shelves',
          'Shelves',
        ]);
      },
    );
    test('one row step for the whole graph', () {
      final g = buildShelfGraph(
        [shelf('a', 'A')],
        [
          doc('1', ['a']),
          doc('2', ['a']),
          doc('3', ['a']),
        ],
      );
      final l = layoutGraph(g, 1000, 600);
      final ys = [V('1'), V('2'), V('3')].map((k) => l.pos[k]!.dy).toList()
        ..sort();
      expect(ys[1] - ys[0], rowStep);
      expect(ys[2] - ys[1], rowStep);
    });
    test('barycenter sweeps put a volume beside its shelf', () {
      // Seeded B's volume first; the sweep orders volumes by their shelf's row.
      final g = buildShelfGraph(
        [shelf('a', 'A'), shelf('b', 'B')],
        [
          doc('1', ['b']),
          doc('2', ['a']),
        ],
      );
      final l = layoutGraph(g, 1000, 600);
      expect(
        (l.pos[V('1')]!.dy - l.pos[V('2')]!.dy).sign,
        (l.pos[S('b')]!.dy - l.pos[S('a')]!.dy).sign,
      );
    });
    test(
      'a tall column wraps round-robin, every other column half a row lower',
      () {
        final docs = [
          for (var i = 0; i < 60; i++) doc('$i', ['a']),
        ];
        final g = buildShelfGraph([shelf('a', 'A')], docs);
        final l = layoutGraph(g, 1000, 300);
        expect(l.columns, greaterThan(2));
        final xs = docs.map((d) => l.pos[V(d.id)]!.dx).toSet().toList()..sort();
        expect(xs.length, l.columns - 1);
        double firstY(double x) => docs
            .where((d) => l.pos[V(d.id)]!.dx == x)
            .map((d) => l.pos[V(d.id)]!.dy)
            .reduce((a, b) => a < b ? a : b);
        expect(firstY(xs[1]) - firstY(xs[0]), rowStep / 2);
        // One header for the wrapped depth, not one per column.
        expect(l.headers.where((h) => h.label == 'Volumes').length, 1);
      },
    );
    test('an empty depth takes no column and no header', () {
      final g = buildShelfGraph([shelf('a', 'A')], []);
      final l = layoutGraph(g, 1000, 600);
      expect(l.columns, 1);
      expect(l.headers.map((h) => h.label).toList(), ['Shelves']);
    });
    test('the canvas grows rather than packs', () {
      final docs = [
        for (var i = 0; i < 400; i++) doc('$i', ['a']),
      ];
      final g = buildShelfGraph([shelf('a', 'A')], docs);
      final l = layoutGraph(g, 600, 300);
      expect(l.width, greaterThan(600));
      expect(l.height, greaterThanOrEqualTo(300));
    });
    test('is deterministic', () {
      final g = buildShelfGraph(
        [shelf('a', 'A'), shelf('b', 'B')],
        [
          doc('1', ['a', 'b']),
          doc('2', ['b']),
          doc('3', ['a']),
        ],
      );
      expect(layoutGraph(g, 900, 500), layoutGraph(g, 900, 500));
    });
  });

  group('wires and search order', () {
    test(
      'a wire leaves each end horizontally and its head points at the parent',
      () {
        final w = wireGeometry(const Offset(0, 0), const Offset(200, 50));
        // web: d.startsWith('M 0 0 C 100 0, 100 50, 200 50')
        expect(
          [w.a, w.c1, w.c2, w.b],
          [
            const Offset(0, 0),
            const Offset(100, 0),
            const Offset(100, 50),
            const Offset(200, 50),
          ],
        );
        expect(w.tan.dx, greaterThan(0));
        // A sub-shelf's parent is to its RIGHT as well, so the head still points right.
        expect(
          wireGeometry(const Offset(300, 0), const Offset(600, 0)).tan.dx,
          greaterThan(0),
        );
      },
    );
    test(
      'Enter takes the first match in layout order: leftmost column, then top to bottom',
      () {
        const pos = {
          'a': Offset(500, 10),
          'b': Offset(100, 90),
          'c': Offset(100, 20),
        };
        expect(firstInLayout({'a', 'b', 'c'}, pos), 'c');
        expect(firstInLayout(<String>{}, pos), isNull);
      },
    );
  });
}
