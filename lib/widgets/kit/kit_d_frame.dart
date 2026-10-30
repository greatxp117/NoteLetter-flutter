import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_d_parts.dart';
import 'kit_frame.dart' show KitScrollView;
import 'kit_shell.dart' show KitGlyph;
import 'kit_text.dart';

// ── Direction D's frame (component-kit §26–§30) ─────────────────────────────
//
// Every D page composes [KitDPage]: the masthead (§26) with the one toolbar
// (§27), the settings panel (§28), the sheet beside the main column (§29) —
// which on a phone runs as the running head (§30) — and the page's tools
// registered for the app header and the tab bar, which live outside the page.
// Web: `src/kit/d/Page.jsx`, `Masthead.jsx`, `Panel.jsx`, `Sheet.jsx`,
// `pageTools.js`.

// ── §27 Registration ────────────────────────────────────────────────────────

/// The two D scrims (fixed, not paired): the panel's and the running head's.
class AppColorsScrim {
  AppColorsScrim._();
  static const Color panel = AppColors.scrimPanel;
  static const Color sheet = AppColors.scrimSheet;
}

/// The page's ONE action (§27): the only accent button on the page, and the
/// tab bar's centre at 1024 and under, where it draws [short].
class KitPageAction {
  final String label;
  final String short;
  final IconData icon;
  final VoidCallback onPressed;
  final bool disabled;

  const KitPageAction({
    required this.label,
    String? short,
    this.icon = Icons.add,
    required this.onPressed,
    this.disabled = false,
  }) : short = short ?? label;
}

/// The page's settings as it declares them (§28): the panel's [label] (the
/// gear's accessible name), its [body] — handed `close`, so a link inside it
/// to a fuller page may close it — the topics it covers ([has], for
/// [KitPageTools.openSettings]), and [held] while a write is in flight.
class KitPageSettings {
  final String label;
  final Widget Function(BuildContext context, VoidCallback close) body;
  final List<String> has;
  final bool held;

  const KitPageSettings({
    required this.label,
    required this.body,
    this.has = const [],
    this.held = false,
  });
}

/// The settings as the chrome reads them: drawn by the app header's gear.
class KitSettingsHandle {
  final String label;
  final bool open;
  final bool held;
  final List<String> has;
  final VoidCallback toggle;
  final VoidCallback show;

  const KitSettingsHandle({
    required this.label,
    required this.open,
    required this.held,
    required this.has,
    required this.toggle,
    required this.show,
  });
}

/// §27's app-level store: the mounted page writes its action and its
/// settings here, and the app header and tab bar — outside the page — read
/// them. The chrome draws the most recent registrant's (the current route's
/// page); a page's disposal takes its tools away and hands the chrome back to
/// the page still mounted, so a page with no tools leaves the chrome showing
/// none. A control the chrome draws calls the page's LATEST handler, read at
/// the press.
///
/// [scrim] is the dismiss callback of whatever D overlay is open (the panel,
/// the dropped running head): the tab bar draws the overlay's scrim over
/// itself while it is set, as web's scrims cover the tab bar.
class KitPageTools extends ChangeNotifier {
  KitPageTools._();
  static final KitPageTools instance = KitPageTools._();

  KitPageAction? _action;
  KitSettingsHandle? _settings;
  String _key = '#';
  bool _announcing = false;

  /// (dismiss, scrim colour) of the open D overlay, or null.
  final ValueNotifier<(VoidCallback, Color)?> scrim = ValueNotifier(null);

  KitPageAction? get action => _action;
  KitSettingsHandle? get settings => _settings;

  static String _keyOf(KitPageAction? a, KitSettingsHandle? s) =>
      '${a == null ? '' : '${a.label}|${a.short}|${a.disabled}|${a.icon.codePoint}'}'
      '#${s == null ? '' : '${s.label}|${s.open}|${s.held}'}';

  /// Every mounted page that has registered, the most recent last: the
  /// chrome draws the LAST one's tools. A stack, not one slot, because a
  /// route change can have the outgoing page register AFTER the incoming
  /// one. Home sits in the inner shell's navigator, where its own route still
  /// reads as current while the outer navigator replaces it with the source
  /// page; Home re-registered during the transition, then disposed and
  /// cleared the slot — and the source page, which had nothing to rebuild
  /// it, drew no gear and no centre action (F-142's device holds, traced
  /// 2026-10-30). Removing the leaving page now hands the chrome back to the
  /// page that is still mounted.
  final List<(Object, KitPageAction?, KitSettingsHandle?)> _live = [];

  /// Store [owner]'s tools now (so a press reads the latest handler) and tell
  /// the chrome after the frame when something it draws changed.
  void register(Object owner, KitPageAction? action, KitSettingsHandle? s) {
    _live.removeWhere((e) => identical(e.$1, owner));
    _live.add((owner, action, s));
    _apply();
  }

  /// [owner]'s page is gone: take what it wrote away. If it was the one the
  /// chrome drew, the most recent page still mounted takes its place.
  void clear(Object owner) {
    final before = _live.length;
    _live.removeWhere((e) => identical(e.$1, owner));
    if (_live.length != before) _apply();
  }

  void _apply() {
    final top = _live.isEmpty ? null : _live.last;
    _action = top?.$2;
    _settings = top?.$3;
    final k = _keyOf(_action, _settings);
    if (k != _key) {
      _key = k;
      _announce();
    }
  }

  /// A link on the page naming its own settings opens the panel instead of
  /// leaving (web `openPageSettings`). With [topic], only where the panel
  /// covers it. False when there is no such panel: the caller navigates.
  bool openSettings([String? topic]) {
    final s = _settings;
    if (s == null || (topic != null && !s.has.contains(topic))) return false;
    if (!s.open) s.show();
    return true;
  }

  void _announce() {
    if (_announcing) return;
    _announcing = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _announcing = false;
      notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @visibleForTesting
  void reset() {
    _live.clear();
    _action = null;
    _settings = null;
    _key = '#';
    scrim.value = null;
  }
}

/// The shell's verbs for kit parts that sit on every page (web `DShellProvider`):
/// Search opens quick search — on this client, the Search screen — and the tab
/// bar's default action opens Add a source.
class KitDShell extends InheritedWidget {
  final VoidCallback openSearch;
  final VoidCallback openAdd;

  const KitDShell({
    super.key,
    required this.openSearch,
    required this.openAdd,
    required super.child,
  });

  static KitDShell? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KitDShell>();

  @override
  bool updateShouldNotify(KitDShell old) =>
      old.openSearch != openSearch || old.openAdd != openAdd;
}

// ── §26 Masthead ────────────────────────────────────────────────────────────

/// §26 — the edition's masthead: the **rail** (the folio, or a crumb — the §39
/// back control, then the folio — and at its trailing edge the page's tools),
/// the **title** (display serif; a `*clause*` is the accent italic clause), an
/// optional italic **standfirst**, and the **double rule**. At 1024 and under
/// the tools leave the rail (the chrome carries them) and on a phone the folio
/// wraps instead of truncating.
class KitMasthead extends StatelessWidget {
  final String folio;
  final Widget? back;
  final Widget? tools;
  final String title;
  final String? stand;

  /// A title still being read (the source page's cold open): drawn in the
  /// title's place, e.g. a skeleton line.
  final Widget? titleWidget;

  /// What stands under the title in place of (or after) a standfirst, before
  /// the rule — the source page's byline and its freshness notice (W2's
  /// `byline` slot).
  final Widget? byline;

  /// On a phone the crumb stacks: the back control, then the folio UNDER it,
  /// 16 above the title (the source page's phone order, `screens/reader.md`
  /// §Composition). Elsewhere the crumb runs on one line.
  final bool crumbStacks;

  const KitMasthead({
    super.key,
    required this.folio,
    required this.title,
    this.back,
    this.tools,
    this.stand,
    this.titleWidget,
    this.byline,
    this.crumbStacks = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final phone = KitD.phone(context);
    return LayoutBuilder(
      builder: (context, c) {
        final cw = c.maxWidth;
        final folioText = Text(
          folio.toUpperCase(),
          maxLines: phone ? null : 1,
          overflow: phone ? null : TextOverflow.ellipsis,
          style: AppTheme.mono(
            fontSize: 11,
            height: phone ? 18 / 11 : null,
            letterSpacing: 0.18 * 11,
            color: t.accentText,
          ),
        );
        // The crumb: the back control's 8px of side padding is taken back out,
        // as web's `margin: -14px -8px` does, so its text sits on the edge.
        final stacked = back != null && phone && crumbStacks;
        final lead = back == null
            ? folioText
            : stacked
            // The back control's 44px hit area overhangs the line it draws
            // on by 14 above and below (web's `margin: -14px -8px`), so its
            // visible line is 16 tall and the folio wraps under it.
            ? Stack(
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 22),
                    // A source that could not be read has no folio: the back
                    // control stands alone.
                    child: folio.isEmpty
                        ? const SizedBox(width: double.infinity)
                        : SizedBox(width: double.infinity, child: folioText),
                  ),
                  Positioned(left: -8, top: -14, child: back!),
                ],
              )
            : Row(
                children: [
                  Transform.translate(offset: const Offset(-8, 0), child: back),
                  Flexible(child: folioText),
                ],
              );
        Widget rail;
        final tl = tools;
        if (tl == null) {
          rail = lead;
        } else if (cw >= 960) {
          rail = Row(
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: math.max(0, cw - 364)),
                  child: lead,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 600,
                      minWidth: 340,
                    ),
                    child: tl,
                  ),
                ),
              ),
            ],
          );
        } else {
          rail = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              lead,
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: cw <= KitD.regNarrow ? cw : math.min(600, cw),
                  child: tl,
                ),
              ),
            ],
          );
        }
        // A crumb's 44px hit area: its 14 above and below come back out of the
        // rail's own spacing (web's negative margins).
        final crumb = back != null;
        final pad = stacked ? 16.0 : (phone ? 18.0 : 28.0);
        final titleSize = phone ? 40.0 : (0.05 * cw).clamp(44.0, 80.0);
        final titleStyle = AppTheme.serif(
          fontSize: titleSize,
          height: phone ? 1.02 : 0.98,
          fontWeight: FontWeight.w600,
          letterSpacing: (phone ? -0.028 : -0.03) * titleSize,
          color: t.fg,
          opsz: 60,
        ).copyWith(shadows: AppShadows.letterpress);
        final emStyle = AppTheme.serif(
          fontSize: titleSize,
          height: phone ? 1.02 : 0.98,
          fontWeight: FontWeight.w500,
          fontStyle: FontStyle.italic,
          letterSpacing: (phone ? -0.028 : -0.03) * titleSize,
          color: t.accent,
          opsz: 60,
        ).copyWith(shadows: AppShadows.letterpress);
        final parts = title.split('*');
        final standStyle = AppTheme.serif(
          fontSize: phone ? 17 : 19,
          height: (phone ? 27 : 30) / (phone ? 17 : 19),
          fontStyle: FontStyle.italic,
          color: t.fgLede,
          opsz: 20,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(
                bottom: stacked ? pad : (crumb ? math.max(0, pad - 28) : pad),
              ),
              child: Transform.translate(
                offset: Offset(0, crumb && !stacked ? -14 : 0),
                child: rail,
              ),
            ),
            if (titleWidget != null)
              titleWidget!
            else
            Semantics(
              header: true,
              child: Text.rich(
                TextSpan(
                  style: titleStyle,
                  children: [
                    for (var i = 0; i < parts.length; i++)
                      TextSpan(
                        text: parts[i],
                        style: i.isOdd && parts.length >= 3 ? emStyle : null,
                      ),
                  ],
                ),
              ),
            ),
            if (stand != null && stand!.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: phone ? 14 : 18),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 72 * KitText.ch(context, standStyle),
                    ),
                    child: Text(stand!, style: standStyle),
                  ),
                ),
              ),
            ?byline,
            Container(
              height: 6,
              margin: EdgeInsets.only(top: phone ? 22 : 30),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: t.fg, width: 2),
                  bottom: BorderSide(color: t.fg, width: 1),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── §27 The one toolbar ─────────────────────────────────────────────────────

/// §27 — the rail's tools in their one order: Search (or the page's own field,
/// on Search itself), any extra rail actions, the page's one action, its
/// settings. Drawn only wider than 1024 ([KitDPage] decides).
class KitPageToolbar extends StatelessWidget {
  final VoidCallback? onSearch;
  final Widget? field;
  final List<Widget> actions;
  final KitPageAction? action;
  final KitSettingsHandle? settings;
  final Key? settingsKey;

  const KitPageToolbar({
    super.key,
    this.onSearch,
    this.field,
    this.actions = const [],
    this.action,
    this.settings,
    this.settingsKey,
  });

  @override
  Widget build(BuildContext context) {
    final lead =
        field ?? (onSearch == null ? null : KitSearchField(onOpen: onSearch!));
    final rest = <Widget>[
      ...actions,
      if (action != null) KitActionButton(action: action!),
      if (settings != null)
        KitSettingsButton(key: settingsKey, settings: settings!),
    ];
    return Row(
      children: [
        if (lead != null) Expanded(child: lead) else const Spacer(),
        for (final w in rest) ...[const SizedBox(width: 10), w],
      ],
    );
  }
}

/// §27's Search: a control shaped like a field (not an input) that opens quick
/// search — a leading glyph and the italic serif placeholder. This client
/// binds no keys, so it draws no `⌘K` hint (touch copy, CLAUDE.md).
class KitSearchField extends StatelessWidget {
  final VoidCallback onOpen;
  final String placeholder;

  const KitSearchField({
    super.key,
    required this.onOpen,
    this.placeholder = 'Search your library by meaning…',
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return KitDTap(
      onTap: onOpen,
      label: placeholder,
      builder: (context, hover, focus) => AnimatedContainer(
        duration: KitD.dur(context, AppMotion.durBase),
        curve: AppMotion.easeOut,
        height: 44,
        padding: const EdgeInsets.fromLTRB(15, 0, 9, 0),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: AppRadius.controlR(44),
          border: Border.all(
            color: focus ? t.accent : (hover ? t.borderStrong : t.border),
            width: focus ? 2 : 1,
          ),
          boxShadow: hover ? AppShadows.s2 : null,
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 17, color: t.fgMuted),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                placeholder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KitText.lede(
                  context,
                  fontSize: 16,
                  height: 20,
                  color: t.fgSubtle,
                  opsz: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// §27's page action: the ONLY §6.1 primary on the page — 44 tall, its glyph
/// (15) and label. Held at `--held-opacity` while disabled, here and at the
/// tab bar's centre alike.
class KitActionButton extends StatelessWidget {
  final KitPageAction action;
  const KitActionButton({super.key, required this.action});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Opacity(
      opacity: action.disabled ? AppSpacing.heldOpacity : 1,
      child: KitDTap(
        onTap: action.disabled
            ? null
            : () => (KitPageTools.instance.action ?? action).onPressed(),
        label: action.label,
        builder: (context, hover, focus) => Container(
          height: 44,
          padding: const EdgeInsets.fromLTRB(14, 0, 16, 0),
          decoration: BoxDecoration(
            color: hover ? t.accentHover : t.accent,
            borderRadius: AppRadius.controlR(44),
            border: focus ? Border.all(color: t.fg, width: 2) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              KitGlyph(action.icon, size: 15, color: t.accentFg),
              const SizedBox(width: 8),
              Text(
                action.label,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: AppTheme.fontSans,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: t.accentFg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// §27's page settings: a gear named by the settings' label. It never
/// navigates — it opens the page's §28 panel. Open: the glyph and its ring go
/// accent. Held: the whole control at `--held-opacity`, no pointer events.
/// [chrome]: the app header's 36px form on the plum chrome (§30), raised while
/// the panel is open.
class KitSettingsButton extends StatelessWidget {
  final KitSettingsHandle settings;
  final bool chrome;

  const KitSettingsButton({
    super.key,
    required this.settings,
    this.chrome = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    void press() => (KitPageTools.instance.settings ?? settings).toggle();
    final tap = KitDTap(
      onTap: settings.held ? null : press,
      label: settings.label,
      expanded: settings.open,
      builder: (context, hover, focus) {
        if (chrome) {
          return Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: settings.open
                  ? t.chromeRaised
                  : (hover ? t.chromeActive : null),
              borderRadius: AppRadius.smR,
              border: focus ? Border.all(color: t.chromeFg, width: 2) : null,
            ),
            child: Icon(
              Icons.settings_outlined,
              size: 20,
              color: settings.open || hover ? t.chromeFg : t.chromeControl,
            ),
          );
        }
        final ring = settings.open ? t.accent : t.borderStrong;
        return Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hover ? Color.alphaBlend(t.hover, t.surface) : t.surface,
            borderRadius: AppRadius.controlR(44),
            border: Border.all(
              color: focus ? t.accent : ring,
              width: focus ? 2 : 1,
            ),
          ),
          child: Icon(
            Icons.settings_outlined,
            size: 18,
            color: settings.open ? t.accent : (hover ? t.fg : t.fgMuted),
          ),
        );
      },
    );
    return Opacity(
      opacity: settings.held ? AppSpacing.heldOpacity : 1,
      child: tap,
    );
  }
}

// ── §28 Settings panel ──────────────────────────────────────────────────────

/// §28 — the settings panel: a dialog named by the settings' label, a head
/// (that label in serif, then *Close*) over a rule, then the body's groups,
/// each under a [KitDLabel] (the first one `top: 18`). Escape, the scrim and
/// the close button close it — the layer [KitDPage] draws it in owns those.
class KitSettingsPanel extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final Widget child;

  const KitSettingsPanel({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.borderStrong)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: AppTheme.serif(
                        fontSize: 19,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: t.fg,
                        opsz: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // `margin-right: -10px`: the close button's ring sits 10 into
                // the panel's padding, so its glyph aligns with the edge.
                Transform.translate(
                  offset: const Offset(10, 0),
                  child: KitDTap(
                    onTap: onClose,
                    label: 'Close',
                    builder: (context, hover, focus) => Container(
                      key: const ValueKey('d-panel-close'),
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: hover ? t.hover : null,
                        shape: BoxShape.circle,
                        border: focus
                            ? Border.all(color: t.accent, width: 2)
                            : null,
                      ),
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: hover ? t.fg : t.fgMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// Escape closes what is open: a D overlay's key handler.
class _EscapeCloses extends StatelessWidget {
  final VoidCallback onEscape;
  final Widget child;
  const _EscapeCloses({required this.onEscape, required this.child});

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (node, e) {
      if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
        onEscape();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );
}

// ── §29 Sheet and its parts ─────────────────────────────────────────────────

/// What a page puts in its sheet (§29): its accessible [label] (Home's *On this
/// page*), the [peek] its phone form says — declared, never derived — and the
/// [body] (the lead, Figures, Also, in that order). [foldOnPick]: choosing a
/// Contents or Facet row folds the running head (web `foldOn`).
class KitDSheet {
  final String label;
  final Widget peek;
  final Widget body;
  final bool foldOnPick;

  /// Drawn along the running head line's foot, inset 18 each side — the
  /// source page's 2px reading-progress rule (`screens/reader.md`; web
  /// `.d-peek-prog`). The page's own; nothing else draws one.
  final Widget? foot;

  const KitDSheet({
    required this.label,
    required this.peek,
    required this.body,
    this.foldOnPick = false,
    this.foot,
  });
}

/// The sheet's form, for the parts inside it: [lines] (Facet rows run as
/// lines — a stacked sheet or the dropped running head), [dock] (the running
/// head: Contents rows 11, Facet rows 10), and [pick], which folds the
/// running head when the page asked.
class KitSheetScope extends InheritedWidget {
  final bool lines;
  final bool dock;
  final VoidCallback? onPick;

  const KitSheetScope({
    super.key,
    this.lines = false,
    this.dock = false,
    this.onPick,
    required super.child,
  });

  static KitSheetScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KitSheetScope>();

  static void pick(BuildContext context) =>
      context.getInheritedWidgetOfExactType<KitSheetScope>()?.onPick?.call();

  @override
  bool updateShouldNotify(KitSheetScope old) =>
      old.lines != lines || old.dock != dock || old.onPick != onPick;
}

/// §29 — which section the reader is in, and the way to one (web
/// `useSections`). Give each [KitSecHead] (or section) `key: keyOf(id)`;
/// [current] is the section nearest the top of the page's scroller — the
/// last once the scroll reaches its end — and [jump] scrolls the primary
/// scroller smoothly to a section, 24px above it. [KitDPage] attaches it.
///
/// **Mounting on approach** (the source page, `screens/reader.md` §Continuous
/// scroll; web `useSectionRail`): given [eager], only those sections are
/// mounted at first, and every other one mounts once its top comes within
/// [near] of the viewport's foot — never on a click, so scrolling guarantees
/// it. It only ever grows. A jump mounts everything up to and including its
/// target BEFORE it scrolls: a section whose predecessors are still reserves
/// is at the wrong offset.
///
/// **A landed jump is held** until the reader's own hand scrolls: a browser
/// keeps a landed jump where it landed when content ABOVE it changes size
/// (scroll anchoring) and Flutter does not, so a page whose sections answer
/// late calls [reanchor] when one changes size, and [release] on a drag
/// (F-77 found the target ~90px off after Original's answer grew).
class KitSections extends ChangeNotifier {
  KitSections(this._ids, {Iterable<String>? eager})
    : _mounted = eager == null ? null : {...eager};

  List<String> _ids;
  final Map<String, GlobalKey> _keys = {};
  String? _current;
  ScrollController? _sc;
  bool _pending = false;
  bool _still = false;

  /// Null: every section is mounted (a page with no lazy sections).
  final Set<String>? _mounted;

  /// How far below the viewport a section starts mounting (web `NEAR`).
  static const double near = 800;

  /// The section a jump landed on, held until [release].
  String? _held;

  bool isMounted(String id) => _mounted == null || _mounted.contains(id);

  /// Mount [ids] now (a jump, a deep link into a section).
  void mount(Iterable<String> ids) {
    final m = _mounted;
    if (m == null) return;
    final before = m.length;
    m.addAll(ids);
    if (m.length != before) {
      notifyListeners();
      _schedule();
    }
  }

  /// The reader's own hand moved the page: a held jump is let go.
  void release() => _held = null;

  /// Something above a held jump changed size: put its section back 24 under
  /// the top, at once (never mid-animation).
  void reanchor() {
    final id = _held;
    final sc = _sc;
    if (id == null || sc == null || !sc.hasClients) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_held != id || !sc.hasClients) return;
      if (sc.position.isScrollingNotifier.value) return;
      final top = _top(id);
      if (top == null) return;
      final p = sc.position;
      final to = (p.pixels + top - 24).clamp(
        p.minScrollExtent,
        p.maxScrollExtent,
      );
      if ((to - p.pixels).abs() > 0.5) sc.jumpTo(to);
    });
  }

  List<String> get ids => _ids;
  set ids(List<String> v) {
    _ids = v;
    _schedule();
  }

  String? get current => _current != null && _ids.contains(_current)
      ? _current
      : (_ids.isEmpty ? null : _ids.first);

  int get index => math.max(0, _ids.indexOf(current ?? ''));

  GlobalKey keyOf(String id) =>
      _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'dsec-$id'));

  void attach(ScrollController sc, {bool still = false}) {
    _still = still;
    if (identical(_sc, sc)) return;
    _sc?.removeListener(_schedule);
    _sc = sc;
    sc.addListener(_schedule);
    _schedule();
  }

  void detach(ScrollController sc) {
    if (!identical(_sc, sc)) return;
    sc.removeListener(_schedule);
    _sc = null;
  }

  void _schedule() {
    if (_pending) return;
    _pending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      _read();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  RenderBox? _viewport() {
    final sc = _sc;
    if (sc == null || !sc.hasClients) return null;
    final ro = sc.position.context.storageContext.findRenderObject();
    return ro is RenderBox && ro.attached ? ro : null;
  }

  double? _top(String id) {
    final vp = _viewport();
    final ro = _keys[id]?.currentContext?.findRenderObject();
    if (vp == null || ro is! RenderBox || !ro.attached) return null;
    return ro.localToGlobal(Offset.zero, ancestor: vp).dy;
  }

  void _read() {
    final sc = _sc;
    if (sc == null || !sc.hasClients) return;
    final m = _mounted;
    if (m != null) {
      final reach = sc.position.viewportDimension + near;
      final grow = [
        for (final id in _ids)
          if (!m.contains(id) && (_top(id) ?? double.infinity) < reach) id,
      ];
      if (grow.isNotEmpty) {
        // A section that just mounted moves every one below it: measure
        // again against the new layout, or the cascade stops at whatever
        // fitted first.
        mount(grow);
      }
    }
    final have = _ids.where((id) => _top(id) != null).toList();
    String? on = have.isNotEmpty
        ? have.first
        : (_ids.isEmpty ? null : _ids.first);
    for (final id in have) {
      if (_top(id)! <= 160) on = id;
    }
    final p = sc.position;
    if (have.isNotEmpty &&
        p.pixels >= p.maxScrollExtent - 4 &&
        p.maxScrollExtent > 0) {
      on = have.last;
    }
    if (on != _current) {
      _current = on;
      notifyListeners();
    }
  }

  /// Scroll the page's primary scroller to [id], 24 above it — after
  /// mounting everything up to it, when the page mounts on approach.
  void jump(String id) {
    final m = _mounted;
    if (m != null) {
      final upto = _ids.sublist(0, _ids.indexOf(id) + 1);
      if (!upto.every(m.contains)) {
        mount(upto);
        _held = id;
        _current = id;
        notifyListeners();
        // Laid out first: the offset aimed at is the one it lands in.
        SchedulerBinding.instance.addPostFrameCallback((_) => _scrollTo(id));
        SchedulerBinding.instance.ensureVisualUpdate();
        return;
      }
    }
    _held = id;
    _scrollTo(id);
    _current = id;
    notifyListeners();
  }

  Future<void> _scrollTo(String id) async {
    final sc = _sc;
    final top = _top(id);
    if (sc == null || top == null || !sc.hasClients) return;
    final p = sc.position;
    final to = (p.pixels + top - 24).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    if (_still) {
      sc.jumpTo(to);
    } else {
      await sc.animateTo(
        to,
        duration: AppMotion.durSlow,
        curve: AppMotion.easeQuill,
      );
    }
    // Whatever grew above it while the scroll ran, it lands where it said.
    reanchor();
  }

  @override
  void dispose() {
    _sc?.removeListener(_schedule);
    super.dispose();
  }
}

/// One row of [KitContents]: a section the page ACTUALLY draws.
class KitContentsItem {
  final String id;
  final String label;
  final String? count;
  const KitContentsItem(this.id, this.label, {this.count});
}

/// §29's lead where the page has sections — **Contents**: one row per section,
/// its italic numeral, its title in serif, an optional count; the current one
/// `--fg` 600 with a 6px accent dot in its leading margin. A row scrolls the
/// page to its section (and folds the running head where the page asked).
class KitContents extends StatelessWidget {
  final List<KitContentsItem> items;
  final KitSections sections;
  final String label;

  /// The page's own jump, when it does more than [KitSections.jump] (the
  /// source page counts a deliberate move to a section: `reader_mode_used`).
  final ValueChanged<String>? onJump;

  const KitContents({
    super.key,
    required this.items,
    required this.sections,
    this.label = 'Contents',
    this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final dock = KitSheetScope.maybeOf(context)?.dock ?? false;
    return ListenableBuilder(
      listenable: sections,
      builder: (context, _) => Semantics(
        container: true,
        explicitChildNodes: true,
        label: label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++)
              Builder(
                builder: (context) {
                  final it = items[i];
                  final on = sections.current == it.id;
                  return KitDTap(
                    label: '${KitD.numeral(i)} ${it.label}',
                    selected: on,
                    onTap: () {
                      final j = onJump;
                      j == null ? sections.jump(it.id) : j(it.id);
                      KitSheetScope.pick(context);
                    },
                    builder: (context, hover, focus) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            vertical: dock ? 11 : 9,
                          ),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: t.rule)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              SizedBox(
                                width: 24,
                                child: Text(
                                  KitD.numeral(i),
                                  style: AppTheme.serif(
                                    fontSize: 15,
                                    fontStyle: FontStyle.italic,
                                    color: t.accentText,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: AnimatedDefaultTextStyle(
                                  duration: KitD.dur(
                                    context,
                                    AppMotion.durBase,
                                  ),
                                  style: AppTheme.serif(
                                    fontSize: 16,
                                    fontWeight: on
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: on || hover ? t.fg : t.fgMuted,
                                  ),
                                  child: Text(it.label),
                                ),
                              ),
                              if (it.count != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: t.surfaceSunken,
                                    borderRadius: AppRadius.controlR(20),
                                  ),
                                  child: Text(
                                    it.count!,
                                    style: AppTheme.mono(
                                      fontSize: 9.5,
                                      letterSpacing: 0.08 * 9.5,
                                      color: t.fgMuted,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (on)
                          Positioned(
                            left: -14,
                            top: 0,
                            bottom: 0,
                            child: Center(child: _Dot(color: t.accent)),
                          ),
                        if (focus)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: t.accent, width: 2),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: KitD.dur(context, AppMotion.durBase),
    curve: AppMotion.easeQuill,
    builder: (context, v, _) => Transform.scale(
      scale: v,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    ),
  );
}

/// The running head's line for a Contents sheet (web `SecPeek`):
/// `§ II · Recently added · 2 of 4` — the numeral in accent serif, the
/// section's title in serif, an optional mono caps [meta], the count in mono
/// with ` of {n}` subtler.
class KitSecPeek extends StatelessWidget {
  final List<KitContentsItem> items;
  final KitSections sections;
  final String? meta;

  const KitSecPeek({
    super.key,
    required this.items,
    required this.sections,
    this.meta,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: sections,
      builder: (context, _) {
        final i = math.max(
          0,
          items.indexWhere((s) => s.id == sections.current),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '§ ${KitD.numeral(i)}',
              style: AppTheme.serif(
                fontSize: 16.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.06 * 16.5,
                color: t.accentText,
                opsz: 24,
              ),
            ),
            const SizedBox(width: 9),
            // The section's title takes the line; the count sits at its
            // trailing edge, beside the chevron (`.d-peek-n{margin-left:auto}`).
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      items.isEmpty ? '' : items[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.serif(
                        fontSize: 16.5,
                        height: 22 / 16.5,
                        fontWeight: FontWeight.w600,
                        color: t.fg,
                        opsz: 18,
                      ),
                    ),
                  ),
                  if (meta != null) ...[
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        meta!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.mono(
                          fontSize: 10.5,
                          letterSpacing: 0.12 * 10.5,
                          color: t.fgMuted,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text.rich(
              TextSpan(
                text: '${i + 1}',
                style: AppTheme.mono(fontSize: 11.5, color: t.fg),
                children: [
                  TextSpan(
                    text: ' of ${items.length}',
                    style: AppTheme.mono(fontSize: 11.5, color: t.fgSubtle),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One choice of a [KitFacet].
class KitFacetItem {
  final String id;
  final String label;
  final String? count;
  final bool disabled;
  const KitFacetItem(this.id, this.label, {this.count, this.disabled = false});
}

/// §29's lead where the page narrows what it shows — **Filters**: an optional
/// mono caps label, then one serif row per choice with an optional mono count;
/// exactly one chosen (`--fg` 600, the accent dot). A choice may be held.
/// Pressing the chosen one does nothing. A stacked sheet and the dropped
/// running head run the rows as lines.
class KitFacet extends StatelessWidget {
  final String? label;
  final List<KitFacetItem> items;
  final String value;
  final ValueChanged<String> onChanged;
  final bool first;

  const KitFacet({
    super.key,
    this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    this.first = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final scope = KitSheetScope.maybeOf(context);
    final lines = scope?.lines ?? false;
    final dock = scope?.dock ?? false;
    Widget row(KitFacetItem it) {
      final on = it.id == value;
      return Opacity(
        opacity: it.disabled ? AppSpacing.heldOpacity : 1,
        child: KitDTap(
          label: it.label,
          selected: on,
          enabled: !it.disabled,
          onTap: () {
            if (on) return;
            onChanged(it.id);
            KitSheetScope.pick(context);
          },
          builder: (context, hover, focus) {
            final text = Row(
              mainAxisSize: lines ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  fit: lines ? FlexFit.loose : FlexFit.tight,
                  child: AnimatedDefaultTextStyle(
                    duration: KitD.dur(context, AppMotion.durBase),
                    style: AppTheme.serif(
                      fontSize: 16,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                      color: on || hover ? t.fg : t.fgMuted,
                    ),
                    child: Text(it.label),
                  ),
                ),
                if (it.count != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    it.count!,
                    style: AppTheme.mono(fontSize: 11, color: t.fgSubtle),
                  ),
                ],
              ],
            );
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    vertical: lines ? (dock ? 10 : 6) : 8,
                  ),
                  decoration: lines
                      ? null
                      : BoxDecoration(
                          border: Border(bottom: BorderSide(color: t.rule)),
                        ),
                  child: text,
                ),
                if (on)
                  Positioned(
                    left: -16,
                    top: 0,
                    bottom: 0,
                    child: Center(child: _Dot(color: t.accent)),
                  ),
                if (focus)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: t.accent, width: 2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }

    final rows = lines
        ? Wrap(spacing: 22, children: [for (final it in items) row(it)])
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final it in items) row(it)],
          );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null)
            KitDLabel(label!, first: first, top: dock ? 16 : 22),
          Padding(
            // The chosen dot sits 16 into the margin; a line's first dot
            // needs that room inside the sheet.
            padding: EdgeInsets.only(left: lines ? 16 : 0),
            child: rows,
          ),
        ],
      ),
    );
  }
}

/// A filter page's running head (web `FigurePeek`): `41 sources · 6 shelves` —
/// each figure in italic serif accent, its noun in sans; a null figure is left
/// out, never drawn as 0.
class KitFigurePeek extends StatelessWidget {
  final List<(String?, String)> items;
  const KitFigurePeek({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final shown = items.where((e) => e.$1 != null).toList();
    final noun = TextStyle(
      fontFamily: AppTheme.fontSans,
      fontSize: 13.5,
      color: t.fgMuted,
    );
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0)
              TextSpan(
                text: '  ·  ',
                style: noun.copyWith(color: t.fgSubtle),
              ),
            TextSpan(
              text: '${shown[i].$1} ',
              style: AppTheme.serif(
                fontSize: 21,
                height: 1,
                fontWeight: FontWeight.w500,
                fontStyle: FontStyle.italic,
                color: t.accentText,
                opsz: 60,
              ),
            ),
            TextSpan(text: shown[i].$2, style: noun),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// One row of [KitFigures]: a mono caps [term] beside a serif [value]; [of]
/// is a subtler tail on the value (` of 64`); [meter] a hairline under the
/// row filled in the accent to one count over its own total (the source
/// page's *Passages read 20 of 64*) — never a share of counts that overlap.
class KitFigureRow {
  final String term;
  final String value;
  final String? of;
  final double? meter;
  const KitFigureRow(this.term, this.value, {this.of, this.meter});
}

/// §29's **Figures** — a small ledger of facts about what is open: a mono caps
/// term beside a serif value, ruled. Every value is a measurement (ADR-109):
/// pass `'—'` for unmeasured, and leave out a row the page cannot support.
/// [ledger] takes the rows that carry a tail or a meter (W2's Figures meter).
class KitFigures extends StatelessWidget {
  final List<(String, String)> rows;
  final List<KitFigureRow>? ledger;
  final String? label;

  const KitFigures({super.key, required this.rows, this.label})
    : ledger = null;

  const KitFigures.ledger({
    super.key,
    required List<KitFigureRow> this.ledger,
    this.label,
  }) : rows = const [];

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final all = ledger ?? [for (final r in rows) KitFigureRow(r.$1, r.$2)];
    final valueStyle = AppTheme.serif(fontSize: 15.5, color: t.fg).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null) KitDLabel(label!, first: true),
          for (final r in all)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.rule)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        r.term.toUpperCase(),
                        style: AppTheme.mono(
                          fontSize: 10.5,
                          letterSpacing: 0.12 * 10.5,
                          color: t.fgSubtle,
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          text: r.value,
                          children: [
                            if (r.of != null)
                              TextSpan(
                                text: r.of,
                                style: AppTheme.serif(
                                  fontSize: 14,
                                  color: t.fgSubtle,
                                ),
                              ),
                          ],
                        ),
                        style: valueStyle,
                      ),
                    ],
                  ),
                  if (r.meter != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: ExcludeSemantics(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: SizedBox(
                            height: 3,
                            child: ColoredBox(
                              color: t.surfaceSunken,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: r.meter!.clamp(0.0, 1.0),
                                  heightFactor: 1,
                                  child: ColoredBox(color: t.accent),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// §29's **Also** — the page's quieter actions under *Also*, as full-width
/// ghost rows; a deletion ([KitAlsoButton.danger]) is the only one in
/// `--critical-text` and always last. With no actions nothing is drawn.
class KitSheetAlso extends StatelessWidget {
  final List<Widget> children;
  final String label;

  const KitSheetAlso({super.key, required this.children, this.label = 'Also'});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [KitDLabel(label), ...children],
    );
  }
}

/// One quiet action in [KitSheetAlso]: 40 tall, sans 13.5 `--fg-muted`, a
/// rule under; hover `--hover` and `--fg`. Held while [onTap] is null (a
/// cooldown, a write in flight) at `--held-opacity`.
class KitAlsoButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  const KitAlsoButton(
    this.label, {
    super.key,
    this.icon,
    this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Opacity(
      opacity: onTap == null ? AppSpacing.heldOpacity : 1,
      child: KitRowHover(
        onTap: onTap,
        label: label,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.rule)),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                KitGlyph(
                  icon!,
                  size: 15,
                  color: danger ? t.criticalText : t.fgMuted,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 13.5,
                    color: danger ? t.criticalText : t.fgMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// §29's sheet beside the main column: a raised surface card with an
/// accessible name, scrolling inside itself when taller than [maxHeight].
class KitSheetCard extends StatelessWidget {
  final String label;
  final Widget child;
  final double? maxHeight;
  final bool narrow;

  const KitSheetCard({
    super.key,
    required this.label,
    required this.child,
    this.maxHeight,
    this.narrow = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final body = Padding(
      padding: narrow
          ? const EdgeInsets.symmetric(horizontal: 18, vertical: 22)
          : const EdgeInsets.fromLTRB(24, 26, 24, 24),
      child: child,
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: label,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight ?? double.infinity),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: AppRadius.xlR,
          boxShadow: AppShadows.s2,
        ),
        child: ClipRRect(
          borderRadius: AppRadius.xlR,
          child: maxHeight == null
              ? body
              : KitScrollView.secondary(
                  reason: 'the sheet scrolls inside itself (§29)',
                  child: body,
                ),
        ),
      ),
    );
  }
}

/// §30 — the running head: on a phone the sheet leaves the page and runs as
/// ONE line fixed under the app header, saying where the reader is; tapping it
/// drops the sheet down from it, the line staying as its head. The line, the
/// scrim, Escape, or choosing a row the page names folds it. Folded, its body
/// is inert. [KitDPage] places it; the page's scroller starts below the line.
class KitRunningHead extends StatefulWidget {
  final KitDSheet sheet;
  final double maxBodyHeight;

  const KitRunningHead({
    super.key,
    required this.sheet,
    required this.maxBodyHeight,
  });

  @override
  State<KitRunningHead> createState() => _KitRunningHeadState();
}

class _KitRunningHeadState extends State<KitRunningHead> {
  bool _open = false;

  void _set(bool open) {
    if (open == _open) return;
    setState(() => _open = open);
    final tools = KitPageTools.instance;
    if (open) {
      tools.scrim.value = (_fold, AppColorsScrim.sheet);
    } else if (tools.scrim.value?.$1 == _fold) {
      tools.scrim.value = null;
    }
  }

  void _fold() => _set(false);

  @override
  void dispose() {
    final tools = KitPageTools.instance;
    if (tools.scrim.value?.$1 == _fold) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (tools.scrim.value?.$1 == _fold) tools.scrim.value = null;
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final slow = KitD.dur(context, AppMotion.durSlow);
    final bar = AnimatedContainer(
      duration: slow,
      curve: AppMotion.easeQuill,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: _open
            ? const BorderRadius.vertical(bottom: Radius.circular(AppRadius.xl))
            : BorderRadius.zero,
        boxShadow: _open
            ? AppShadows.s3
            : [
                BoxShadow(color: t.border, offset: const Offset(0, 1)),
                BoxShadow(
                  color: AppShadows.ink(0.3),
                  offset: const Offset(0, 10),
                  blurRadius: 18,
                  spreadRadius: -14,
                ),
              ],
      ),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: widget.sheet.label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitDTap(
              key: const ValueKey('d-peek'),
              onTap: () => _set(!_open),
              expanded: _open,
              builder: (context, hover, focus) => Stack(
                children: [
                  Container(
                    constraints: const BoxConstraints(minHeight: 46),
                    padding: const EdgeInsets.fromLTRB(18, 0, 14, 0),
                    decoration: focus
                        ? BoxDecoration(
                            border: Border.all(color: t.accent, width: 2),
                            borderRadius: AppRadius.xlR,
                          )
                        : null,
                    child: Row(
                      children: [
                        Expanded(child: widget.sheet.peek),
                        const SizedBox(width: 10),
                        AnimatedRotation(
                          turns: _open ? 0.5 : 0,
                          duration: slow,
                          curve: AppMotion.easeQuill,
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            size: 18,
                            color: t.fgMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.sheet.foot != null)
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 0,
                      height: 2,
                      child: IgnorePointer(child: widget.sheet.foot!),
                    ),
                ],
              ),
            ),
            ClipRect(
              child: AnimatedAlign(
                duration: slow,
                curve: AppMotion.easeQuill,
                alignment: Alignment.topCenter,
                heightFactor: _open ? 1 : 0,
                child: ExcludeFocus(
                  excluding: !_open,
                  child: ExcludeSemantics(
                    excluding: !_open,
                    child: IgnorePointer(
                      ignoring: !_open,
                      child: Container(
                        constraints: BoxConstraints(
                          maxHeight: widget.maxBodyHeight,
                        ),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: t.rule)),
                        ),
                        child: KitScrollView.secondary(
                          reason: 'the dropped sheet scrolls inside (§30)',
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                            child: KitSheetScope(
                              lines: true,
                              dock: true,
                              onPick: widget.sheet.foldOnPick ? _fold : null,
                              child: widget.sheet.body,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_open,
            child: AnimatedOpacity(
              opacity: _open ? 1 : 0,
              duration: slow,
              curve: AppMotion.easeOut,
              child: GestureDetector(
                key: const ValueKey('d-dock-scrim'),
                behavior: HitTestBehavior.opaque,
                onTap: _fold,
                child: ColoredBox(color: t.scrimSheet),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: _open ? _EscapeCloses(onEscape: _fold, child: bar) : bar,
        ),
      ],
    );
  }
}

// ── The page ────────────────────────────────────────────────────────────────

/// §26–§30 — the D frame every page composes: the masthead (folio or crumb,
/// title, standfirst, rule) with the one toolbar, the sheet beside the main
/// column (one column, the sheet above, when the container is 860 or
/// narrower; the running head on a phone), the settings panel, and the page's
/// tools registered for the chrome. The primary scroller ends with the shell's
/// support footer (INV-22) and is the one [sections] follows.
class KitDPage extends StatefulWidget {
  final String folio;
  final KitDBackControl? back;
  final String title;
  final String? stand;

  /// Search in the toolbar (default) — false hides it.
  final bool search;

  /// Replaces Search with the page's own field (Search's own page).
  final Widget? field;
  final List<Widget> actions;
  final KitPageAction? action;
  final KitPageSettings? settings;

  /// A node between the masthead and the grid.
  final Widget? under;
  final KitDSheet? sheet;
  final KitSections? sections;
  final ScrollController? controller;
  final Widget child;

  /// [KitMasthead.titleWidget], [KitMasthead.byline], [KitMasthead.crumbStacks].
  final Widget? titleWidget;
  final Widget? byline;
  final bool crumbStacks;

  /// The grid's distance under the masthead wider than a phone (§29's 36;
  /// the source page stands its grid 40 under).
  final double gridTop;

  const KitDPage({
    super.key,
    required this.folio,
    required this.title,
    required this.child,
    this.back,
    this.titleWidget,
    this.byline,
    this.crumbStacks = false,
    this.gridTop = 36,
    this.stand,
    this.search = true,
    this.field,
    this.actions = const [],
    this.action,
    this.settings,
    this.under,
    this.sheet,
    this.sections,
    this.controller,
  });

  @override
  State<KitDPage> createState() => _KitDPageState();
}

class _KitDPageState extends State<KitDPage> {
  ScrollController? _own;
  ScrollController get _sc =>
      widget.controller ?? (_own ??= ScrollController());
  final GlobalKey _gear = GlobalKey(debugLabel: 'd-gear');
  final GlobalKey _stack = GlobalKey(debugLabel: 'd-page');
  final GlobalKey _grid = GlobalKey(debugLabel: 'd-grid');
  bool _open = false;

  void _setOpen(bool v) {
    if (v == _open) return;
    setState(() => _open = v);
    final tools = KitPageTools.instance;
    if (v && KitD.chrome(context)) {
      tools.scrim.value = (_close, AppColorsScrim.panel);
    } else if (!v && tools.scrim.value?.$1 == _close) {
      tools.scrim.value = null;
    }
  }

  void _close() => _setOpen(false);

  KitSettingsHandle? _handle() {
    final s = widget.settings;
    if (s == null) return null;
    return KitSettingsHandle(
      label: s.label,
      open: _open,
      held: s.held,
      has: s.has,
      toggle: () => _setOpen(!_open),
      show: () => _setOpen(true),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.sections?.attach(_sc, still: KitD.still(context));
  }

  @override
  void didUpdateWidget(KitDPage old) {
    super.didUpdateWidget(old);
    if (old.sections != widget.sections) {
      old.sections?.detach(_sc);
      widget.sections?.attach(_sc, still: KitD.still(context));
    }
  }

  @override
  void dispose() {
    widget.sections?.detach(_sc);
    final tools = KitPageTools.instance..clear(this);
    if (tools.scrim.value?.$1 == _close) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (tools.scrim.value?.$1 == _close) tools.scrim.value = null;
      });
    }
    _own?.dispose();
    super.dispose();
  }

  /// The panel's place: dropped from the app header at 1024 and under; under
  /// the masthead's gear wider than that.
  Widget _panelLayer(BuildContext context, BoxConstraints c) {
    final t = Tokens.of(context);
    final s = widget.settings!;
    final chrome = KitD.chrome(context);
    final w = c.maxWidth;
    final h = c.maxHeight;
    double top = 0, right = 0, width = w, maxH = h;
    if (!chrome) {
      final gear = _gear.currentContext?.findRenderObject() as RenderBox?;
      final stack = _stack.currentContext?.findRenderObject() as RenderBox?;
      if (gear != null && stack != null && gear.attached) {
        final r = gear.localToGlobal(Offset.zero, ancestor: stack) & gear.size;
        top = r.bottom + 10;
        right = math.max(16, w - r.right);
      } else {
        top = 96;
        right = 32;
      }
      width = math.min(400, w - 32);
      maxH = math.max(200, h - top - 24);
    }
    final panel = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: KitD.dur(context, AppMotion.durBase),
      curve: AppMotion.easeQuill,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, -4 * (1 - v)),
          child: child,
        ),
      ),
      child: Container(
        key: const ValueKey('d-panel'),
        width: width,
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: chrome
              ? const BorderRadius.vertical(
                  bottom: Radius.circular(AppRadius.xl),
                )
              : AppRadius.xlR,
          boxShadow: AppShadows.s3,
        ),
        padding: chrome
            ? const EdgeInsets.fromLTRB(20, 12, 20, 24)
            : const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: KitSettingsPanel(
          title: s.label,
          onClose: _close,
          child: KitScrollView.secondary(
            reason: 'the settings panel scrolls inside itself (§28)',
            child: KitPanelScope(child: s.body(context, _close)),
          ),
        ),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: KitD.dur(context, AppMotion.durBase),
            curve: AppMotion.easeOut,
            builder: (context, v, child) => Opacity(opacity: v, child: child),
            child: GestureDetector(
              key: const ValueKey('d-panel-scrim'),
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: ColoredBox(color: t.scrimPanel),
            ),
          ),
        ),
        Positioned(
          top: top,
          right: chrome ? 0 : right,
          left: chrome ? 0 : null,
          child: _EscapeCloses(onEscape: _close, child: panel),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final handle = _handle();
    if (ModalRoute.of(context)?.isCurrent ?? true) {
      KitPageTools.instance.register(this, widget.action, handle);
    }
    final shell = KitDShell.maybeOf(context);
    final size = MediaQuery.sizeOf(context);
    final phone = size.width <= KitD.phoneMax;
    final chrome = size.width <= KitD.chromeMax;
    final sheet = widget.sheet;
    final padH = phone ? 18.0 : (0.032 * size.width).clamp(20.0, 64.0);
    return KitDScope(
      child: LayoutBuilder(
        key: _stack,
        builder: (context, c) {
          final cw = math.min(c.maxWidth, 1760.0) - 2 * padH;
          final hasTools =
              widget.search ||
              widget.field != null ||
              widget.action != null ||
              handle != null ||
              widget.actions.isNotEmpty;
          final tools = chrome && widget.field == null
              ? null
              : (hasTools
                    ? KitPageToolbar(
                        // Outside a shell the verb is inert, as web's default
                        // context's is — the field still draws.
                        onSearch: widget.search
                            ? (shell?.openSearch ?? () {})
                            : null,
                        field: widget.field,
                        actions: chrome ? const [] : widget.actions,
                        action: chrome ? null : widget.action,
                        settings: chrome ? null : handle,
                        settingsKey: _gear,
                      )
                    : null);
          final masthead = KitMasthead(
            folio: widget.folio,
            back: widget.back == null
                ? null
                : KitDBackControl(
                    widget.back!.label,
                    onTap: widget.back!.onTap,
                    separator: !phone,
                  ),
            tools: tools,
            title: widget.title,
            stand: widget.stand,
            titleWidget: widget.titleWidget,
            byline: widget.byline,
            crumbStacks: widget.crumbStacks,
          );
          Widget grid;
          if (sheet == null || phone) {
            grid = widget.child;
          } else if (cw <= KitD.stackMax) {
            grid = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KitSheetCard(
                  label: sheet.label,
                  narrow: cw <= 560,
                  child: KitSheetScope(lines: true, child: sheet.body),
                ),
                const SizedBox(height: 32),
                widget.child,
              ],
            );
          } else {
            final sheetW = (0.24 * cw).clamp(272.0, 340.0);
            final gap = (0.034 * cw).clamp(32.0, 56.0);
            grid = Row(
              key: _grid,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: sheetW,
                  child: _Sticky(
                    controller: _sc,
                    gridKey: _grid,
                    viewport: c.maxHeight,
                    child: KitSheetCard(
                      label: sheet.label,
                      maxHeight: math.max(240, c.maxHeight - 48),
                      child: KitSheetScope(child: sheet.body),
                    ),
                  ),
                ),
                SizedBox(width: gap),
                Expanded(child: widget.child),
              ],
            );
          }
          final content = Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1760),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  padH,
                  phone ? 26 : 40,
                  padH,
                  phone ? 40 : 88,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    masthead,
                    ?widget.under,
                    SizedBox(height: phone ? 26 : widget.gridTop),
                    grid,
                  ],
                ),
              ),
            ),
          );
          final dock = phone && sheet != null;
          return Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(top: dock ? 46 : 0),
                child: KitScrollView(controller: _sc, child: content),
              ),
              if (dock)
                Positioned.fill(
                  child: KitRunningHead(
                    sheet: sheet,
                    maxBodyHeight: math.max(160, c.maxHeight - 70),
                  ),
                ),
              if (_open && widget.settings != null)
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, cc) => _panelLayer(context, cc),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The sheet sticks 24 from the top of the page's scroller once the masthead
/// has scrolled past (§29's `position: sticky; top: 24px`), never past the
/// end of its grid. Read from the controller's own offset, so it moves on the
/// frame the scroll does.
class _Sticky extends StatefulWidget {
  final ScrollController controller;
  final GlobalKey gridKey;
  final double viewport;
  final Widget child;

  const _Sticky({
    required this.controller,
    required this.gridKey,
    required this.viewport,
    required this.child,
  });

  @override
  State<_Sticky> createState() => _StickyState();
}

class _StickyState extends State<_Sticky> {
  final GlobalKey _self = GlobalKey();
  bool _queued = false;

  // The column can grow (a read lands) without this widget rebuilding, so the
  // grid is re-measured after any frame the page scrolled in, too.
  void _onScroll() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      _measure();
    });
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(_Sticky old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  double? _gridTop;
  double _gridH = 0;
  double _selfH = 0;

  void _measure() {
    if (!mounted || !widget.controller.hasClients) return;
    final grid = widget.gridKey.currentContext?.findRenderObject();
    final self = _self.currentContext?.findRenderObject();
    final vp = widget.controller.position.context.storageContext
        .findRenderObject();
    if (grid is! RenderBox || self is! RenderBox || vp is! RenderBox) return;
    if (!grid.attached || !vp.attached) return;
    final top =
        grid.localToGlobal(Offset.zero, ancestor: vp).dy +
        widget.controller.offset;
    final changed =
        _gridTop == null ||
        (top - _gridTop!).abs() > .5 ||
        grid.size.height != _gridH ||
        self.size.height != _selfH;
    if (changed) {
      setState(() {
        _gridTop = top;
        _gridH = grid.size.height;
        _selfH = self.size.height;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        final gt = _gridTop;
        var shift = 0.0;
        if (gt != null && widget.controller.hasClients) {
          shift = (widget.controller.offset + 24 - gt).clamp(
            0.0,
            math.max(0.0, _gridH - _selfH),
          );
        }
        return Transform.translate(offset: Offset(0, shift), child: child);
      },
      child: KeyedSubtree(key: _self, child: widget.child),
    );
  }
}
