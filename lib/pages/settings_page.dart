import 'package:flutter/material.dart' show Icons, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../build_info.dart';
import '../shared/local_flags.dart';
import '../state/auth_notifier.dart';
import '../state/theme_notifier.dart';
import '../theme/app_spacing.dart';
import '../widgets/kit/kit.dart';
import 'settings/summaries_section.dart';

/// Settings (`spec/screens/settings.md` §Composition, ADR-041).
///
/// Reading frame (760) inside a scroll container · chapter opening (§2.1)
/// with the `Account · {email}` folio · sections opened by §3 headers, each a
/// raised row list of setting rows (`kit_rows.dart`) · segmented controls
/// (§6.8) in the control strips · the build stamp last.
///
/// The letter's own form is NOT here: it is `/letters/settings`, as the
/// reference has it (F-05 moved it rather than copying it). This screen keeps
/// one row through to it, so the way in from Settings survives the move. The
/// "Run through setup again" row lands with F-14.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    LocalFlags.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final themeN = context.watch<ThemeNotifier>();
    final user = context.watch<AuthNotifier>().user;
    final who = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!
        : (user?.email ?? '');

    return KitPage(
      width: KitFrameWidth.reading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChapterOpening(
            folio: 'Account · $who',
            title: 'Settings',
            standfirst:
                'How NoteLetter looks, how your letter behaves, and where '
                'your account stands.',
          ),

          // ── Appearance ────────────────────────────────────────────────
          const SectionHeader('Appearance', first: true),
          KitRowList(
            raised: true,
            rows: [
              KitSettingRow(
                icon: Icons.wb_sunny_outlined,
                title: 'Theme',
                description:
                    'Light, dark, or follow your system. The plum chrome '
                    'stays warm either way.',
                wideControl: true,
                trailing: [
                  KitSegmented(
                    segments: const [
                      KitSegment('Light', icon: Icons.wb_sunny_outlined),
                      KitSegment('System', icon: Icons.desktop_windows_outlined),
                      KitSegment('Dark', icon: Icons.dark_mode_outlined),
                    ],
                    selected: switch (themeN.themeMode) {
                      ThemeMode.light => 0,
                      ThemeMode.system => 1,
                      ThemeMode.dark => 2,
                    },
                    onChanged: (i) => themeN.setMode(const [
                      ThemeMode.light,
                      ThemeMode.system,
                      ThemeMode.dark,
                    ][i]),
                  ),
                ],
              ),
            ],
          ),

          // ── The letter ────────────────────────────────────────────────
          const SectionHeader('The letter'),
          KitRowList(
            raised: true,
            rows: [
              KitSettingRow(
                icon: Icons.mail_outline,
                title: 'Letter settings',
                description:
                    'When your letter arrives, who it goes to, what it draws '
                    'from — and the readings letter beside it.',
                // The link drops under the copy on a phone rather than taking
                // half the row's width from it.
                wideControl: true,
                trailing: [
                  KitSettingLink('Open letter settings',
                      onTap: () => context.go('/letters/settings')),
                ],
              ),
            ],
          ),

          // ── Summaries (4.3.0 + 4.4.0, ADR-040) ────────────────────────
          const SummariesSection(),

          // ── Scripture (2.28.0, ADR-027 §7) ────────────────────────────
          //
          // Client-local and per-device BY CONTRACT: the Scripture shelf and
          // verse search are affordances, not account state, so a second
          // device decides for itself. The readings LETTER is the opposite —
          // contract state on its own settings document — which is why it is
          // configured on Letters and only pointed at from here.
          const SectionHeader('Scripture'),
          ValueListenableBuilder<bool>(
            valueListenable: LocalFlags.scripture,
            builder: (context, on, _) => KitRowList(
              raised: true,
              rows: [
                KitSettingRow(
                  icon: Icons.menu_book_outlined,
                  title: 'Verse search',
                  description:
                      'Turns a citation like Mt 16:24-28 into a verse-by-verse '
                      'read of the passage, with the notes and books on your '
                      'shelves that answer each verse.',
                  trailing: [
                    KitSwitch(
                      value: on,
                      tooltip: 'Verse search',
                      // Write before you move: the preference is stored, then
                      // the switch follows. A control that flips first reverts
                      // only on reload, which is the failure nobody sees.
                      onChanged: (next) => LocalFlags.setScripture(next),
                    ),
                  ],
                ),
                if (on)
                  KitSettingRow(
                    icon: Icons.mail_outline,
                    title: 'The readings letter',
                    description:
                        'A second letter carrying the day’s Mass readings. It '
                        'has its own schedule and recipient, so it is set up '
                        'with your letters rather than here.',
                    trailing: [
                      KitSettingLink('Open letter settings',
                          onTap: () => context.go('/letters/settings')),
                    ],
                  ),
              ],
            ),
          ),

          // ── Notifications (2.5.0, ADR-014) ────────────────────────────
          const SectionHeader('Notifications'),
          KitRowList(
            raised: true,
            rows: [
              KitSettingRow(
                icon: Icons.notifications_none,
                title: 'Channels',
                description:
                    'How you hear about what NoteLetter does — on-screen, by '
                    'email or by push, at the severity you choose.',
                trailing: [
                  KitSettingLink('Manage channels',
                      onTap: () => context.go('/settings/notifications')),
                ],
              ),
            ],
          ),

          // ── Account ───────────────────────────────────────────────────
          const SectionHeader('Account'),
          KitRowList(
            raised: true,
            rows: [
              KitSettingRow(
                icon: Icons.person_outline,
                leading: KitAvatarPlate(KitAvatarPlate.initialsOf(who)),
                title: (user?.displayName?.trim().isNotEmpty ?? false)
                    ? user!.displayName!
                    : 'Your account',
                description: user?.email,
                trailing: [
                  KitSettingLink('Sign out',
                      icon: Icons.logout,
                      onTap: () => context.read<AuthNotifier>().signOut()),
                ],
              ),
            ],
          ),

          const KitBuildStamp(
            contract: BuildInfo.contractPin,
            platform: BuildInfo.platform,
          ),
          const SizedBox(height: AppSpacing.s8),
        ],
      ),
    );
  }
}
