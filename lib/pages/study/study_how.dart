/// How Deep Study Works (5.45.0, `spec/screens/study.md` §How Deep Study
/// Works; web `pages/study/StudyHow.jsx`), built on Xavier's ruling of
/// 2026-11-01 and reached from Study only: the programs masthead's link and the
/// empty state's button, never onboarding.
///
/// The D frame with **no sheet**: one reading column at most 820 wide
/// (`.dp-how .d-main`). Every sentence is a claim about the backend
/// (`functions/area_study.py`) and is the spec's, verbatim — the prototype's
/// copy was corrected wherever it was false (ten documents, not fifty; a
/// session, not a letter; sessions on the days the reader chose; counts, not a
/// duration; email is a switch; a missed day makes nothing wait). The
/// references are citations, kept as written, and open in the system browser.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../widgets/kit/kit.dart';

/// The four steps of a program — the spec's strings, each checked against the
/// build.
const studyHowSteps = <(String, String)>[
  (
    'You choose the documents',
    'Up to ten finished documents, one subject, in the order you want them '
        'taught. Sessions introduce passages from the first document before '
        'moving on, and from a reading only as far as you’ve read.',
  ),
  (
    'A session comes on the days you choose',
    'Daily, on weekdays or once a week: a few new passages, plus the ones '
        'that have come due. A day with nothing new and nothing due brings '
        'none. You set how much a session may carry; anything due beyond '
        'that waits and comes first next time.',
  ),
  (
    'It arrives as its own session',
    'Separate from your daily letter, at its own hour: here, and by email '
        'unless you turn that off. The email carries the questions only — '
        'answering happens here, so the grade can be written down.',
  ),
  (
    'Your grade sets the next date',
    'Again, Hard, Good or Easy. The next date comes back from the schedule '
        'as you answer, and the session shows it.',
  ),
];

/// The further reading, verbatim from the prototype (`ST_REFS`).
const studyHowRefs = <KitStudyRef>[
  KitStudyRef(
    authors: 'Cepeda, Pashler, Vul, Wixted & Rohrer',
    year: '2006',
    title: 'Distributed practice in verbal recall tasks: a review and '
        'quantitative synthesis',
    where: 'Psychological Bulletin',
    href: 'https://doi.org/10.1037/0033-2909.132.3.354',
    note: 'A synthesis of spacing studies: the same study time spread out '
        'beats the same time in one sitting.',
  ),
  KitStudyRef(
    authors: 'Roediger & Karpicke',
    year: '2006',
    title: 'Test-enhanced learning: taking memory tests improves long-term '
        'retention',
    where: 'Psychological Science',
    href: 'https://doi.org/10.1111/j.1467-9280.2006.01693.x',
    note: 'Being asked a question does more for later recall than reading '
        'the same material again.',
  ),
  KitStudyRef(
    authors: 'Dunlosky, Rawson, Marsh, Nathan & Willingham',
    year: '2013',
    title: 'Improving students’ learning with effective learning techniques',
    where: 'Psychological Science in the Public Interest',
    href: 'https://doi.org/10.1177/1529100612453266',
    note: 'A survey of ten study techniques. Practice testing and distributed '
        'practice are the two rated most useful; rereading and highlighting '
        'are not.',
  ),
];

const studyHowOverviews = <(String, String)>[
  ('spaced repetition', 'https://en.wikipedia.org/wiki/Spaced_repetition'),
  ('the testing effect', 'https://en.wikipedia.org/wiki/Testing_effect'),
];

class StudyHowPage extends StatelessWidget {
  /// Where a citation goes: the system browser (injectable for tests).
  final void Function(String href)? openLink;

  const StudyHowPage({super.key, this.openLink});

  static void _external(String href) =>
      launchUrlString(href, mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    void back() => context.go('/study');
    return KitDPage(
      back: KitDBackControl('Study programs', onTap: back),
      folio: 'Deep study · How it works',
      title: 'How Deep Study Works',
      stand:
          'Your letter keeps your whole library in view. A study program is '
          'the other direction: one subject, asked back to you until you '
          'have it.',
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const KitStudyProse([
                'Reading something once puts it in the library, not in your '
                    'head. Two habits change that, and both are old, dull and '
                    'well evidenced: being *asked* instead of re-reading, and '
                    'being asked *again later* rather than twice in one sitting.',
                'A study program is those two habits, run for you over '
                    'documents from your library.',
              ]),
              const KitFormSection(
                eyebrow: 'The two techniques',
                children: [
                  KitStudyMoves([
                    KitStudyMove(
                      'I',
                      'Retrieval practice',
                      'You answer before the answer shows. The effort of '
                          'pulling something back is what makes it easier to '
                          'pull back next time — which is why the player hides '
                          'the answer behind a reveal, and why review items '
                          'keep their excerpt behind a disclosure.',
                      icon: Icons.chat_bubble_outline,
                    ),
                    KitStudyMove(
                      'II',
                      'Spaced repetition',
                      'A passage you answered well comes back further away; '
                          'one you missed comes back sooner. The gap widens '
                          'each time you succeed, so a long list of things '
                          'stays affordable to keep.',
                      icon: Icons.calendar_today_outlined,
                    ),
                  ]),
                  KitFineNote(
                    'Neither technique is ours. The reading below is where '
                    'they come from.',
                    top: 0,
                  ),
                ],
              ),
              KitFormSection(
                eyebrow: 'What a program does with them',
                children: [
                  const SizedBox(height: 12),
                  KitRowList(rows: [
                    for (final (i, s) in studyHowSteps.indexed)
                      KitFormRow(
                        number: '${i + 1}',
                        title: s.$1,
                        plain: true,
                        subtitle: s.$2,
                      ),
                  ]),
                ],
              ),
              const KitFormSection(
                eyebrow: 'What it doesn’t do',
                lede:
                    'There is no score, no retention percentage, no streak and '
                    'no timer. Nothing is counted except what is actually '
                    'stored, such as how many passages a program has '
                    'introduced, when each one is next due, and how many were '
                    'due beyond a session’s length. A day you miss records '
                    'nothing against you: what you did not grade stays due and '
                    'comes back.',
              ),
              KitFormSection(
                eyebrow: 'Further reading',
                children: [
                  KitStudyRefs(
                    refs: studyHowRefs,
                    overviews: studyHowOverviews,
                    onOpen: openLink ?? _external,
                  ),
                ],
              ),
              KitFormFoot(
                leading: [
                  KitButton.primary(
                    'New program',
                    icon: Icons.add,
                    onPressed: () => context.go('/study/new'),
                  ),
                  KitButton.ghost('Back to programs', onPressed: back),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
