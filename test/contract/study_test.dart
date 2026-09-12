import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/study.dart';
import 'package:flutter_app/shared/extraction_markers.dart';
import 'package:flutter_app/state/study_schedule.dart';

/// The study screen's read boundary and its copy rules.
///
/// Every rule here is one a renderer would satisfy silently while being wrong:
/// a runway defaulted to zero renders a perfectly good notice, a status switch
/// with a `default: return status` renders a perfectly good chip, and a marker
/// drawn in the body role renders a perfectly good sentence.
void main() {
  StudyProgram program(Map<String, dynamic> json) =>
      StudyProgram.fromJson('p1', {'title': 'Anatomy', ...json});

  group('running low on material (4.7.0, ADR-043)', () {
    test('ABSENT is not zero — a new program carries no notice', () {
      // `material_runway` is written by the first BUILD, so a just-created
      // program has none. Defaulting it to 0 puts "no new material left" on
      // every new program, which is wrong and is the first thing a reader
      // sees.
      final p = program({});
      expect(p.materialRunway, isNull);
      expect(runwayNotice(p), isNull);
    });

    test('a healthy runway is silent', () {
      expect(runwayNotice(program({'material_runway': 3})), isNull);
      expect(runwayNotice(program({'material_runway': 12})), isNull);
    });

    test('the figure comes from the field, and zero is a real value', () {
      final zero = runwayNotice(program({'material_runway': 0}))!;
      expect(zero.text, startsWith('No new material left'));
      final one = runwayNotice(program({'material_runway': 1}))!;
      expect(one.text, startsWith('About one more session'));
      final two = runwayNotice(program({'material_runway': 2}))!;
      expect(two.text, startsWith('About 2 more sessions'));
    });

    test('never recomputed — a stuck reader is not told they are fine', () {
      // `unit_count - introduced_count` counts material still WITHHELD behind
      // a reading position: derive from it and the reader who is stuck is
      // exactly the one shown a healthy figure (ADR-043 §Rationale). Here the
      // derivation would say 90 and the measured answer is 1.
      final p = program({
        'unit_count': 100,
        'introduced_count': 10,
        'material_runway': 1,
        'low_material_reason': 'awaiting_position',
      });
      final n = runwayNotice(p)!;
      expect(n.text, contains('About one more session'));
      expect(n.text, isNot(contains('90')));
      expect(n.cta, 'Set your position');
      expect(n.action, 'edit');
    });

    test('`exhausted` sends the reader to a NEW program, not to settings', () {
      // `documentIds` is fixed once a program starts, so "add material" means
      // a new program — and the copy must not imply the program stopped:
      // reviews continue on schedule.
      final n = runwayNotice(program({
        'material_runway': 0,
        'low_material_reason': 'exhausted',
      }))!;
      expect(n.action, 'new');
      expect(n.cta, 'New program');
      expect(n.text, contains('fixed once it starts'));
    });

    test('an unrecognised reason takes the neutral wording, never an error',
        () {
      final n = runwayNotice(program({
        'material_runway': 1,
        'low_material_reason': 'some_future_reason',
      }))!;
      expect(n.text, 'About one more session of new material.');
      expect(n.action, 'edit');
    });
  });

  group('status is an open vocabulary', () {
    test('the three known values', () {
      expect(studyStatusLabel('active'), 'Active');
      expect(studyStatusLabel('maintenance'), 'Maintenance');
      expect(studyStatusLabel('complete'), 'Complete');
    });

    test('an unknown value is humanised, never the raw token', () {
      // "Never end a status switch with `default: return status`" — that is
      // how a reader is shown `pending_upload`.
      expect(studyStatusLabel('awaiting_sources'), 'Awaiting sources');
      expect(studyStatusLabel(''), 'Unknown');
    });
  });

  group('the schedule is stated from what was READ', () {
    test('every part of the sentence comes from the document', () {
      final p = program({
        'frequency': 'weekdays',
        'delivery_time': '06:15',
        'timezone': 'America/New_York',
        'email_enabled': true,
        'email_address': 'reader@example.com',
      });
      expect(programScheduleSentence(p),
          'Weekdays at 06:15 · New York · by email to reader@example.com');
    });

    test('email off is said as in-app, not as off', () {
      final p = program({'email_enabled': false, 'timezone': 'Europe/Dublin'});
      expect(programScheduleSentence(p), endsWith('in the app only'));
    });
  });

  group('the return date is the schedule\'s own answer', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1757500000000);
    int inDays(int d) => now.millisecondsSinceEpoch + d * 86400000;

    test('it is read from the response, and absent says nothing', () {
      expect(returnLabel(null, now: now), isNull);
      expect(returnLabel(inDays(0), now: now), 'back later today');
      expect(returnLabel(inDays(1), now: now), 'back tomorrow');
      expect(returnLabel(inDays(6), now: now), 'back in 6 days');
    });
  });

  group('the delivery axis on a session (4.22.0, INV-23)', () {
    test('absent means unknown, and `sent` is not a delivery claim', () {
      final s = StudySession.fromJson('s1', {'status': 'sent'});
      expect(s.delivery, isNull);
      expect(s.deliveryState, isNull);
      expect(s.gradable, isTrue);
    });

    test('a bounced session is still gradable — the axes are separate', () {
      final s = StudySession.fromJson('s1', {
        'status': 'sent',
        'delivery': {'state': 'bounced', 'detail': '550'},
      });
      expect(s.deliveryState, 'bounced');
      expect(s.gradable, isTrue,
          reason: 'the questions are here and answerable either way');
    });

    test('`generating` is not gradable even when items are present', () {
      // The build writes the full `items` array under `generating` BEFORE the
      // questions are drawn (2.37.2). Gate on the status, never on the items.
      final s = StudySession.fromJson('s1', {
        'status': 'generating',
        'items': [
          {'qid': 'q1', 'title': 'A', 'questions': []}
        ],
      });
      expect(s.items, isNotEmpty);
      expect(s.gradable, isFalse);
    });
  });

  group('markers inside an excerpt (4.52.0, ADR-089)', () {
    test('a block that is ONLY markers becomes asides', () {
      final out = markSanitizedHtml('<p>[On screen: 10 habits]</p>');
      expect(out, contains('x-mark-aside'));
      expect(out, contains('10 habits'));
      // The brackets are the defect: a marker is not a sentence.
      expect(out, isNot(contains('[On screen')));
    });

    test('a marker inside real text stays INLINE', () {
      // A block box here breaks the line box of the sentence it sits in, which
      // is the entire reason §17 has two shapes.
      final out =
          markSanitizedHtml('<p>He said [Video: a person typing] and left.</p>');
      expect(out, contains('x-mark-inline'));
      expect(out, isNot(contains('x-mark-aside')));
      expect(out, contains('He said'));
      expect(out, contains('and left.'));
    });

    test('a fragment with no marker is returned untouched', () {
      const plain = '<p>Ordinary prose.</p>';
      expect(markSanitizedHtml(plain), plain);
      expect(markSanitizedHtml(''), '');
      expect(markSanitizedHtml(null), '');
    });

    test('the marker text is set as TEXT, so it cannot become markup', () {
      // The spans this adds carry a class, which the chunk vocabulary lists
      // under Never — they are ours, added AFTER the allowlist has run.
      final out = markSanitizedHtml('<p>[Notes: <b>not bold</b>]</p>');
      expect(out, isNot(contains('<b>')));
    });
  });
}
