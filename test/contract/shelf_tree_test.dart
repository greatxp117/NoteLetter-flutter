// INV-33 (contract 5.28.0, ADR-185): the shelf tree — the resolution rule,
// the subtree, the path, tree order, letter-mode inheritance and which
// parents a move may offer. Case for case with web's
// tests/contract/shelf-tree.test.js, which runs the backend
// `area_tags._ShelfTree`'s cases; two rules would be two answers to "is this
// inside that".
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/shared/shelf_tree.dart';

Tag sh(String id, String title, {String? parent, String? mode}) =>
    Tag.fromJson(id, {
      'user_id': 'u1',
      'title': title,
      'parent_tag_id': ?parent,
      'letter_mode': ?mode,
    });

final lib = [
  sh('cat', 'Catholic', mode: 'muted'),
  sh('mary', 'Mary', parent: 'cat', mode: 'mixed'),
  sh('app', 'Apparitions', parent: 'mary'),
  sh('hum', 'Humility', parent: 'cat'),
  sh('a', 'Cycle A', parent: 'b'),
  sh('b', 'Cycle B', parent: 'a'),
  sh('c', 'Into the cycle', parent: 'a'),
  sh('dang', 'Dangling', parent: 'gone'),
  sh('self', 'Self', parent: 'self'),
];

void main() {
  group('INV-33 resolution', () {
    final t = ShelfTree(lib);
    test('a live parent counts', () {
      expect(t.parent['mary'], 'cat');
      expect(t.parent['app'], 'mary');
    });
    test('a dangling id, the shelf itself, and a stored cycle are top-level', () {
      expect(t.parent['dang'], isNull);
      expect(t.parent['self'], isNull);
      expect(t.parent['a'], isNull);
      expect(t.parent['b'], isNull);
    });
    test('a shelf whose chain only reaches a cycle keeps its parent', () {
      expect(t.parent['c'], 'a');
    });
    test('a deleting parent is not a parent — the subscription has dropped it',
        () {
      expect(ShelfTree([sh('kid', 'Kid', parent: 'leaving')]).parent['kid'],
          isNull);
    });
    test('past the hop guard a shelf is top-level; the guard is 64', () {
      final chain = [
        for (var i = 0; i < 70; i++)
          sh('n$i', 'N$i', parent: i == 0 ? null : 'n${i - 1}'),
      ];
      final d = ShelfTree(chain);
      expect(shelfHops, 64);
      expect(d.ancestors('n64'), hasLength(64));
      expect(d.parent['n65'], isNull);
    });
  });

  group('INV-33 membership and order', () {
    final t = ShelfTree(lib);
    test('the subtree runs down, never up', () {
      expect(t.subtreeIds('cat'), {'cat', 'mary', 'app', 'hum'});
      expect(t.subtreeIds('mary'), {'mary', 'app'});
      expect(t.subtreeIds('a'), {'a', 'c'});
    });
    test('a document is in a shelf when any of its shelves is in the subtree',
        () {
      expect(inSubtree(['app'], t.subtreeIds('cat')), isTrue);
      expect(inSubtree(['cat'], t.subtreeIds('mary')), isFalse);
      expect(inSubtree(const [], t.subtreeIds('cat')), isFalse);
    });
    test('tree order is depth first, siblings in subscription order', () {
      expect([for (final r in t.ordered()) r.shelf.id],
          ['cat', 'mary', 'app', 'hum', 'a', 'c', 'b', 'dang', 'self']);
      expect(t.ordered().firstWhere((r) => r.shelf.id == 'app').depth, 2);
    });
    test('the path is the ancestors, root first', () {
      expect(t.pathLabel('app'), 'Catholic${shelfPathSep}Mary');
      expect(t.pathLabel('cat'), '');
      expect(shelfPathSep, ' › ');
    });
  });

  group('INV-33 letter-mode inheritance', () {
    final t = ShelfTree(lib);
    test('the nearest explicit mode up the chain wins', () {
      expect(t.letterMode('hum').mode, 'muted');
      expect(t.letterMode('hum').from?.id, 'cat');
      expect(t.letterMode('app').mode, 'mixed');
      expect(t.letterMode('app').from?.id, 'mary');
    });
    test('the default is mixed, set by nobody', () {
      expect(t.letterMode('dang').mode, 'mixed');
      expect(t.letterMode('dang').from, isNull);
    });
    test('an absent or unknown stored mode is no mode of the shelf\'s own', () {
      expect(sh('x', 'X').ownLetterMode, isNull);
      expect(Tag.fromJson('y', {'title': 'Y', 'letter_mode': 'loud'}).ownLetterMode,
          isNull);
    });
  });

  group('INV-33 moves', () {
    final t = ShelfTree(lib);
    test('never into itself or below itself', () {
      expect(t.canHold('cat', 'cat'), isFalse);
      expect(t.canHold('cat', 'app'), isFalse);
      expect(t.canHold('app', 'hum'), isTrue);
      expect(t.canHold('app', null), isTrue);
    });
    test('never re-closing a cycle already stored', () {
      expect(t.canHold('a', 'b'), isFalse);
    });
    test('never under a shelf the caller does not hold', () {
      expect(t.canHold('app', 'gone'), isFalse);
    });
  });
}
