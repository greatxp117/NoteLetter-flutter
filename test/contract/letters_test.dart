import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/models/scripture_newsletter_settings.dart';
import 'package:flutter_app/pages/letters/delivery.dart';

/// The letter's read boundary and its two vocabularies.
///
/// Everything here is a **pure** rule that no request-construction suite can
/// see: `api_requests_test.dart` drives each endpoint from the FIXTURE body, so
/// it exercises the adapter and never what a screen puts in it. That is exactly
/// how this client shipped a readings-letter save that 400'd on every call for
/// its whole life while the suite stayed green.
void main() {
  Newsletter of(Map<String, dynamic> json) => Newsletter.fromJson('n1', json);

  group('the letterhead decides the frame (4.50.0, ADR-087)', () {
    test('the test is the attribute, not a version or a date', () {
      expect(
          of({'html_body': '<div data-nl-letterhead="1"><p>x</p></div>'})
              .hasLetterhead,
          isTrue);
      // Every letter written before 4.50.0 is frame-less and stays so forever.
      expect(of({'html_body': '<p>A card list.</p>'}).hasLetterhead, isFalse);
    });

    test('a letterheaded row quotes data-nl-lede, never the head of text_body',
        () {
      final n = of({
        'html_body': '<div data-nl-letterhead="1">'
            '<h1>NOTELETTER</h1><p>Vol. I · No. 12</p>'
            '<p data-nl-lede="1">Three passages found each other today.</p>'
            '</div>',
        'text_body': 'NOTELETTER Vol. I No. 12 Three passages…',
      });
      // The head of a letterheaded text_body is the masthead and the folio,
      // which reads the same in EVERY letter — a list built from it would say
      // nothing about any row.
      expect(n.lede, 'Three passages found each other today.');
    });

    test('without the marker the lede is the head of text_body, as before', () {
      expect(of({'text_body': '  Good morning.\n\n  A passage.  '}).lede,
          'Good morning. A passage.');
    });

    test('the lede is entity-decoded — it is our own escaped render', () {
      final n = of({
        'html_body': '<div data-nl-letterhead="1">'
            '<p data-nl-lede="1">Today&#x27;s letter &amp; its passages</p></div>',
      });
      expect(n.lede, "Today's letter & its passages");
    });
  });

  group('a letter opens when it has a body', () {
    test('empty and error rows are informational, not openable', () {
      expect(of({'status': 'empty', 'error_message': 'Nothing new'}).isReadable,
          isFalse);
      expect(of({'status': 'error', 'error_message': 'No recipient'}).isReadable,
          isFalse);
    });

    test('a bounced letter still opens — INV-23 keeps the axes separate', () {
      final n = of({
        'status': 'sent',
        'html_body': '<p>x</p>',
        'delivery': {'state': 'bounced', 'detail': '550 no such user'},
      });
      expect(n.isReadable, isTrue);
    });
  });

  group('the badge table (4.22.0 + 4.24.0, INV-23)', () {
    test('`sent` is NEVER rendered as Delivered', () {
      // Acceptance by the provider is not arrival. A letter Yahoo deferred
      // eight times looked sent and landed hours later (ADR-059).
      expect(letterBadge(status: 'sent', trigger: 'scheduled').text,
          'Scheduled');
      expect(letterBadge(status: 'sent', trigger: 'manual').text,
          'Sent on request');
      expect(
          letterBadge(status: 'sent', deliveryState: 'delivered').text,
          'Delivered');
    });

    test('delivery outranks the build outcome when it has something to say',
        () {
      expect(letterBadge(status: 'sent', deliveryState: 'bounced').text,
          'Not delivered');
      expect(letterBadge(status: 'sent', deliveryState: 'deferred').text,
          'Still sending…');
    });

    test('an absent delivery map means unknown, never failed', () {
      // Every record written before 4.22.0 has none, and there is no backfill.
      expect(letterBadge(status: 'sent', trigger: 'manual').settled, isTrue);
      expect(LetterDelivery.fromJson(null), isNull);
      expect(LetterDelivery.fromJson({'detail': 'x'}), isNull);
    });

    test('an unrecognised delivery state falls through silently', () {
      expect(letterBadge(status: 'sent', deliveryState: 'quarantined').text,
          'Scheduled');
    });

    test('email_failed is neither error nor sent', () {
      final b = letterBadge(status: 'email_failed');
      expect(b.text, 'Email failed');
      expect(b.text, isNot('Failed'));
    });

    test('empty is informational, not a failure', () {
      expect(letterBadge(status: 'empty').text, 'Nothing new');
      expect(letterBadge(status: 'empty').settled, isTrue);
      expect(letterBadge(status: 'error').settled, isFalse);
    });

    test('the note is the provider\'s own sentence, and only where actionable',
        () {
      expect(deliveryNote(state: 'delivered'), isNull);
      expect(deliveryNote(state: null), isNull);
      expect(deliveryNote(state: 'deferred', attempts: 8),
          contains('8 attempts'));
      expect(deliveryNote(state: 'bounced', detail: '550 no such user'),
          '550 no such user');
      expect(deliveryNote(state: 'dropped'),
          'The receiving mail server refused this message.');
    });
  });

  group('the readings letter', () {
    test('liturgical_day is a MAP — `as String?` over it throws', () {
      // data-model.md called this a date string until 4.52.3; the field is the
      // whole of `lectionary.identify()` and the date lives INSIDE it. Reading
      // it as a string did not degrade, it threw — so no readings letter could
      // be listed at all.
      final n = of({
        'kind': 'scripture',
        'liturgical_day': {
          'name': 'Thursday of week 23 in Ordinary Time',
          'date': '2026-09-10',
          'cycle': 'B',
          'liturgical_year': 2026,
        },
      });
      expect(n.liturgicalDay!.title, 'Thursday of week 23 in Ordinary Time');
      expect(n.liturgicalDay!.date, '2026-09-10');
      expect(n.liturgicalDay!.cycleLine, 'Cycle B · 2026');
    });

    test('a nameless day composes a readable title from the parts', () {
      final n = of({
        'kind': 'scripture',
        'liturgical_day': {
          'season': 'ordinary_time',
          'week': 23,
          'weekday': 'thursday',
        },
      });
      expect(n.liturgicalDay!.title, 'Thursday of week 23 in ordinary time');
    });

    test('a reading with no `parsed` key parsed — absent is not false', () {
      final n = of({
        'kind': 'scripture',
        'readings': [
          {'label': 'Gospel', 'ref': 'Lk 6:27-38', 'lead': true},
          {'label': 'First reading', 'ref': '?', 'parsed': false},
        ],
      });
      expect(n.readings.first.parsed, isTrue);
      expect(n.readings.last.parsed, isFalse);
      expect(n.readings.first.lead, isTrue);
    });

    test('settings send the closed key set and NOTHING else', () {
      // `frequency`, `itemsPerNewsletter` and `excludeRecentDays` are the daily
      // letter's keys; this endpoint answers them with a 400 that writes
      // nothing (`scripture-newsletter:settings-unknown-keys`).
      const cfg = ScriptureNewsletterSettings(
        enabled: true,
        emailAddress: 'reader@example.com',
        timezone: 'America/Chicago',
      );
      expect(cfg.toJson().keys.toSet(), {
        'enabled',
        'emailEnabled',
        'deliveryTime',
        'timezone',
        'emailAddress',
        'calendar',
      });
    });

    test('emailEnabled is absent-means-TRUE, and is not `enabled`', () {
      // Two controls, never merged (4.24.0, ADR-061): every document written
      // before the field already means "email me".
      expect(ScriptureNewsletterSettings.fromJson({'enabled': true}).emailEnabled,
          isTrue);
      expect(
          ScriptureNewsletterSettings.fromJson(
              {'enabled': true, 'emailEnabled': false}).emailEnabled,
          isFalse);
      // …and the one the footer's unsubscribe flips leaves the letter on.
      expect(
          ScriptureNewsletterSettings.fromJson(
              {'enabled': true, 'emailEnabled': false}).enabled,
          isTrue);
    });
  });

  group('one collection, two kinds (2.24.0, ADR-029 §3)', () {
    test('absent kind is daily — the filter is `!= scripture`', () {
      expect(of({}).isScripture, isFalse);
      expect(of({'kind': 'daily'}).isScripture, isFalse);
      expect(of({'kind': 'scripture'}).isScripture, isTrue);
    });
  });

  group('chunk_ids is the passage count, not an estimate', () {
    test('it names exactly the passages the body holds (4.39.0)', () {
      expect(of({'chunk_ids': ['a', 'b', 'c']}).chunkIds.length, 3);
      expect(of({}).chunkIds, isEmpty);
    });
  });
}
