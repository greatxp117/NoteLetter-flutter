import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/build_info.dart';
import 'package:flutter_app/models/support.dart';

/// The support read shapes (`spec/data-model.md` §/support_threads, INV-06).
///
/// There is no captured `firestore/*` fixture for these — the suite predates
/// them — so this asserts the mapper directly against the field names and rules
/// the data model states. Each case here is a rule someone could plausibly
/// implement the other way round.
void main() {
  group('SupportThread', () {
    test('INV-06 — timestamps become epoch ms at the boundary', () {
      final thread = SupportThread.fromJson('u1', {
        'created_at': Timestamp.fromMillisecondsSinceEpoch(1755648000000),
        'last_message_at': Timestamp.fromMillisecondsSinceEpoch(1755648060000),
        'last_sender': 'user',
        'message_count': 2,
        'unread_for_user': 1,
      });
      expect(thread.createdAt, 1755648000000);
      expect(thread.lastMessageAt, 1755648060000);
      expect(thread.messageCount, 2);
      expect(thread.unreadForUser, 1);
    });

    test('a fresh thread with no counters reads as zero, not null', () {
      // Absent counters are the contract's "treat absent as 0" — the footer
      // badge reads this on every screen and may not be null-shaped.
      final thread = SupportThread.fromJson('u1', const {});
      expect(thread.unreadForUser, 0);
      expect(thread.messageCount, 0);
      expect(thread.createdAt, isNull);
    });

    test('awaiting is DERIVED from last_sender, never stored', () {
      // screens/support.md §States. A second field saying the same thing is a
      // second field that can disagree.
      expect(
          SupportThread.fromJson('u1', const {'last_sender': 'user'})
              .awaitingAnswer,
          isTrue);
      expect(
          SupportThread.fromJson('u1', const {'last_sender': 'support'})
              .awaitingAnswer,
          isFalse);
      expect(SupportThread.fromJson('u1', const {}).awaitingAnswer, isFalse);
    });
  });

  group('SupportMessage', () {
    test('sender is an OPEN vocabulary for reading', () {
      // spec/api/support.md §Reads: anything that is not `user` renders as the
      // other side, so a later `sender: "system"` needs no breaking client
      // change. This is the assertion that keeps someone from "tightening" the
      // mapper into a three-case enum that throws on the fourth.
      expect(SupportMessage.fromJson('m', const {'sender': 'user'}).sender,
          SupportSender.user);
      expect(SupportMessage.fromJson('m', const {'sender': 'support'}).sender,
          SupportSender.support);
      expect(SupportMessage.fromJson('m', const {'sender': 'system'}).sender,
          SupportSender.support);
      expect(SupportMessage.fromJson('m', const {}).sender,
          SupportSender.support);
    });

    test('body and route survive; INV-06 on created_at', () {
      final m = SupportMessage.fromJson('m1', {
        'sender': 'user',
        'body': 'The reader scrolls to the top when I tag a passage.',
        'route': '/reader/doc-1',
        'created_at': Timestamp.fromMillisecondsSinceEpoch(1755648000000),
      });
      expect(m.body, startsWith('The reader scrolls'));
      expect(m.route, '/reader/doc-1');
      expect(m.createdAt, 1755648000000);
    });

    test('a message with no body maps to empty, never null', () {
      expect(SupportMessage.fromJson('m', const {}).body, '');
    });
  });

  test('clientVersion carries the pin, and the pin has one source', () {
    // BuildInfo.contractPin is a second copy of the CLAUDE.md pin. This is the
    // thing that compares them — a vocabulary written in two places with
    // nothing comparing them is the shape of half the defects in ../TODO.md.
    expect(BuildInfo.clientVersion, 'flutter/${BuildInfo.contractPin}');
    expect(BuildInfo.platform, 'flutter',
        reason: 'a member of the endpoint\'s closed platform vocabulary');
  });
}
