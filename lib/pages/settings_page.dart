import 'package:flutter/material.dart' show Icons, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../build_info.dart';
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
                trailing: [
                  KitSettingLink('Open letter settings',
                      onTap: () => context.go('/letters/settings')),
                ],
              ),
            ],
          ),

          // ── Summaries (4.3.0 + 4.4.0, ADR-040) ────────────────────────
          const SummariesSection(),

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
