import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart' show Icons, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../build_info.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../shared/local_flags.dart';
import '../shared/plan.dart';
import '../shared/plan_limit_signal.dart';
import '../state/ai_settings_notifier.dart';
import '../state/auth_notifier.dart';
import '../state/cloud_notifier.dart';
import '../state/theme_notifier.dart';
import '../widgets/kit/kit.dart';
import 'settings/sources_section.dart';
import 'settings/summaries_section.dart';

/// Settings (`spec/screens/settings.md` §Composition (direction D); web
/// `SettingsView`).
///
/// The D frame: the masthead (`Settings · Account · {name or email}`, the
/// title, the standfirst), no action and no settings; the sheet *Settings*
/// with Contents of only the groups drawn, in order, then Also (*Write to
/// support*, *Sign out*); each group under a §31 numbered head, 56 apart, its
/// rows a ruled register ([KitDSetScope]); Setup's replay a featured row. On
/// a phone the sheet is the running head `§ {numeral} · {group} · {i} of {n}`.
///
/// The letter's own form is NOT here: it is `/letters/settings`, as the
/// reference has it (F-05 moved it rather than copying it). This screen keeps
/// one row through to it, so the way in from Settings survives the move.
///
/// Settings draws no camera-roll group in D (5.43.0, ADR-198): the camera
/// roll's settings live on the Library (F-146).
class SettingsPage extends StatefulWidget {
  /// Open at the Sources section — the `/settings/sources` route the Sources
  /// page links to (ruled 2026-10-09; web `settings-sources`).
  final bool focusSources;

  const SettingsPage({super.key, this.focusSources = false});

  /// The generative-AI switch row's description (settings.md §Generative AI
  /// section), verbatim.
  static const aiDescription =
      'Summaries, Ask and cohesive reading in the app, and the librarian’s '
      'notes and study questions in what NoteLetter sends you.';

  /// The caption the switch row gains while generative AI is off — the
  /// honest half of the switch (ADR-186 §7); it may not be dropped.
  static const aiOffCaption =
      'NoteLetter still uses AI to read what you add — recognising text, '
      'transcribing audio, indexing it for search — and to suggest shelves. '
      'Summaries are still prepared, so they return if you switch this back '
      'on.';

  /// Video reading's description (settings.md §Video reading), verbatim.
  static const videoDescription =
      'Which AI picks the pictures, decides what leads and indexes the '
      'Instagram, TikTok and other short videos you add. Transcription and '
      'search are the same either way. Applies to videos you add from now on.';

  /// Keys the holds and the device run find.
  static const aiSwitchKey = ValueKey('set-ai-switch');
  static const videoKey = ValueKey('set-video-ai');
  static const contentsKey = ValueKey('set-contents');

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final KitSections _sec = KitSections(const []);

  @override
  void initState() {
    super.initState();
    LocalFlags.ensureLoaded();
    // The one app-wide subscription; idempotent (the shell starts it too).
    context.read<AiSettingsNotifier?>()?.start();
  }

  @override
  void dispose() {
    _sec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeN = context.watch<ThemeNotifier>();
    final user = context.watch<AuthNotifier>().user;
    final named = user?.displayName?.trim().isNotEmpty ?? false;
    final who = named ? user!.displayName! : (user?.email ?? '');
    final ai = context.watch<AiSettingsNotifier?>();
    // Only a READ `on` draws Summaries and Your librarian (api/ai.md §What
    // the switch hides): loading and failed draw neither (INV-34). A tree
    // with no notifier is a bare harness, and reads on.
    final aiOn = ai == null || ai.aiOn;
    final sourcesShown = SourcesSection.shownFor(
      context.watch<CloudNotifier?>(),
    );

    // Contents lists only the groups the page draws, in its order (settings.md
    // §Composition): Summaries only while generative AI is on, Sources only
    // once a service is connected. Setup can always run here — the replay is
    // a flag the onboarding gate answers.
    final secs = [
      const KitContentsItem('setup', 'Setup'),
      const KitContentsItem('appearance', 'Appearance'),
      const KitContentsItem('letter', 'The daily letter'),
      const KitContentsItem('ai', 'Generative AI'),
      if (aiOn) const KitContentsItem('summaries', 'Summaries'),
      const KitContentsItem('scripture', 'Scripture'),
      const KitContentsItem('notifications', 'Notifications'),
      if (sourcesShown) const KitContentsItem('sources', 'Sources'),
      const KitContentsItem('account', 'Account'),
    ];
    final ids = [for (final s in secs) s.id];
    if (!listEquals(_sec.ids, ids)) _sec.ids = ids;

    Widget group(String id, Widget child) {
      final i = ids.indexOf(id);
      return KitDSetGroup(
        n: i,
        title: secs[i].label,
        headKey: _sec.keyOf(id),
        child: child,
      );
    }

    void signOut() => context.read<AuthNotifier>().signOut();

    return KitDPage(
      folio: 'Settings · Account · $who',
      title: 'Settings',
      stand:
          'How NoteLetter looks, how your letter behaves, and where your '
          'account stands.',
      sections: _sec,
      sheet: KitDSheet(
        label: 'Settings',
        foldOnPick: true,
        peek: KitSecPeek(items: secs, sections: _sec),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KitDLabel('Contents', first: true),
            KitContents(
              key: SettingsPage.contentsKey,
              items: secs,
              sections: _sec,
            ),
            KitSheetAlso(
              children: [
                KitAlsoButton(
                  'Write to support',
                  icon: Icons.chat_bubble_outline,
                  onTap: () => context.go('/support'),
                ),
                KitAlsoButton('Sign out', icon: Icons.logout, onTap: signOut),
              ],
            ),
          ],
        ),
      ),
      child: KitDSetScope(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Setup (2.27.0; `screens/onboarding.md` §States/Replay) ──────
            // Replaying first-run is how someone who skipped it, or who wants
            // to re-tune the letter from scratch, gets back to it — and it is
            // the ONLY door once the flag is set, since the gate needs an
            // empty library. Non-destructive by construction: the wizard
            // writes nothing until its last step.
            group(
              'setup',
              KitDSetFeature(
                icon: KitQuill.icon,
                title: 'Run through setup again',
                description:
                    'Replay first-run — bring in sources, write your '
                    'librarian’s mission, and tune your letter. Nothing '
                    'you’ve already set is changed until you finish.',
                action: KitButton.primary(
                  'Run setup',
                  onPressed: () => LocalFlags.onboardingReplay.value = true,
                ),
              ),
            ),

            // ── Appearance ─────────────────────────────────────────────────
            group(
              'appearance',
              KitRowList(
                rows: [
                  KitSettingRow(
                    icon: Icons.wb_sunny_outlined,
                    title: 'Theme',
                    description:
                        'Light, dark, or follow your system. The plum chrome '
                        'stays warm either way.',
                    wideControl: true,
                    trailing: [
                      // The reference's ThemeToggle: three glyphs, named by
                      // their titles, no text (F-80 (3)); D keeps the three
                      // icon buttons.
                      KitThemeToggle(
                        selected: switch (themeN.themeMode) {
                          ThemeMode.light => 0,
                          ThemeMode.system => 1,
                          ThemeMode.dark => 2,
                        },
                        onChanged: (i) => themeN.setMode(
                          const [
                            ThemeMode.light,
                            ThemeMode.system,
                            ThemeMode.dark,
                          ][i],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── The daily letter ───────────────────────────────────────────
            group(
              'letter',
              KitRowList(
                rows: [
                  KitSettingRow(
                    icon: Icons.mail_outline,
                    title: 'Delivery & composition',
                    description:
                        'When your letter arrives, how many passages it '
                        'carries, and which shelves it draws from.',
                    // The link drops under the copy on a phone rather than
                    // taking half the row's width from it.
                    wideControl: true,
                    trailing: [
                      KitSettingLink(
                        'Edit letter settings',
                        onTap: () => context.go('/letters/settings'),
                      ),
                    ],
                  ),
                  // The way into Ask — absent while generative AI is off
                  // (5.29.0, ADR-186; api/ai.md §What the switch hides).
                  if (aiOn)
                    KitSettingRow(
                      icon: Icons.chat_bubble_outline,
                      title: 'Your librarian',
                      description:
                          'The voice your library answers in when you ask it '
                          'a question.',
                      trailing: [
                        KitSettingLink(
                          'Open Ask',
                          onTap: () => context.go('/ask'),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // ── Generative AI (5.29.0, ADR-186, INV-34; 5.33.0, ADR-190) ───
            group('ai', _GenerativeAISection(ai: ai)),

            // ── Summaries (4.3.0 + 4.4.0, ADR-040) — absent while off ──────
            if (aiOn) group('summaries', const SummariesSection()),

            // ── Scripture (2.28.0, ADR-027 §7) ─────────────────────────────
            //
            // Client-local and per-device BY CONTRACT: the Scripture shelf and
            // verse search are affordances, not account state, so a second
            // device decides for itself. The readings LETTER is the opposite —
            // contract state on its own settings document — which is why it
            // is configured on Letters and only pointed at from here.
            group(
              'scripture',
              ValueListenableBuilder<bool>(
                valueListenable: LocalFlags.scripture,
                builder: (context, on, _) => KitRowList(
                  rows: [
                    KitSettingRow(
                      icon: Icons.menu_book_outlined,
                      title: 'Verse search',
                      description:
                          'Turns a citation like Mt 16:24-28 into a '
                          'verse-by-verse read of the passage, with the notes '
                          'and books on your shelves that answer each verse.',
                      trailing: [
                        KitSwitch(
                          value: on,
                          tooltip: 'Verse search',
                          // Write before you move: the preference is stored,
                          // then the switch follows. A control that flips
                          // first reverts only on reload, which is the
                          // failure nobody sees.
                          onChanged: (next) => LocalFlags.setScripture(next),
                        ),
                      ],
                    ),
                    if (on)
                      KitSettingRow(
                        icon: Icons.mail_outline,
                        title: 'The readings letter',
                        description:
                            'A second letter carrying the day’s Mass '
                            'readings. It has its own schedule and recipient, '
                            'so it is set up with your letters rather than '
                            'here.',
                        trailing: [
                          KitSettingLink(
                            'Open Letters',
                            onTap: () => context.go('/letters'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            // ── Notifications (2.5.0, ADR-014) ─────────────────────────────
            group(
              'notifications',
              KitRowList(
                rows: [
                  KitSettingRow(
                    icon: Icons.notifications_none,
                    title: 'Channels',
                    description:
                        'How you hear about what NoteLetter does — on-screen '
                        'or by email, at the severity you choose.',
                    trailing: [
                      KitSettingLink(
                        'Manage channels',
                        onTap: () => context.go('/settings/notifications'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Sources (settings.md §Sources section, ruled 2026-10-09) ────
            // The auto-organization settings' one home, between Notifications
            // and Account, as the reference orders it, and only while a
            // provider is connected: the section draws its head with itself.
            // Mounted either way — it is what reads the integrations.
            SourcesSection(
              focus: widget.focusSources,
              head: sourcesShown
                  ? KitDSetGroup(
                      n: ids.indexOf('sources'),
                      title: 'Sources',
                      headKey: _sec.keyOf('sources'),
                    )
                  : null,
            ),

            // ── Account ────────────────────────────────────────────────────
            group(
              'account',
              KitRowList(
                rows: [
                  const _PlanRow(),
                  KitSettingRow(
                    icon: Icons.person_outline,
                    leading: KitAvatarPlate(KitAvatarPlate.initialsOf(who)),
                    title: named ? user!.displayName! : 'Your account',
                    description: user?.email,
                    trailing: [
                      KitSettingLink(
                        'Sign out',
                        icon: Icons.logout,
                        onTap: signOut,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const KitBuildStamp(
              contract: BuildInfo.contractPin,
              platform: BuildInfo.platform,
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings → Generative AI (5.29.0, ADR-186, INV-34; settings.md §Generative
/// AI section) and its second row, Video reading (5.33.0, ADR-190, INV-36),
/// both read off the ONE app-wide [AiSettingsNotifier].
///
/// **Write before you move.** The switch draws what the subscription last
/// delivered, is held while `fn_ai_settings` PUT `{generativeAI}` is out, and
/// moves only when the stored value comes back; a refusal leaves it where it
/// was, with the server's sentence under the row (§14.2). Video reading is
/// the same over `{videoAI}` alone, and a press on the selected option sends
/// nothing.
///
/// **Unread / failed** (INV-24): no switch until the first snapshot, and a
/// failed subscription is a §14.1 block in the switch row's control cluster —
/// never a switch at a guessed position. Video reading draws no control then,
/// and no failure of its own: one subscription, one failure, said once.
class _GenerativeAISection extends StatelessWidget {
  final AiSettingsNotifier? ai;

  const _GenerativeAISection({required this.ai});

  @override
  Widget build(BuildContext context) {
    final ai = this.ai;
    final genAI = ai?.genAI ?? GenAI.loading;
    final video = ai?.videoAI ?? VideoAI.loading;
    return KitRowList(
      rows: [
        KitSettingRow(
          icon: KitSparkle.icon,
          title: 'Generative AI',
          description: SettingsPage.aiDescription,
          caption: genAI == GenAI.off ? SettingsPage.aiOffCaption : null,
          alignTop: false,
          wideControl: genAI == GenAI.failed,
          below: ai?.aiError == null ? null : KitFailureInline(ai!.aiError!),
          trailing: [
            if (genAI == GenAI.failed)
              KitFailureBlock(
                sentence: 'Your generative-AI setting could not be read.',
                detail: ai?.error ?? '',
                onRetry: ai?.start,
              )
            else if (ai != null && (genAI == GenAI.on || genAI == GenAI.off))
              KitSwitch(
                key: SettingsPage.aiSwitchKey,
                value: genAI == GenAI.on,
                tooltip: 'Generative AI',
                onChanged: ai.aiBusy ? null : (v) => ai.setGenerativeAI(v),
              ),
          ],
        ),
        KitSettingRow(
          icon: Icons.play_arrow_outlined,
          title: 'Video reading',
          description: SettingsPage.videoDescription,
          alignTop: false,
          // §6.8/§34 stacks under the copy below 768 (CLAUDE.md §Composition
          // deviations): beside it on a phone the description ran to a
          // two-word measure.
          wideControl: true,
          below: ai?.videoError == null
              ? null
              : KitFailureInline(ai!.videoError!),
          trailing: [
            if (ai != null &&
                (video == VideoAI.openai || video == VideoAI.claude))
              KitSlideSwitch<VideoAI>(
                key: SettingsPage.videoKey,
                label: 'Video reading',
                value: video,
                held: ai.videoBusy,
                options: const [
                  KitSlideOption(VideoAI.openai, 'OpenAI'),
                  KitSlideOption(VideoAI.claude, 'Claude'),
                ],
                onChanged: (v) => ai.setVideoAI(v),
              ),
          ],
        ),
      ],
    );
  }
}

/// The Plan row (4.79.0, ADR-113, INV-28 — `screens/settings.md` §Plan row).
///
/// Three rules, each of which is a way to get this wrong:
///
///  * **Every figure comes from `fn_plan_status`.** This client already
///    shipped one fabricated figure (F-00); a count of the documents
///    subscription is a number nothing checked, and §12 is explicit that a
///    notice is measured, not decorative.
///  * **Unread is not zero** (ADR-109). Until the endpoint answers, the title
///    is `Plan` and there are NO figures — never `0 of 100`.
///  * **A failed read is a §14.1 failure block in the control cluster**, never
///    zeros (INV-24). The sentence is ours, the detail is the server's.
///
/// It refetches on [PlanLimitSignal] — a refusal anywhere in the app means the
/// figures here are stale — and never learns a number from the refusal itself.
class _PlanRow extends StatefulWidget {
  const _PlanRow();

  @override
  State<_PlanRow> createState() => _PlanRowState();
}

class _PlanRowState extends State<_PlanRow> {
  Map<String, dynamic>? _status;
  ApiException? _err;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = PlanLimitSignal.stream.listen((_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    // Write before move: the request is awaited, and only then does state
    // change. Clearing `_status` first would blank a row that is still correct
    // every time a refusal arrived.
    try {
      final s = await Api.instance.getPlanStatus();
      if (!mounted) return;
      setState(() {
        _status = s;
        _err = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _err = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = planSummary(_status);
    final err = _err;
    return KitSettingRow(
      icon: Icons.menu_book_outlined,
      title: summary.title,
      description: summary.description,
      trailing: [
        if (err != null)
          KitFailureBlock(
            sentence: 'Your plan could not be read.',
            detail: err.message,
            requestId: err.requestId,
            onRetry: _load,
          ),
      ],
      wideControl: err != null,
      // §12 under the row, inside the row's own width: the condition the
      // backend measured, with ONE action. There is no checkout, so the
      // honest action is the support thread (§13). No dismiss — the notice
      // leaves when the endpoint says the condition ended.
      below: summary.notice == null
          ? null
          : KitNotice(
              // The glyph is the pattern's own (kit_notice.dart).
              text: summary.notice!,
              actionLabel: 'Ask about upgrading',
              onAction: () => context.go('/support'),
            ),
    );
  }
}
