// `/landing` — the reference's LandingActual.jsx + landing-actual.css: the page
// is an edition of the letter. Site furniture with its own sheet, as
// `site_sheet.dart` records (Xavier, 2026-09-26: the web reference binds for
// the signed-out pages; tokens still bind).
//
// Recorded departures, each because the reference's mechanism does not exist
// here rather than by taste:
//  * §01's statement lights word by word with scroll, as the reference's does,
//    but it is not PINNED: `position: sticky` over a 180vh runway has no
//    counterpart inside one scroll view, so the words light as the statement
//    crosses the viewport instead.
//  * Links scroll to their department with `Scrollable.ensureVisible` — the
//    reference's `#n04` anchors.
//  * The sheet and the letters carry no grain: the reference lays it at 60%
//    and 50% opacity, and the kit's ground has one strength, which read as a
//    grey speckled page beside the reference's clean one (first frame,
//    2026-09-26). The desk around the sheet keeps its lattice.
//  * The footer's `rgba(255,255,255,.72/.5)` are the chrome tokens nearest them
//    (`--chrome-control`, `--chrome-muted`); `--brick-300` on the plum band is
//    `Tokens.dark.accentText`, the same fixed step in both themes.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/theme_notifier.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/kit/kit_ground.dart';
import '../widgets/kit/kit_shell.dart';
import 'auth_modal.dart';
import 'landing_bits.dart';

// ── the sheet ────────────────────────────────────────────────────────────────

class _Lt {
  final Tokens t;
  final double w;
  const _Lt(this.t, this.w);

  bool get phone => w <= 640;
  bool get narrow => w <= 980;

  TextStyle mono(
    double size,
    double tracking,
    Color c, {
    double? height,
    FontWeight? weight,
  }) => TextStyle(
    fontFamily: AppTheme.fontMono,
    fontSize: size,
    letterSpacing: tracking * size,
    color: c,
    height: height,
    fontWeight: weight,
  );
  TextStyle sans(double size, Color c, {double? height, FontWeight? weight}) =>
      TextStyle(
        fontFamily: AppTheme.fontSans,
        fontSize: size,
        color: c,
        height: height,
        fontWeight: weight,
      );
  TextStyle serif(
    double size,
    Color c, {
    double? height,
    double weight = 400,
    double tracking = 0,
    double? opsz,
    bool italic = false,
    bool press = false,
  }) {
    return TextStyle(
      fontFamily: AppTheme.fontSerif,
      fontSize: size,
      height: height,
      color: c,
      fontWeight: FontWeight.values[(weight ~/ 100) - 1],
      fontVariations: [
        FontVariation('wght', weight),
        if (opsz != null) FontVariation('opsz', opsz),
      ],
      fontStyle: italic ? FontStyle.italic : null,
      letterSpacing: tracking * size,
      shadows: press ? AppShadows.letterpress : null,
    );
  }

  TextStyle em(TextStyle s) =>
      s.copyWith(fontStyle: FontStyle.italic, color: t.accent);

  // `.dep h2`, `.dep > p`
  TextStyle get h2 => serif(
    phone ? 28 : 38,
    t.fg,
    height: 1.06,
    weight: 600,
    tracking: -.024,
    opsz: 40,
    press: true,
  );
  TextStyle get body => serif(
    phone ? 16 : 17.5,
    t.fg,
    height: phone ? 26 / 16 : 29 / 17.5,
    opsz: 18,
  );
  TextStyle get small => sans(14.5, t.fgMuted, height: 23 / 14.5);
}

/// The departments, their numbers and titles — the reference's CONTENTS.
const _contents = <(String, String)>[
  ('01', 'The brief'),
  ('02', 'The problem'),
  ('03', 'How it works'),
  ('04', 'Connect'),
  ('05', 'Index'),
  ('06', 'Letter'),
  ('07', 'What matters to you'),
  ('08', 'Where it reaches you'),
  ('09', 'Why this one'),
  ('10', 'Standing orders'),
];

const _navLinks = <(String, int)>[
  ('The problem', 1),
  ('How it works', 2),
  ('The sources', 3),
  ('The letter', 5),
];

/// What goes in. EPUBs are absent on purpose (a hard 400 since 4.10.0).
const _ticker = [
  'Articles',
  'PDFs',
  'Podcasts',
  'Voice memos',
  'YouTube',
  'Slide decks',
  'Highlights',
  'Newsletters',
  'Social posts',
  'Your notes',
  'Cloud drives',
];

// ── page ─────────────────────────────────────────────────────────────────────

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final _scroll = ScrollController();
  final _keys = List.generate(_contents.length, (_) => GlobalKey());
  final _scaffold = GlobalKey<ScaffoldState>();
  final _line = Dateline.of(DateTime.now());
  int _active = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_mark);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Which department the reader is in: the last whose top has crossed 28%
  /// of the viewport — the reference's `useActiveSection`.
  void _mark() {
    final line = MediaQuery.sizeOf(context).height * 0.28;
    var cur = 0;
    for (var i = 0; i < _keys.length; i++) {
      final box = _keys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy <= line) cur = i;
    }
    if (cur != _active) setState(() => _active = cur);
  }

  void _go(int i) {
    final c = _keys[i].currentContext;
    if (c != null) {
      Scrollable.ensureVisible(
        c,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOut,
      );
    }
  }

  void _signUp() => showAuthModal(context, AuthMode.signup);
  void _signIn() => showAuthModal(context, AuthMode.signin);

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final w = MediaQuery.sizeOf(context).width;
    final lt = _Lt(t, w);
    final pad = w <= 720 ? 20.0 : 32.0;
    return Scaffold(
      key: _scaffold,
      backgroundColor: t.bg,
      endDrawer: _Drawer(
        onLink: (i) {
          Navigator.of(context).pop();
          _go(i);
        },
        onSignUp: () {
          Navigator.of(context).pop();
          _signUp();
        },
        onSignIn: () {
          Navigator.of(context).pop();
          _signIn();
        },
      ),
      body: Stack(
        children: [
          // `.lac::before` — the checkered desk the sheet lies on.
          Positioned.fill(
            child: KitGround(grain: false, child: const SizedBox()),
          ),
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              controller: _scroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: pad),
                    child: _Nav(
                      lt: lt,
                      onTop: () => _scroll.animateTo(
                        0,
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOut,
                      ),
                      onLink: _go,
                      onSignIn: _signIn,
                      onSignUp: _signUp,
                      onMenu: () => _scaffold.currentState?.openEndDrawer(),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      lt.narrow ? 18 : 32,
                      0,
                      lt.narrow ? 18 : 32,
                      lt.narrow ? 64 : 88,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1400),
                        child: _Sheet(
                          lt: lt,
                          line: _line,
                          keys: _keys,
                          active: _active,
                          scroll: _scroll,
                          onSignUp: _signUp,
                          onLink: _go,
                        ),
                      ),
                    ),
                  ),
                  _Footer(lt: lt, line: _line, onSignUp: _signUp, onLink: _go),
                ],
              ),
            ),
          ),
          const Positioned(right: 18, bottom: 18, child: _ThemeToggle()),
        ],
      ),
    );
  }
}

// ── chrome ───────────────────────────────────────────────────────────────────

class _Tap extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final String? label;
  const _Tap({required this.child, required this.onTap, this.label});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: child,
    ),
  );
}

/// `.cta-primary` — and, `compact`, the nav's `.nav-cta`.
class _Cta extends StatelessWidget {
  final _Lt lt;
  final VoidCallback onTap;
  final bool compact;
  const _Cta({required this.lt, required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final t = lt.t;
    final h = compact ? 34.0 : 46.0;
    final size = compact
        ? (lt.w <= 400
              ? 12.5
              : lt.w <= 560
              ? 13.0
              : 14.0)
        : 15.0;
    return Material(
      color: t.accent,
      borderRadius: AppRadius.controlR(h),
      child: InkWell(
        onTap: onTap,
        hoverColor: t.accentHover,
        borderRadius: AppRadius.controlR(h),
        child: Container(
          height: h,
          decoration: BoxDecoration(
            borderRadius: AppRadius.controlR(h),
            boxShadow: compact ? null : AppShadows.s2,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? (lt.w <= 400 ? 10 : 12) : 22,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Start your library',
                style: lt.sans(size, t.accentFg, weight: FontWeight.w500),
              ),
              if (!compact) ...[
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 16, color: t.accentFg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Nav extends StatelessWidget {
  final _Lt lt;
  final VoidCallback onTop, onSignIn, onSignUp, onMenu;
  final ValueChanged<int> onLink;
  const _Nav({
    required this.lt,
    required this.onTop,
    required this.onLink,
    required this.onSignIn,
    required this.onSignUp,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final t = lt.t;
    final w = lt.w;
    final brand = _Tap(
      onTap: onTop,
      label: 'NoteLetter',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KitQuill(size: 26, color: t.fg),
          const SizedBox(width: 10),
          KitWordmark(
            fontSize: w <= 560 ? 15 : 17,
            color: t.fg,
            tracking: 0.11,
            opsz: 24,
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Row(
        children: [
          // At a phone's width the brand takes what the CTA and the burger
          // leave, and scales down rather than clipping (`.nav .brand
          // { min-width: 0 }`); wider, it is its natural size.
          if (w > 940)
            brand
          else
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(fit: BoxFit.scaleDown, child: brand),
              ),
            ),
          if (w > 940) ...[
            const SizedBox(width: 48),
            for (final (label, i) in _navLinks)
              _Tap(
                onTap: () => onLink(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(label, style: lt.sans(14, t.fgMuted)),
                ),
              ),
          ],
          if (w > 940) const Spacer(),
          if (w > 720)
            _Tap(
              onTap: onSignIn,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text('Sign in', style: lt.sans(14, t.fgMuted)),
              ),
            ),
          if (w >= 360) ...[
            SizedBox(width: w <= 560 ? 2 : 8),
            _Cta(lt: lt, onTap: onSignUp, compact: true),
          ],
          if (w <= 940) ...[
            SizedBox(width: w <= 560 ? 2 : 8),
            _Tap(
              onTap: onMenu,
              label: 'Menu',
              child: SizedBox(
                width: 38,
                height: 38,
                child: Icon(Icons.menu, size: 22, color: t.fg),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Drawer extends StatelessWidget {
  final ValueChanged<int> onLink;
  final VoidCallback onSignUp, onSignIn;
  const _Drawer({
    required this.onLink,
    required this.onSignUp,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final lt = _Lt(t, MediaQuery.sizeOf(context).width);
    Widget row(String label, VoidCallback onTap) => _Tap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.rule)),
        ),
        child: Text(label, style: lt.serif(19, t.fg, opsz: 20)),
      ),
    );
    return Drawer(
      width: math.min(280, MediaQuery.sizeOf(context).width * 0.84),
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: _Tap(
                  onTap: () => Navigator.of(context).pop(),
                  label: 'Close',
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.close, size: 22, color: t.fgMuted),
                  ),
                ),
              ),
              for (final (label, i) in _navLinks) row(label, () => onLink(i)),
              const SizedBox(height: 14),
              _Cta(lt: lt, onTap: onSignUp),
              row('Sign in', onSignIn),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.mk-theme` — the visitor's choice is the app's own, carried into the
/// library after they sign in.
class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final theme = context.watch<ThemeNotifier>();
    final dark = t.isDark;
    Widget b(IconData icon, String label, bool on, ThemeMode mode) => _Tap(
      onTap: () => theme.setMode(mode),
      label: label,
      child: Container(
        width: 34,
        height: 30,
        decoration: BoxDecoration(
          color: on ? t.surfaceSunken : null,
          borderRadius: AppRadius.pillR(30),
        ),
        child: Icon(icon, size: 16, color: on ? t.fg : t.fgMuted),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: AppRadius.pillR(38),
        boxShadow: AppShadows.s2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          b(Icons.light_mode_outlined, 'Light', !dark, ThemeMode.light),
          const SizedBox(width: 2),
          b(Icons.dark_mode_outlined, 'Dark', dark, ThemeMode.dark),
        ],
      ),
    );
  }
}

// ── the edition ──────────────────────────────────────────────────────────────

class _Sheet extends StatelessWidget {
  final _Lt lt;
  final Dateline line;
  final List<GlobalKey> keys;
  final int active;
  final ScrollController scroll;
  final VoidCallback onSignUp;
  final ValueChanged<int> onLink;
  const _Sheet({
    required this.lt,
    required this.line,
    required this.keys,
    required this.active,
    required this.scroll,
    required this.onSignUp,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    final t = lt.t;
    final lbPad = lt.phone
        ? const EdgeInsets.fromLTRB(18, 6, 18, 8)
        : lt.narrow
        ? const EdgeInsets.fromLTRB(30, 6, 30, 8)
        : lt.w <= 1100
        ? const EdgeInsets.fromLTRB(44, 6, 30, 8)
        : const EdgeInsets.fromLTRB(60, 6, 48, 8);
    final deps = [
      _Brief(lt: lt, scroll: scroll),
      const _Problem(),
      _How(onLink: onLink),
      const _Connect(),
      const _Index(),
      const _LetterDep(),
      const _Matters(),
      const _Reaches(),
      const _Why(),
      _Orders(onSignUp: onSignUp),
    ];
    final lb = Padding(
      padding: lbPad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < deps.length; i++)
            KeyedSubtree(
              key: keys[i],
              child: _Dep(lt: lt, index: i, child: deps[i]),
            ),
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: AppRadius.lgR,
        boxShadow: AppShadows.s3,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.lgR,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Masthead(lt: lt, line: line, onSignUp: onSignUp),
              const _Ticker(),
              if (lt.narrow)
                lb
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: lb),
                    SizedBox(
                      width: lt.w <= 1100 ? 196 : 232,
                      child: _Contents(lt: lt, active: active, onLink: onLink),
                    ),
                  ],
                ),
              _Colophon(lt: lt, line: line),
            ],
          ),
        ),
      ),
    );
  }
}

class _Masthead extends StatelessWidget {
  final _Lt lt;
  final Dateline line;
  final VoidCallback onSignUp;
  const _Masthead({
    required this.lt,
    required this.line,
    required this.onSignUp,
  });

  @override
  Widget build(BuildContext context) {
    final t = lt.t;
    final strap = lt.mono(10, .16, t.fgSubtle);
    final lock = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KitQuill(size: 17, color: t.fg),
        const SizedBox(width: 9),
        Text.rich(
          TextSpan(
            style: lt.serif(13.5, t.fg, weight: 600, tracking: .2, opsz: 20),
            children: [
              const TextSpan(text: 'N'),
              TextSpan(
                text: 'OTE',
                style: TextStyle(fontSize: 13.5 * .8),
              ),
              const TextSpan(text: 'L'),
              TextSpan(
                text: 'ETTER',
                style: TextStyle(fontSize: 13.5 * .8),
              ),
            ],
          ),
          semanticsLabel: 'NoteLetter',
        ),
      ],
    );
    final day = '${line.day}, ${line.date}'.toUpperCase();
    final strapRow = lt.phone
        ? Column(
            children: [
              Text(
                line.stamp.toUpperCase(),
                style: strap,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              lock,
              const SizedBox(height: 6),
              Text(day, style: strap, textAlign: TextAlign.center),
            ],
          )
        : Row(
            children: [
              Expanded(child: Text(line.stamp.toUpperCase(), style: strap)),
              lock,
              Expanded(
                child: Text(day, style: strap, textAlign: TextAlign.right),
              ),
            ],
          );
    final say = _Say(lt: lt, onSignUp: onSignUp);
    final stack = _LetterStack(lt: lt, line: line);
    return Padding(
      padding: lt.phone
          ? const EdgeInsets.fromLTRB(18, 22, 18, 0)
          : lt.narrow
          ? const EdgeInsets.fromLTRB(30, 26, 30, 0)
          : const EdgeInsets.fromLTRB(60, 34, 60, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.rule)),
            ),
            child: strapRow,
          ),
          Container(height: 2, color: t.fg),
          Padding(
            padding: lt.phone
                ? const EdgeInsets.only(top: 32, bottom: 36)
                : lt.narrow
                ? const EdgeInsets.only(top: 40, bottom: 48)
                : const EdgeInsets.only(top: 56, bottom: 64),
            child: lt.narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      say,
                      SizedBox(height: lt.phone ? 36 : 44),
                      stack,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(flex: 7, child: say),
                      SizedBox(width: lt.w <= 1100 ? 40 : 56),
                      Expanded(flex: 5, child: stack),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// The headline, its two retyping words, the standfirst and the primary act.
class _Say extends StatefulWidget {
  final _Lt lt;
  final VoidCallback onSignUp;
  const _Say({required this.lt, required this.onSignUp});

  @override
  State<_Say> createState() => _SayState();
}

class _SayState extends State<_Say> {
  (String, String) _typed = rotPairs.first;
  bool _busy = false;
  bool _caret = true;
  Timer? _blink;
  bool _alive = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion never arms the loop: the sentence reads correctly on
    // the first pair, which is the state that is painted.
    if (_blink == null && !MediaQuery.disableAnimationsOf(context)) {
      _blink = Timer.periodic(const Duration(milliseconds: 525), (_) {
        if (mounted && !_busy) setState(() => _caret = !_caret);
      });
      _run();
    }
  }

  @override
  void dispose() {
    _alive = false;
    _blink?.cancel();
    super.dispose();
  }

  Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: ms));

  /// One loop owns the whole cycle: erase both words, then type the next pair
  /// in step — the reference's timings.
  Future<void> _run() async {
    var i = 0;
    var cur = rotPairs.first;
    await _wait(2200);
    while (_alive && mounted) {
      i = (i + 1) % rotPairs.length;
      final next = rotPairs[i];
      setState(() {
        _busy = true;
        _caret = true;
      });
      for (var n = math.max(cur.$1.length, cur.$2.length); n > 0; n--) {
        if (!_alive || !mounted) return;
        setState(
          () => _typed = (
            cur.$1.substring(0, math.min(n - 1, cur.$1.length)),
            cur.$2.substring(0, math.min(n - 1, cur.$2.length)),
          ),
        );
        await _wait(36);
      }
      await _wait(180);
      for (var n = 1; n <= math.max(next.$1.length, next.$2.length); n++) {
        if (!_alive || !mounted) return;
        setState(
          () => _typed = (
            next.$1.substring(0, math.min(n, next.$1.length)),
            next.$2.substring(0, math.min(n, next.$2.length)),
          ),
        );
        await _wait(58);
      }
      if (!_alive || !mounted) return;
      setState(() => _busy = false);
      cur = next;
      await _wait(2400);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lt = widget.lt;
    final t = lt.t;
    final w = lt.w;
    final size = lt.phone
        ? (w * 0.105).clamp(36.0, 44.0)
        : w <= 1100
        ? (w * 0.05).clamp(40.0, 60.0)
        : (w * 0.054).clamp(44.0, 78.0);
    final h1 = lt.serif(
      size,
      t.fg,
      height: 1,
      weight: 600,
      tracking: -.03,
      opsz: 60,
      press: true,
    );
    InlineSpan rot(String word, Color color) => WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            // the 2px accent underline at 20%
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: t.accent.withValues(alpha: .2),
                  width: 2,
                ),
              ),
            ),
            child: Text(
              word,
              style: h1.copyWith(fontStyle: FontStyle.italic, color: color),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Opacity(
              opacity: _caret ? 1 : 0,
              child: Container(width: 2, height: size * .78, color: t.accent),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: h1,
            children: [
              const TextSpan(text: 'Your '),
              rot(_typed.$1, t.accent),
              const TextSpan(text: ' deserve'),
              TextSpan(text: lt.phone ? ' ' : '\n'),
              const TextSpan(text: 'to be re-'),
              rot(_typed.$2, t.fg),
              const TextSpan(text: '.'),
            ],
          ),
          semanticsLabel:
              'Your ${rotPairs.first.$1} deserve to be re-${rotPairs.first.$2}.',
        ),
        SizedBox(height: lt.phone ? 20 : 28),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: lt.phone ? double.infinity : 440,
          ),
          child: Text(
            'You kept it because it was worth keeping. NoteLetter holds the '
            'whole collection and posts a few passages back to you every '
            'morning — until the things you chose are things you know.',
            style: lt.serif(
              lt.phone ? 17 : 20,
              t.fgLede,
              height: lt.phone ? 28 / 17 : 32 / 20,
              italic: true,
              opsz: 20,
            ),
          ),
        ),
        SizedBox(height: lt.phone ? 24 : 30),
        Wrap(
          spacing: 18,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Cta(lt: lt, onTap: widget.onSignUp),
            Text(
              'Free to start · No card · Your library stays yours',
              style: lt.mono(11, .06, t.fgSubtle, height: 1.9),
            ),
          ],
        ),
      ],
    );
  }
}

/// Three mornings of letters, fanned; at a phone's width only today's.
class _LetterStack extends StatelessWidget {
  final _Lt lt;
  final Dateline line;
  const _LetterStack({required this.lt, required this.line});

  Widget _paper(_Lt lt, {required Widget child, double? minHeight}) {
    final t = lt.t;
    return Container(
      constraints: BoxConstraints(minHeight: minHeight ?? 0),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: AppRadius.mdR,
        boxShadow: AppShadows.s3,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.mdR,
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 22, 26, 24),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _head(_Lt lt, List<InlineSpan> spans, {bool seal = false}) {
    final t = lt.t;
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(style: lt.mono(10, .14, t.fgMuted), children: spans),
            ),
          ),
          if (seal)
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: t.accentSoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: KitQuill(size: 14, color: t.seal),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = lt.t;
    final h4 = lt.serif(
      30,
      t.fg,
      height: 1.06,
      weight: 600,
      tracking: -.022,
      opsz: 32,
      press: true,
    );
    final mark = t.highlight;
    final top = _paper(
      lt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head(lt, [
            TextSpan(
              text: '№ 124',
              style: TextStyle(color: t.accentText),
            ),
            TextSpan(text: '     ${line.day.toUpperCase()}, 6:30'),
          ], seal: true),
          const SizedBox(height: 14),
          Text(
            'Four passages · two returning'.toUpperCase(),
            style: lt.mono(9.5, .16, t.accentText),
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              style: h4,
              children: [
                const TextSpan(text: 'Margin & '),
                TextSpan(text: 'Memory', style: lt.em(h4)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(
              style: lt.serif(15.5, t.fg, height: 25 / 15.5, opsz: 16),
              children: [
                const TextSpan(
                  text:
                      'We fetishize invention because invention has a '
                      'photograph. Maintenance has no photograph. ',
                ),
                TextSpan(
                  text:
                      'The woman who re-tarred the roof is not in the history '
                      'book; the roof is not in the history book either, '
                      'because the roof held.',
                  style: TextStyle(backgroundColor: mark),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Chip(lt: lt, text: 'Essay', size: 9, tracking: .12),
              Text(
                'The Maintenance Essays · p. 61',
                style: lt.sans(12, t.fgMuted),
              ),
              SizedBox(
                width: double.infinity,
                child: Text(
                  'Third time · first read in March',
                  style: lt.serif(13, t.fgLede, italic: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.rule)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in const [
                  '§ 02 · Lecture · 41:20',
                  '§ 03 · Your note · Kyoto notebook',
                  '§ 04 · Podcast · 12:05',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Text(
                      s.toUpperCase(),
                      style: lt.mono(9.5, .12, t.fgMuted),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (lt.phone) return ExcludeSemantics(child: top);
    Widget under(String no, String when, String title, double minH) => _paper(
      lt,
      minHeight: minH,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head(lt, [TextSpan(text: '$no     $when'.toUpperCase())]),
          const SizedBox(height: 12),
          Text(title, style: h4),
        ],
      ),
    );
    return ExcludeSemantics(
      child: Align(
        alignment: lt.narrow ? Alignment.center : Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: lt.narrow ? 460 : 440),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 40),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Transform.translate(
                    offset: const Offset(-44, 40),
                    child: Transform.rotate(
                      angle: -7 * math.pi / 180,
                      alignment: Alignment.bottomCenter,
                      child: Opacity(
                        opacity: .8,
                        child: under(
                          '№ 122',
                          'Sunday, 6:30',
                          'The Unread Shelf',
                          380,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Transform.translate(
                    offset: const Offset(36, 18),
                    child: Transform.rotate(
                      angle: 4 * math.pi / 180,
                      alignment: Alignment.bottomCenter,
                      child: Opacity(
                        opacity: .92,
                        child: under(
                          '№ 123',
                          'Monday, 6:30',
                          'Weather, Not Currency',
                          400,
                        ),
                      ),
                    ),
                  ),
                ),
                Transform.rotate(
                  angle: -1 * math.pi / 180,
                  alignment: Alignment.bottomCenter,
                  child: top,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An accent chip — `.lt-src .k`, `.dep-h .n`, `.conn .chips span`.
class _Chip extends StatelessWidget {
  final _Lt lt;
  final String text;
  final double size;
  final double tracking;
  final bool square;
  const _Chip({
    required this.lt,
    required this.text,
    this.size = 10,
    this.tracking = .1,
    this.square = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = lt.t;
    return Container(
      padding: square
          ? const EdgeInsets.fromLTRB(8, 5, 8, 4)
          : const EdgeInsets.fromLTRB(8, 3, 8, 3),
      decoration: BoxDecoration(
        color: t.accentChipBg,
        border: Border.all(color: t.accentChipBorder),
        borderRadius: square ? AppRadius.xsR : AppRadius.pillR(24),
      ),
      child: Text(
        text.toUpperCase(),
        style: lt.mono(size, tracking, t.accentChipFg, height: 1),
      ),
    );
  }
}

/// A plain outlined chip — `.ways .chips span`.
class _Tag extends StatelessWidget {
  final _Lt lt;
  final String text;
  const _Tag({required this.lt, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 5, 10, 4),
    decoration: BoxDecoration(
      border: Border.all(color: lt.t.border),
      borderRadius: AppRadius.pillR(24),
    ),
    child: Text(text.toUpperCase(), style: lt.mono(10, .1, lt.t.fgMuted)),
  );
}

/// `.tkr` — what goes in, going in.
class _Ticker extends StatefulWidget {
  const _Ticker();

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 54),
  );
  final _rowKey = GlobalKey();
  double _half = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final lt = _Lt(t, MediaQuery.sizeOf(context).width);
    Widget item(String s) => Padding(
      padding: const EdgeInsets.only(right: 38),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: .55),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 9),
          Text(s.toUpperCase(), style: lt.mono(10.5, .16, t.fgMuted)),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _rowKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null &&
          box.hasSize &&
          box.size.width / 2 != _half &&
          mounted) {
        setState(() => _half = box.size.width / 2);
      }
    });
    return ExcludeSemantics(
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: t.surfaceSunken,
          border: Border.symmetric(horizontal: BorderSide(color: t.rule)),
        ),
        child: ClipRect(
          child: ShaderMask(
            // the two 64px fades into the band's own ground
            shaderCallback: (r) => LinearGradient(
              colors: [
                t.surfaceSunken.withValues(alpha: 0),
                t.surfaceSunken,
                t.surfaceSunken,
                t.surfaceSunken.withValues(alpha: 0),
              ],
              stops: [0, 64 / r.width, 1 - 64 / r.width, 1],
            ).createShader(r),
            blendMode: BlendMode.dstIn,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, child) => OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: Transform.translate(
                  offset: Offset(-_half * _c.value, 0),
                  child: child,
                ),
              ),
              child: Row(
                key: _rowKey,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final s in [..._ticker, ..._ticker]) item(s),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.toc` — the contents rail, above 980 only.
class _Contents extends StatelessWidget {
  final _Lt lt;
  final int active;
  final ValueChanged<int> onLink;
  const _Contents({
    required this.lt,
    required this.active,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    final t = lt.t;
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: t.rule)),
      ),
      padding: lt.w <= 1100
          ? const EdgeInsets.fromLTRB(20, 26, 26, 40)
          : const EdgeInsets.fromLTRB(26, 30, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 11),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.borderStrong)),
            ),
            child: Text(
              'In this edition'.toUpperCase(),
              style: lt.mono(10, .18, t.accentText),
            ),
          ),
          for (var i = 0; i < _contents.length; i++)
            _Tap(
              onTap: () => onLink(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.rule)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        _contents[i].$1,
                        style: lt.mono(
                          10,
                          .06,
                          active == i ? t.accentText : t.fgSubtle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _contents[i].$2,
                        style: lt.sans(
                          13.5,
                          active == i ? t.fg : t.fgMuted,
                          height: 19 / 13.5,
                          weight: active == i ? FontWeight.w500 : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 18),
          Text(
            'Set in Source Serif & Geist\nDept. of Marginalia'.toUpperCase(),
            style: lt.mono(9.5, .14, t.fgSubtle, height: 16 / 9.5),
          ),
        ],
      ),
    );
  }
}

// ── departments ──────────────────────────────────────────────────────────────

/// `.dep` + `.dep-h` — the numbered head and the rule above every department
/// but the first.
class _Dep extends StatelessWidget {
  final _Lt lt;
  final int index;
  final Widget child;
  const _Dep({required this.lt, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = lt.t;
    final (n, k) = _contents[index];
    final head = Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        children: [
          _Chip(lt: lt, text: '§ $n', tracking: .18, square: true),
          const SizedBox(width: 10),
          Text(
            k == 'What matters to you'
                ? 'WHAT TRULY MATTERS TO YOU'
                : k.toUpperCase(),
            style: lt.mono(12, .18, t.fg, weight: FontWeight.w500),
          ),
          const SizedBox(width: 13),
          Expanded(child: Container(height: 1, color: t.rule)),
        ],
      ),
    );
    return Container(
      decoration: index == 0
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: t.rule)),
            ),
      padding: index == 0
          ? const EdgeInsets.symmetric(vertical: 72)
          : lt.phone
          ? const EdgeInsets.only(top: 34, bottom: 40)
          : const EdgeInsets.only(top: 44, bottom: 52),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [head, child],
      ),
    );
  }
}

/// `.dep h2` with an accent `<em>` tail.
Widget _h2(_Lt lt, String plain, String em, [String after = '']) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: Text.rich(
    TextSpan(
      style: lt.h2,
      children: [
        TextSpan(text: plain),
        TextSpan(text: em, style: lt.em(lt.h2)),
        if (after.isNotEmpty) TextSpan(text: after),
      ],
    ),
  ),
);

Widget _p(_Lt lt, String s) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: Text(s, style: lt.body),
);

/// `.chap` — the chapter opening §04, §05 and §06 share.
Widget _chapter(_Lt lt, String title, String stand, String em) {
  final t = lt.t;
  final c = lt.serif(
    lt.phone ? 19 : 24,
    t.accentText,
    height: 1.3,
    italic: true,
  );
  return Container(
    margin: const EdgeInsets.only(top: 4, bottom: 26),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: t.rule)),
    ),
    child: Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: lt.serif(
                  lt.phone ? 32 : (lt.w * .042).clamp(38.0, 56.0),
                  t.fg,
                  height: 1.02,
                  weight: 600,
                  tracking: -.026,
                  opsz: 60,
                  press: true,
                ),
              ),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  style: c,
                  children: [
                    TextSpan(text: stand),
                    TextSpan(
                      text: em,
                      style: c.copyWith(color: t.accent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          bottom: 0,
          child: Container(width: 38, height: 3, color: t.accent),
        ),
      ],
    ),
  );
}

/// A bordered card on `--surface` — `.conn`, `.find`, `.inbox`, `.msn`.
Widget _card(
  _Lt lt, {
  required Widget child,
  EdgeInsets padding = EdgeInsets.zero,
  Color? color,
  bool lifted = true,
}) => Container(
  padding: padding,
  decoration: BoxDecoration(
    color: color ?? lt.t.surface,
    border: Border.all(color: lt.t.border),
    borderRadius: AppRadius.mdR,
    boxShadow: lifted ? AppShadows.s1 : null,
  ),
  clipBehavior: Clip.antiAlias,
  child: child,
);

/// §01 — the statement lights word by word as it crosses the viewport.
class _Brief extends StatefulWidget {
  final _Lt lt;
  final ScrollController scroll;
  const _Brief({required this.lt, required this.scroll});

  @override
  State<_Brief> createState() => _BriefState();
}

class _BriefState extends State<_Brief> {
  static final _words = [
    for (final w
        in 'You saved it for a reason. But over time, you’ve forgotten '
                'most of it. Now it’s time to'
            .split(' '))
      (w, false),
    for (final w in 'bring it back to life.'.split(' ')) (w, true),
  ];
  static final _sol = [
    for (final w in 'NoteLetter is the'.split(' ')) (w, false),
    ('librarian', true),
    for (final w
        in 'who organizes it all for you and gives you back what’s best.'.split(
          ' ',
        ))
      (w, false),
  ];
  double _head = 0;

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_light);
    WidgetsBinding.instance.addPostFrameCallback((_) => _light());
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_light);
    super.dispose();
  }

  void _light() {
    if (!mounted) return;
    final total = (_words.length + _sol.length).toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_head != total) setState(() => _head = total);
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final vh = MediaQuery.sizeOf(context).height;
    final top = box.localToGlobal(Offset.zero).dy;
    // 0 as its top enters the lower fifth, 1 once its bottom reaches the
    // upper third — then held, as the reference holds after the last word.
    final start = vh * .8;
    final end = vh * .33 - box.size.height;
    final raw = ((start - top) / (start - end)).clamp(0.0, 1.0);
    final next = raw * total;
    if ((next - _head).abs() > .01) setState(() => _head = next);
  }

  @override
  Widget build(BuildContext context) {
    final lt = widget.lt;
    final t = lt.t;
    final style = lt.serif(
      lt.phone ? 30 : (lt.w * .042).clamp(30.0, 62.0),
      t.fg,
      height: 1.1,
      weight: 600,
      tracking: -.028,
      opsz: 60,
      press: true,
    );
    TextSpan word((String, bool) w, int n) {
      final lit = (_head - n).clamp(0.0, 1.0);
      final on = lit > .55;
      return TextSpan(
        text: '${w.$1} ',
        style: style.copyWith(
          color: (w.$2 && on ? t.accent : t.fg).withValues(
            alpha: 0.13 + 0.87 * lit,
          ),
          fontStyle: w.$2 && on ? FontStyle.italic : null,
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: style.fontSize! * 34 * .5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                for (var i = 0; i < _words.length; i++) word(_words[i], i),
              ],
            ),
          ),
          SizedBox(height: style.fontSize! * .5),
          Text.rich(
            TextSpan(
              children: [
                for (var i = 0; i < _sol.length; i++)
                  word(_sol[i], _words.length + i),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem();

  @override
  Widget build(BuildContext context) {
    final lt = _Lt(Tokens.of(context), MediaQuery.sizeOf(context).width);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _h2(
          lt,
          'You read it, you meant to come back to it, ',
          'but you never did.',
        ),
        _p(
          lt,
          'Everything you save has a half-life. A link, a file, a voice memo on '
          'the walk home — it lands somewhere and is readable in seconds, and by '
          'any Tuesday in August you have forgotten you had it. The archive kept '
          'every word and no reason to hand any back.',
        ),
        _Curve(lt: lt),
        _p(
          lt,
          'Posted back, the same passage is still working on you in August. '
          'Spaced further apart each time, the third reading is the one that '
          'changes how you work — and when you search a half-remembered phrase '
          'mid-sentence, it is there, with its source attached.',
        ),
      ],
    );
  }
}

/// Fig. 1 — one passage over a year; a schematic, captioned as one.
class _Curve extends StatelessWidget {
  final _Lt lt;
  const _Curve({required this.lt});

  @override
  Widget build(BuildContext context) {
    final t = lt.t;
    return Container(
      margin: const EdgeInsets.only(top: 30, bottom: 26),
      padding: lt.phone
          ? const EdgeInsets.fromLTRB(14, 16, 14, 14)
          : const EdgeInsets.fromLTRB(26, 22, 26, 20),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        border: Border.all(color: t.border),
        borderRadius: AppRadius.mdR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              style: lt.mono(10, .14, t.fgMuted, height: 1.9),
              children: [
                TextSpan(
                  text: 'FIG. 1   ',
                  style: TextStyle(color: t.accentText),
                ),
                TextSpan(
                  text: 'One passage, over a year — a schematic'.toUpperCase(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            label:
                'Two curves. Left alone, what you remember of a passage falls '
                'away within days. Posted back at widening intervals, each letter '
                'lifts it, and the drop after each is shallower.',
            child: AspectRatio(
              aspectRatio: 960 / 300,
              child: CustomPaint(painter: _CurvePainter(lt)),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.rule)),
            ),
            child: Text(
              'Each mark is a letter, sent just before the passage would have '
              'slipped. The shape of forgetting has been drawn for a century; '
              'nothing changes it except seeing the thing again.',
              style: lt.serif(14.5, t.fgMuted, height: 22 / 14.5, italic: true),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  final _Lt lt;
  _CurvePainter(this.lt);

  static final _decay = svgPath(curveDecay);
  static final _lifted = svgPath(curveLifted);

  @override
  void paint(Canvas canvas, Size size) {
    final t = lt.t;
    final k = size.width / 960;
    canvas.save();
    canvas.scale(k);
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / k * k;
    for (final (x, _) in curveMarks) {
      canvas.drawLine(Offset(x, 30), Offset(x, 250), thin..color = t.rule);
    }
    canvas.drawLine(
      const Offset(40, 250),
      const Offset(920, 250),
      thin..color = t.borderStrong,
    );
    // Left alone: dashed.
    final off = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..color = t.fgSubtle;
    for (final m in _decay.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), off);
      }
    }
    canvas.drawPath(
      _lifted,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = t.accent,
    );
    for (final (x, _) in curveMarks.skip(1)) {
      canvas.drawCircle(Offset(x, 250), 5, Paint()..color = t.seal);
    }
    canvas.drawCircle(
      const Offset(60, 250),
      5,
      Paint()..color = t.surfaceRaised,
    );
    canvas.drawCircle(
      const Offset(60, 250),
      5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = t.fgSubtle,
    );
    // Labels — at a phone's width the reference sets them LARGER in the
    // viewBox so they survive the scale-down.
    final lbl = lt.mono(lt.phone ? 15 : 11, .1, t.fgMuted);
    for (final (x, l) in curveMarks) {
      _text(canvas, l.toUpperCase(), lbl, Offset(x, 278), TextAlign.center);
    }
    final tag = lt.serif(lt.phone ? 19 : 15, t.fgMuted, italic: true);
    _text(canvas, 'Left alone', tag, const Offset(905, 228), TextAlign.right);
    _text(
      canvas,
      'Posted back',
      tag.copyWith(color: t.accentText),
      const Offset(905, 30),
      TextAlign.right,
    );
    canvas.restore();
  }

  /// Text anchored as SVG anchors it: [at] is the baseline point.
  void _text(Canvas c, String s, TextStyle style, Offset at, TextAlign align) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final dx = switch (align) {
      TextAlign.center => at.dx - tp.width / 2,
      TextAlign.right => at.dx - tp.width,
      _ => at.dx,
    };
    tp.paint(c, Offset(dx, at.dy - base));
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) =>
      old.lt.t != lt.t || old.lt.phone != lt.phone;
}

class _How extends StatelessWidget {
  final ValueChanged<int> onLink;
  const _How({required this.onLink});

  static const _steps = [
    (
      'Connect',
      'Point it at the pile.',
      'Connect the places you already save into, or drop files straight in. Read-only, always — nothing is written back.',
      3,
    ),
    (
      'Index',
      'Read by meaning.',
      'Every paragraph is indexed by what it says, not what you titled it. So the thing you half-remember is findable in the words you half-remember.',
      4,
    ),
    (
      'Letter',
      'A letter, on your schedule.',
      'Daily at the hour you set, or once a week. One theme, four passages, threaded by a librarian you shape yourself.',
      5,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final lt = _Lt(Tokens.of(context), MediaQuery.sizeOf(context).width);
    final t = lt.t;
    Widget step(int i) {
      final (k, h, body, dep) = _steps[i];
      final disc = Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: t.surface,
          shape: BoxShape.circle,
          border: Border.all(color: t.borderStrong),
        ),
        alignment: Alignment.center,
        child: Text('${i + 1}', style: lt.mono(11, 0, t.fg)),
      );
      final text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Tap(
            onTap: () => onLink(dep),
            child: Text(k.toUpperCase(), style: lt.mono(10, .18, t.accentText)),
          ),
          const SizedBox(height: 10),
          Text(
            h,
            style: lt.serif(24, t.fg, height: 1.1, weight: 600, tracking: -.02),
          ),
          const SizedBox(height: 8),
          Text(body, style: lt.small),
        ],
      );
      if (lt.narrow) {
        return Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              disc,
              const SizedBox(width: 16),
              Expanded(child: text),
            ],
          ),
        );
      }
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: i < 2 ? 32 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [disc, const SizedBox(height: 18), text],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _h2(lt, 'Connect, index, ', 'letter.'),
        _p(lt, 'Three quiet pieces, in the order they happen.'),
        const SizedBox(height: 14),
        if (lt.narrow)
          Column(children: [for (var i = 0; i < 3; i++) step(i)])
        else
          Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 17,
                child: Container(height: 1, color: t.rule),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (var i = 0; i < 3; i++) step(i)],
              ),
            ],
          ),
      ],
    );
  }
}

/// A grid that is two columns above 980 and one at or below.
Widget _grid(_Lt lt, List<Widget> cells, {double gap = 16, int cols = 2}) {
  if (lt.narrow) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          cells[i],
        ],
      ],
    );
  }
  final rows = <Widget>[];
  for (var i = 0; i < cells.length; i += cols) {
    rows.add(
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var j = i; j < i + cols; j++) ...[
              if (j > i) SizedBox(width: gap),
              Expanded(child: j < cells.length ? cells[j] : const SizedBox()),
            ],
          ],
        ),
      ),
    );
    if (i + cols < cells.length) rows.add(SizedBox(height: gap));
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
}

class _Connect extends StatelessWidget {
  const _Connect();

  static const _ways = [
    (
      'Read',
      'The page you have open, a folder you hand over, a decade of highlights.',
      ['Articles', 'PDFs', 'Documents', 'Slide decks', 'Highlights'],
    ),
    (
      'Heard',
      'Episodes and interviews, and the half-thought you record walking.',
      ['Podcasts', 'Voice memos', 'Audiobooks', 'Recorded calls'],
    ),
    (
      'Written',
      'Your own notes stay in sync, margins and all. Anything on your phone is one share away.',
      ['Your notes', 'Social posts', 'Newsletters', 'Cloud drives'],
    ),
    (
      'Watched',
      'Video is the hardest thing to return to. Paste a link and NoteLetter keeps the transcript and the timestamp, so a passage plays back at the second it mattered.',
      [
        'YouTube',
        'Talks & lectures',
        'Documentaries',
        'Course videos',
        'Screen recordings',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final lt = _Lt(Tokens.of(context), MediaQuery.sizeOf(context).width);
    final t = lt.t;
    final lbl = lt.mono(10, .16, t.fgMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _chapter(
          lt,
          'Point it at the pile.',
          'Setup is a few clicks, then ',
          'nothing.',
        ),
        _p(
          lt,
          'Most of what you have saved is already sitting in another account. '
          'Connect it once and NoteLetter reads what is already there. New files '
          'land on their own, and there is nothing to file or tag.',
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 30),
          child: _card(
            lt,
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text('CONNECTIONS', style: lbl.copyWith(color: t.fg)),
                    Text('READ-ONLY · REVOKE ANY TIME', style: lbl),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in const [
                      'Google Drive',
                      'Dropbox',
                      'OneDrive',
                      'Notion',
                    ])
                      _Chip(lt: lt, text: c),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.rule)),
                  ),
                  child: Text(
                    'Sign in, pick a folder, close the tab. Nothing else is asked of you.',
                    style: lt.serif(15, t.fgMuted, italic: true),
                  ),
                ),
              ],
            ),
          ),
        ),
        _p(
          lt,
          'Or send things in one at a time. Text is only one of the ways '
          'knowledge arrives — everything gets transcribed, split into passages, '
          'and indexed by meaning, so a line from a podcast is as findable as a '
          'line from a book.',
        ),
        const SizedBox(height: 16),
        _grid(lt, [
          for (final (h, body, chips) in _ways)
            Container(
              padding: lt.phone
                  ? const EdgeInsets.all(18)
                  : const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
              decoration: BoxDecoration(
                color: t.surface,
                border: Border.all(color: t.border),
                borderRadius: AppRadius.mdR,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h,
                    style: lt.serif(
                      lt.phone ? 28 : 34,
                      t.accentText,
                      height: 1,
                      weight: 500,
                      tracking: -.02,
                      opsz: 40,
                      italic: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(body, style: lt.small),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [for (final c in chips) _Tag(lt: lt, text: c)],
                  ),
                ],
              ),
            ),
        ]),
      ],
    );
  }
}

class _Index extends StatelessWidget {
  const _Index();

  static const _hits = [
    (
      'Lecture',
      'Weather, Not Currency',
      '41:20',
      'You will be told that attention is a currency. ',
      'It is not. It is a weather system.',
    ),
    (
      'Essay',
      'The Maintenance Essays',
      'p. 61',
      'Spending implies a purse with a bottom. ',
      'Tending implies a season.',
    ),
    (
      'Your note',
      'Kyoto notebook',
      'Apr 3',
      'If attention is weather then the calendar is a barometer, not a budget.',
      '',
    ),
  ];
  static const _bullets = [
    'Ask in a sentence, not in keywords',
    'Every result is a passage, quoted, with its source attached. Nothing invented',
    'Audio and video carry a timestamp, and play from there',
    'The index takes in new sources as they land, without being asked',
  ];

  @override
  Widget build(BuildContext context) {
    final lt = _Lt(Tokens.of(context), MediaQuery.sizeOf(context).width);
    final t = lt.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _chapter(
          lt,
          'Read by meaning.',
          'A thought you can’t find is ',
          'a thought you don’t have.',
        ),
        _p(
          lt,
          'Every paragraph is indexed by what it says, not by what you titled '
          'it or where you filed it. So a half-remembered phrase is enough — '
          'and the podcast at 41:20 answers the same question as the book.',
        ),
        const SizedBox(height: 10),
        _card(
          lt,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: t.surfaceRaised,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 16, color: t.fgMuted),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        'that thing about attention not being a currency',
                        style: lt.sans(14.5, t.fg),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('3 passages', style: lt.mono(9.5, .1, t.fgMuted)),
                  ],
                ),
              ),
              for (final (kind, src, at, before, mark) in _hits)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 15,
                  ),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.rule)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _Chip(lt: lt, text: kind, size: 9, tracking: .12),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(src, style: lt.sans(12, t.fgMuted)),
                          ),
                          Text(at, style: lt.mono(9.5, .06, t.fgSubtle)),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text.rich(
                        TextSpan(
                          style: lt.serif(16, t.fg, height: 26 / 16, opsz: 18),
                          children: [
                            TextSpan(text: before),
                            if (mark.isNotEmpty)
                              TextSpan(
                                text: mark,
                                style: TextStyle(backgroundColor: t.highlight),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.borderStrong)),
                ),
                child: Text(
                  'THREE SOURCES · ALL ADDED BY YOU',
                  style: lt.mono(9.5, .1, t.fgSubtle),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        for (var i = 0; i < _bullets.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: i == 0
                ? null
                : BoxDecoration(
                    border: Border(top: BorderSide(color: t.rule)),
                  ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Icon(Icons.check, size: 16, color: t.accentText),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _bullets[i],
                    style: lt.sans(13.5, t.fgMuted, height: 21 / 13.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LetterDep extends StatelessWidget {
  const _LetterDep();

  static const _inbox = [
    (
      '№ 124',
      'Margin & Memory',
      'Four passages · two returning',
      'Tue 6:30',
      true,
    ),
    (
      '№ 123',
      'Weather, Not Currency',
      'Four passages · one returning',
      'Mon 6:30',
      false,
    ),
    (
      '№ 122',
      'The Unread Shelf',
      'Four passages · three returning',
      'Sun 6:30',
      false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final lt = _Lt(Tokens.of(context), MediaQuery.sizeOf(context).width);
    final t = lt.t;
    final lbl = lt.mono(10, .16, t.fgMuted);
    Widget kv(String title, List<(String, String)> rows) => Container(
      padding: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.fg, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title.toUpperCase(), style: lt.mono(9.5, .18, t.accentText)),
          const SizedBox(height: 12),
          for (final (k, v) in rows)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.rule)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(
                      k.toUpperCase(),
                      style: lt.mono(9, .12, t.fgSubtle),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(v, style: lt.sans(13, t.fgMuted))),
                ],
              ),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _chapter(
          lt,
          'It comes back.',
          'Seeing something once is ',
          'not learning it.',
        ),
        _p(
          lt,
          'One theme, four passages, at the hour you set. Each letter is drawn '
          'from your own shelves and spaced so the passage returns just before '
          'you would have lost it. Read it in your inbox, or have it read aloud '
          'as a private podcast feed for the walk.',
        ),
        const SizedBox(height: 10),
        _card(
          lt,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: t.surfaceRaised,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Text('INBOX', style: lbl.copyWith(color: t.fg)),
                    const Spacer(),
                    Text('EVERY MORNING, 6:30', style: lbl),
                  ],
                ),
              ),
              for (final (no, title, sub, at, unread) in _inbox)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.rule)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: unread ? t.accent : null,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (lt.w > 720) ...[
                        SizedBox(
                          width: 120,
                          child: Row(
                            children: [
                              KitQuill(size: 12, color: t.seal),
                              const SizedBox(width: 7),
                              Text('NoteLetter', style: lt.sans(13.5, t.fg)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: lt.sans(
                              13.5,
                              t.fg,
                              weight: unread ? FontWeight.w500 : null,
                            ),
                            children: [
                              TextSpan(
                                text: '$no ',
                                style: lt.mono(11, 0, t.accentText),
                              ),
                              TextSpan(text: title),
                              TextSpan(
                                text: ' — $sub',
                                style: TextStyle(color: t.fgMuted),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(at, style: lt.mono(10, .08, t.fgMuted)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        _grid(lt, gap: lt.narrow ? 26 : 40, [
          kv('§ 06.1 · How it chooses', const [
            ('Chosen by', 'What you want to get better at'),
            ('Sources', 'Your own library, nothing else'),
            ('Arrives', 'Daily or weekly, your hour'),
            ('Aloud', 'A private podcast feed, same letter'),
          ]),
          kv('§ 06.2 · What it asks of you', const [
            ('Effort', 'Read the letter. That is all of it'),
            ('Backlog', 'None. Nothing piles up unread'),
            ('Ignored', 'Skip a fortnight; the spacing adjusts'),
          ]),
        ]),
      ],
    );
  }
}

class _Matters extends StatelessWidget {
  const _Matters();

  @override
  Widget build(BuildContext context) {
    final lt = _Lt(Tokens.of(context), MediaQuery.sizeOf(context).width);
    final t = lt.t;
    final small = lt.sans(12.5, t.fgSubtle, height: 19 / 12.5);
    final cases = lt.sans(12.5, t.fgMuted, height: 20 / 12.5);
    final caseEm = lt.serif(12.5, t.accentText, italic: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _h2(lt, 'You choose the content ', 'that comes.'),
        _p(
          lt,
          'A pile of saved things has no opinion about what you are trying to '
          'become. You give your librarian a brief, and everything they send is '
          'chosen against it.',
        ),
        const SizedBox(height: 10),
        _card(
          lt,
          padding: lt.phone
              ? const EdgeInsets.all(18)
              : const EdgeInsets.fromLTRB(28, 26, 28, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'YOUR BRIEF TO THE LIBRARIAN · EDITED IN MARCH',
                style: lt.mono(9.5, .16, t.accentText),
              ),
              const SizedBox(height: 14),
              for (final (i, s) in const [
                'Write clearly under deadline.',
                'Understand how good software teams decide.',
                'Cook well enough to stop thinking about it.',
              ].indexed)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: i == 0
                      ? null
                      : BoxDecoration(
                          border: Border(top: BorderSide(color: t.rule)),
                        ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(
                          '§ 0${i + 1}',
                          style: lt.mono(9, .08, t.fgSubtle),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          s,
                          style: lt.serif(18, t.fg, height: 26 / 18, opsz: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.only(top: 13),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.borderStrong)),
                ),
                child: Text.rich(
                  TextSpan(
                    style: small,
                    children: [
                      const TextSpan(text: 'Retired: '),
                      TextSpan(
                        text: 'learn conversational Portuguese',
                        style: TextStyle(
                          decoration: TextDecoration.lineThrough,
                          decorationColor: t.accent,
                        ),
                      ),
                      const TextSpan(text: ' · '),
                      TextSpan(
                        text: 'the history of cartography',
                        style: TextStyle(
                          decoration: TextDecoration.lineThrough,
                          decorationColor: t.accent,
                        ),
                      ),
                      const TextSpan(text: ' — struck out in January.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.only(top: 13),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.rule)),
                ),
                child: Text.rich(
                  TextSpan(
                    style: cases,
                    children: [
                      const TextSpan(
                        text:
                            'Some libraries are read differently, and are handled '
                            'that way: ',
                      ),
                      TextSpan(text: 'scripture', style: caseEm),
                      const TextSpan(text: ' by chapter and verse, '),
                      TextSpan(text: 'recipes', style: caseEm),
                      const TextSpan(text: ' by the week, '),
                      TextSpan(text: 'papers', style: caseEm),
                      const TextSpan(text: ' by citation, '),
                      TextSpan(text: 'a language', style: caseEm),
                      const TextSpan(text: ' by what you last got wrong.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Reaches extends StatelessWidget {
  const _Reaches();

  @override
  Widget build(BuildContext context) {
    final lt = _Lt(Tokens.of(context), MediaQuery.sizeOf(context).width);
    final t = lt.t;
    Widget tile(IconData icon, String h, String p) => Container(
      padding: lt.phone
          ? const EdgeInsets.all(18)
          : const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: AppRadius.mdR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: t.seal),
          const SizedBox(height: 16),
          Text(
            h,
            style: lt.serif(22, t.fg, height: 1.16, weight: 600, opsz: 22),
          ),
          const SizedBox(height: 8),
          Text(p, style: lt.sans(14, t.fgMuted, height: 22 / 14)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _h2(lt, 'It comes to where ', 'you already are.'),
        _p(
          lt,
          'A system you have to remember to visit is one you stop visiting. The '
          'letter arrives instead.',
        ),
        const SizedBox(height: 12),
        _grid(lt, [
          tile(
            Icons.mail_outline,
            'Your inbox',
            'Plain enough to read in any client, with no app to open. The letter is the product; the app is where the library lives.',
          ),
          tile(
            Icons.mic_none,
            'A private podcast feed',
            'The same letter, read aloud — for the commute or the walk. Subscribe once in the player you already use.',
          ),
        ]),
      ],
    );
  }
}

class _Why extends StatelessWidget {
  const _Why();

  static const _why = [
    (
      'Zero maintenance',
      'No queue to groom, no weekly review you will skip. Ignore it for two months and the letters keep arriving, still right.',
    ),
    (
      'No lock-in',
      'The file you uploaded stays downloadable from its own page, and any source can be removed from your library in one click.',
    ),
    (
      'Never held hostage',
      'Free to start, paid to go further — and above the free plan everything you filed stays readable, searchable and yours. Nothing is ever deleted to make you pay.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final lt = _Lt(Tokens.of(context), MediaQuery.sizeOf(context).width);
    final t = lt.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _h2(lt, 'It works ', 'while you ignore it.'),
        _p(
          lt,
          'Most personal knowledge tools ask you to become the kind of person '
          'who maintains a personal knowledge tool. This one asks for a source '
          'and an email address.',
        ),
        const SizedBox(height: 12),
        _grid(lt, gap: lt.narrow ? 22 : 32, cols: 3, [
          for (final (h, p) in _why)
            Container(
              padding: const EdgeInsets.only(top: 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.fg, width: 2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h,
                    style: lt.serif(
                      22,
                      t.fg,
                      height: 1.1,
                      weight: 600,
                      tracking: -.018,
                      opsz: 24,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(p, style: lt.sans(14, t.fgMuted, height: 22 / 14)),
                ],
              ),
            ),
        ]),
      ],
    );
  }
}

class _Orders extends StatelessWidget {
  final VoidCallback onSignUp;
  const _Orders({required this.onSignUp});

  @override
  Widget build(BuildContext context) {
    final lt = _Lt(Tokens.of(context), MediaQuery.sizeOf(context).width);
    final t = lt.t;
    final h3 = lt.serif(
      lt.phone ? 32 : (lt.w * .036).clamp(32.0, 44.0),
      t.fg,
      height: 1.04,
      weight: 600,
      tracking: -.024,
      opsz: 40,
      press: true,
    );
    return CustomPaint(
      painter: _Dashed(t.borderStrong),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: lt.phone
            ? const EdgeInsets.symmetric(horizontal: 20, vertical: 26)
            : const EdgeInsets.fromLTRB(36, 34, 36, 32),
        decoration: BoxDecoration(
          color: t.surfaceRaised,
          borderRadius: AppRadius.mdR,
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STANDING ORDER · CANCEL IN ONE CLICK',
                  style: lt.mono(9.5, .18, t.accentText),
                ),
                const SizedBox(height: 14),
                Text.rich(
                  TextSpan(
                    style: h3,
                    children: [
                      const TextSpan(text: 'Take on a '),
                      TextSpan(text: 'librarian.', style: lt.em(h3)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Point them at one thing you saved. Tomorrow morning it comes '
                  'back, and keeps coming back. Free to start, and free is genuinely '
                  'usable: connect one source, set an hour.',
                  style: lt.serif(
                    17,
                    t.fgLede,
                    height: 27 / 17,
                    italic: true,
                    opsz: 18,
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 18,
                  runSpacing: 14,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Cta(lt: lt, onTap: onSignUp),
                    Text(
                      'FREE TO START · TAKES ABOUT TWO MINUTES',
                      style: lt.mono(10, .1, t.fgMuted),
                    ),
                  ],
                ),
              ],
            ),
            if (!lt.phone)
              Positioned(
                top: -6,
                right: -4,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: t.accentSoft,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: KitQuill(size: 22, color: t.seal),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `border: 1px dashed` — Flutter's borders are solid.
class _Dashed extends CustomPainter {
  final Color color;
  _Dashed(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      (Offset(0, 6) & Size(size.width, size.height - 6)).deflate(.5),
      const Radius.circular(AppRadius.md),
    );
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final m in (Path()..addRRect(r)).computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Dashed old) => old.color != color;
}

class _Colophon extends StatelessWidget {
  final _Lt lt;
  final Dateline line;
  const _Colophon({required this.lt, required this.line});

  @override
  Widget build(BuildContext context) {
    final t = lt.t;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.fg, width: 2)),
      ),
      padding: lt.phone
          ? const EdgeInsets.fromLTRB(18, 24, 18, 28)
          : lt.narrow
          ? const EdgeInsets.fromLTRB(30, 28, 30, 32)
          : const EdgeInsets.fromLTRB(60, 34, 60, 40),
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: t.accentSoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: KitQuill(size: 16, color: t.seal),
          ),
          Text.rich(
            TextSpan(
              style: lt.mono(10, .14, t.fgSubtle, height: 17 / 10),
              children: [
                TextSpan(
                  text: 'NOTELETTER PRESS',
                  style: TextStyle(color: t.accentText),
                ),
                TextSpan(
                  text:
                      ' · EST. 2026\n${line.stamp.toUpperCase()} · DEPT. OF MARGINALIA',
                ),
              ],
            ),
          ),
          SizedBox(
            width: lt.phone ? double.infinity : null,
            child: Text(
              'Tomorrow, at the hour you choose.',
              style: lt.serif(14, t.fgLede, italic: true),
            ),
          ),
        ],
      ),
    );
  }
}

// ── footer — the plum chrome band, fixed in both themes ─────────────────────

class _Footer extends StatelessWidget {
  final _Lt lt;
  final Dateline line;
  final VoidCallback onSignUp;
  final ValueChanged<int> onLink;
  const _Footer({
    required this.lt,
    required this.line,
    required this.onSignUp,
    required this.onLink,
  });

  static const _cols = [
    (
      'The product',
      [('The letter', 5), ('Search', 4), ('Library', 3), ('The brief', 6)],
    ),
    ('Reading', [('How it works', 2), ('The problem', 1), ('Why this one', 8)]),
    ('Company', [('Standing orders', 9), ('Where it reaches you', 7)]),
  ];

  @override
  Widget build(BuildContext context) {
    final t = lt.t;
    final paper = t.chromeFg;
    final muted = t.chromeMuted;
    final brick = Tokens.dark.accentText; // --brick-300, fixed on the band
    final colH = lt.mono(10, .16, muted);
    Widget link(String s, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _Tap(
        onTap: onTap,
        child: Text(s, style: lt.sans(14, paper)),
      ),
    );
    Widget col(String title, List<Widget> links) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 14),
          child: Text(title.toUpperCase(), style: colH),
        ),
        ...links,
      ],
    );
    final brand = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KitQuill(size: 24, color: paper),
            const SizedBox(width: 10),
            KitWordmark(fontSize: 17, color: paper, tracking: .11, opsz: 24),
          ],
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: lt.w <= 720 ? double.infinity : 300,
          ),
          child: Text(
            'A personal librarian for everything you have read, watched, heard '
            'and written.',
            style: lt.serif(15, t.chromeControl, height: 22 / 15, italic: true),
          ),
        ),
        const SizedBox(height: 16),
        Text.rich(
          TextSpan(
            style: lt.mono(10, .14, muted),
            children: [
              TextSpan(
                text: 'EST. 2026',
                style: TextStyle(color: brick),
              ),
              TextSpan(
                text: ' · ${line.stamp.toUpperCase()} · DEPT. OF MARGINALIA',
              ),
            ],
          ),
        ),
      ],
    );
    final cols = [
      for (final (title, links) in _cols)
        col(title, [for (final (s, i) in links) link(s, () => onLink(i))]),
      col('Begin', [
        link('Start your library', onSignUp),
        // The one link to /signin — the addressable page; a page nothing
        // links to is a page nobody reaches.
        link('Sign in', () => context.go('/signin')),
      ]),
    ];
    final meta = lt.mono(11, .06, muted);
    final metas = [
      Text('© ${DateTime.now().year} NoteLetter Press', style: meta),
      _Tap(
        onTap: () => launchUrl(
          Uri.parse('https://noteletter.com/privacy'),
          mode: LaunchMode.externalApplication,
        ),
        child: Text(
          'Privacy & Terms',
          style: meta.copyWith(decoration: TextDecoration.underline),
        ),
      ),
      Text('Independent, and staying that way', style: meta),
    ];
    return Container(
      color: t.chrome,
      padding: EdgeInsets.fromLTRB(
        lt.w <= 720 ? 20 : 32,
        72,
        lt.w <= 720 ? 20 : 32,
        28 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1116),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: EdgeInsets.only(bottom: lt.w <= 720 ? 32 : 56),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.chromeBorder)),
                ),
                child: lt.w <= 720
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          brand,
                          for (final c in cols) ...[
                            const SizedBox(height: 24),
                            c,
                          ],
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: brand),
                          for (final c in cols) ...[
                            const SizedBox(width: 48),
                            Expanded(child: c),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 28),
              if (lt.w <= 720)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final m in metas) ...[m, const SizedBox(height: 10)],
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: metas,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
