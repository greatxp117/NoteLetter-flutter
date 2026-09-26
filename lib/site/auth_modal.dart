import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_errors.dart';
import '../services/auth_service.dart';
import '../state/pending_letter_setup.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/kit/kit_failure.dart';
import 'site_sheet.dart';

/// Which face of the modal is up — its own tab switch moves between them.
enum AuthMode { signin, signup }

/// The sign-in / subscribe modal — the reference's `shared/AuthModal.jsx`.
///
/// Opened by `/signin`'s "Start your library" and by the landing. It owns the
/// auth call, the pre-signup **letter opt-in**, and nothing else: the page
/// behind it owns the copy above. A success is handled by the router: its
/// redirect replaces the signed-out page, and the modal leaves with it.
///
/// Two departures from the reference, both recorded rather than quietly made:
///  * below 720 the editorial half is not drawn — the reference's `1fr 1fr`
///    grid has no narrow form and at a phone's width would halve the fields;
///  * "Forgot password?" SENDS, as `/signin`'s "Forgot it?" does. The
///    reference's is `href="#"`, the dead control this workspace keeps finding.
Future<void> showAuthModal(BuildContext context, AuthMode mode) {
  final t = Tokens.of(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: t.scrim,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => AuthModal(initialMode: mode),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: const Cubic(0.2, 0.7, 0.2, 1),
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class AuthModal extends StatefulWidget {
  final AuthMode initialMode;
  const AuthModal({super.key, required this.initialMode});

  @override
  State<AuthModal> createState() => _AuthModalState();
}

class _AuthModalState extends State<AuthModal> {
  late AuthMode _mode = widget.initialMode;
  final _email = TextEditingController();
  final _pass = TextEditingController();
  String _error = '';
  String _said = '';
  bool _loading = false;

  // The letter opt-in — stashed locally and replayed through
  // fn_newsletter_settings once signed in (PendingLetterSetup).
  bool _wantLetter = true;
  String _tone = 'quiet';
  String _time = '06:30';

  bool get _signup => _mode == AuthMode.signup;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _setMode(AuthMode m) => setState(() {
    _mode = m;
    _error = '';
    _said = '';
  });

  /// Written BEFORE the auth call: a successful sign-up leaves the signed-out
  /// surface at once, so the signed-in app is the one that does the PUT.
  Future<void> _stash() async {
    if (!_signup) return;
    await PendingLetterSetup.stash(
      wanted: _wantLetter,
      deliveryTime: _time,
      tone: _tone,
    );
  }

  Future<void> _run(Future<void> Function() call) async {
    setState(() {
      _error = '';
      _said = '';
      _loading = true;
    });
    try {
      await _stash();
      await call();
      // Nothing pops here. A success changes the session, the router's
      // redirect replaces the signed-out page this modal sits on, and a
      // pageless route leaves with its page. Popping as well raced that
      // replacement — two removals of one route, Navigator's `_debugLocked`
      // assertion on the device run (2026-09-26).
    } catch (e) {
      if (mounted) setState(() => _error = humanizeAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() => _run(
    () => _signup
        ? AuthService.instance.signUp(_email.text, _pass.text)
        : AuthService.instance.signIn(_email.text, _pass.text),
  );

  Future<void> _google() => _run(AuthService.instance.signInWithGoogle);

  Future<void> _forgot() async {
    setState(() {
      _error = '';
      _said = '';
    });
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = humanizeAuthCode('missing-email'));
      return;
    }
    const said = 'If that address has an account, a reset link is on its way.';
    setState(() => _loading = true);
    try {
      await AuthService.instance.sendPasswordReset(email);
      if (mounted) setState(() => _said = said);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(
        () => e.code == 'user-not-found'
            ? _said = said
            : _error = humanizeAuthCode(e.code),
      );
    } catch (e) {
      if (mounted) setState(() => _error = humanizeAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final size = MediaQuery.sizeOf(context);
    final split = size.width >= 720;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: split ? 880 : 440,
              maxHeight: size.height * 0.92,
            ),
            child: Material(
              color: t.bg,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.nestR(AppRadius.md, 4),
                side: BorderSide(color: t.rule),
              ),
              clipBehavior: Clip.antiAlias,
              elevation: 24,
              shadowColor: AppShadows.ink(0.5),
              // One scroll view around both halves: a scroll view has no
              // intrinsic height, so it cannot sit inside the IntrinsicHeight
              // that lets the editorial half match the form's.
              child: SingleChildScrollView(
                child: split
                    ? IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Expanded(child: _Editorial()),
                            Expanded(child: _form(t)),
                          ],
                        ),
                      )
                    : _form(t),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(Tokens t) {
    final type = _ModalType(t);
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(36, 38, 36, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 14),
              _Tabs(mode: _mode, onChanged: _setMode),
              const SizedBox(height: 26),
              Text(
                _signup ? 'Begin your subscription.' : 'Welcome back, reader.',
                style: type.title,
              ),
              const SizedBox(height: 8),
              Text(
                _signup
                    ? 'Set up your library and choose when your letter '
                          'arrives. No card required.'
                    : 'A letter is waiting in your library.',
                style: type.sub,
              ),
              const SizedBox(height: 24),
              _GoogleRow(onPressed: _loading ? null : _google),
              const SizedBox(height: 20),
              const SiteOr(word: 'or by email'),
              const SizedBox(height: 16),
              AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Field(
                      label: 'Email',
                      icon: Icons.mail_outline,
                      hint: 'you@yourdomain.com',
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofill: AutofillHints.email,
                    ),
                    const SizedBox(height: 12),
                    _Field(
                      label: 'Password',
                      icon: Icons.lock_outline,
                      hint: _signup ? '12+ characters' : 'Your password',
                      controller: _pass,
                      obscure: true,
                      autofill: _signup
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ),
                  ],
                ),
              ),
              if (_signup) ...[
                const SizedBox(height: 16),
                _LetterOptIn(
                  wanted: _wantLetter,
                  tone: _tone,
                  time: _time,
                  onWanted: (v) => setState(() => _wantLetter = v),
                  onTone: (v) => setState(() => _tone = v),
                  onTime: (v) => setState(() => _time = v),
                ),
              ],
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                KitFailureInline(_error),
              ],
              if (_said.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_said, style: SiteType(t).said),
              ],
              const SizedBox(height: 20),
              _Submit(
                label: _loading
                    ? 'Please wait…'
                    : _signup
                    ? 'Create my library'
                    : 'Open the library',
                onPressed: _loading ? null : _submit,
              ),
              if (!_signup) ...[
                const SizedBox(height: 12),
                Center(
                  child: SiteTextButton(
                    'Forgot password?',
                    style: type.forgot,
                    onTap: _loading ? null : _forgot,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Container(height: 1, color: t.rule),
              const SizedBox(height: 18),
              _Legal(type: type),
            ],
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: Semantics(
            button: true,
            label: 'Close',
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: AppRadius.pillR(28),
              child: SizedBox(
                width: 28,
                height: 28,
                child: Icon(Icons.close, size: 14, color: t.fgSubtle),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The modal's own type — the reference's inline styles, by role.
class _ModalType {
  final Tokens t;
  const _ModalType(this.t);

  TextStyle get title => AppTheme.serif(
    fontSize: 30,
    fontWeight: FontWeight.w600,
    height: 1.1,
    letterSpacing: -0.6,
    color: t.fg,
  );
  TextStyle get sub => TextStyle(
    fontFamily: AppTheme.fontSans,
    fontSize: 13.5,
    height: 1.5,
    color: t.fgSubtle,
  );
  TextStyle get body => TextStyle(
    fontFamily: AppTheme.fontSans,
    fontSize: 13.5,
    color: t.fgMuted,
  );
  TextStyle get label => TextStyle(
    fontFamily: AppTheme.fontMono,
    fontSize: 11,
    letterSpacing: 0.06 * 11,
    color: t.fgSubtle,
  );
  TextStyle get input =>
      TextStyle(fontFamily: AppTheme.fontSans, fontSize: 14, color: t.fg);
  TextStyle get small => TextStyle(
    fontFamily: AppTheme.fontSans,
    fontSize: 12,
    height: 1.5,
    color: t.fgMuted,
  );
  TextStyle get note =>
      TextStyle(fontFamily: AppTheme.fontSans, fontSize: 11, color: t.fgSubtle);
  TextStyle get forgot => TextStyle(
    fontFamily: AppTheme.fontSans,
    fontSize: 12.5,
    color: t.fgSubtle,
  );
  TextStyle get legal => TextStyle(
    fontFamily: AppTheme.fontMono,
    fontSize: 11.5,
    height: 1.5,
    color: t.fgSubtle,
  );
}

/// The left half — `From the welcome issue`, the reference's copy verbatim.
class _Editorial extends StatelessWidget {
  const _Editorial();

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final type = _ModalType(t);
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        border: Border(right: BorderSide(color: t.rule)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mail_outline, size: 24, color: t.fg),
              const SizedBox(width: 10),
              Text(
                'NoteLetter',
                style: AppTheme.serif(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: t.fg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'From the welcome issue'.toUpperCase(),
            style: SiteType(t).asideEyebrow,
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: t.accent, width: 2)),
            ),
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              '"Maintenance has no photograph. The roof held; that is why it '
              'is not in the history book."',
              style: AppTheme.serif(
                fontSize: 22,
                height: 1.35,
                fontStyle: FontStyle.italic,
                color: t.fg,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('— Ines Moreau · §01 · Apr 7', style: type.legal),
          const Spacer(),
          const SizedBox(height: 28),
          Container(height: 1, color: t.rule),
          const SizedBox(height: 22),
          for (final line in const [
            'A daily letter from your own archive.',
            'Chat with an editor you have trained.',
            'Index stays private. Read-only on Notion + Drive.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.check, size: 13, color: t.fgMuted),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(line, style: type.body)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Sign in | Subscribe.
class _Tabs extends StatelessWidget {
  final AuthMode mode;
  final ValueChanged<AuthMode> onChanged;
  const _Tabs({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    Widget tab(AuthMode m, String name) {
      final on = mode == m;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: GestureDetector(
            onTap: () => onChanged(m),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
              decoration: BoxDecoration(
                color: on ? t.surface : null,
                borderRadius: AppRadius.xsR,
                boxShadow: on ? AppShadows.s1 : null,
              ),
              alignment: Alignment.center,
              child: Text(
                name,
                style: TextStyle(
                  fontFamily: AppTheme.fontSans,
                  fontSize: 13,
                  fontWeight: on ? FontWeight.w500 : FontWeight.w400,
                  color: on ? t.fg : t.fgSubtle,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        border: Border.all(color: t.rule),
        borderRadius: AppRadius.smR,
      ),
      child: Row(
        children: [
          tab(AuthMode.signin, 'Sign in'),
          const SizedBox(width: 4),
          tab(AuthMode.signup, 'Subscribe'),
        ],
      ),
    );
  }
}

class _GoogleRow extends StatelessWidget {
  final VoidCallback? onPressed;
  const _GoogleRow({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Opacity(
      opacity: onPressed == null ? 0.6 : 1,
      child: Material(
        color: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.controlR(44),
          side: BorderSide(color: t.rule),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadius.controlR(44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const GoogleMark(size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontFamily: AppTheme.fontSans,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: t.fg,
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward, size: 13, color: t.fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `AuthField` — a caps label over an icon-led well.
class _Field extends StatelessWidget {
  final String label;
  final IconData icon;
  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType? keyboardType;
  final String autofill;

  const _Field({
    required this.label,
    required this.icon,
    required this.hint,
    required this.controller,
    required this.autofill,
    this.obscure = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final type = _ModalType(t);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label.toUpperCase(), style: type.label),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.rule),
            borderRadius: AppRadius.controlR(44),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: t.fgSubtle),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  keyboardType: keyboardType,
                  autofillHints: [autofill],
                  autocorrect: false,
                  enableSuggestions: !obscure,
                  style: type.input,
                  cursorColor: t.accent,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: type.input.copyWith(color: t.fgSubtle),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
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

/// "Send me the daily letter at 6:30am in my timezone." — with its tone and
/// time, and the promise that all of it is editable later.
class _LetterOptIn extends StatelessWidget {
  final bool wanted;
  final String tone;
  final String time;
  final ValueChanged<bool> onWanted;
  final ValueChanged<String> onTone;
  final ValueChanged<String> onTime;

  const _LetterOptIn({
    required this.wanted,
    required this.tone,
    required this.time,
    required this.onWanted,
    required this.onTone,
    required this.onTime,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final type = _ModalType(t);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          checked: wanted,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onWanted(!wanted),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: wanted,
                    onChanged: (v) => onWanted(v ?? false),
                    activeColor: t.accent,
                    checkColor: t.accentFg,
                    side: BorderSide(color: t.borderStrong),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: type.small,
                      children: [
                        const TextSpan(text: 'Send me the daily letter at '),
                        TextSpan(
                          text: PendingLetterSetup.formatTime(time),
                          style: type.small.copyWith(
                            fontWeight: FontWeight.w600,
                            color: t.fg,
                          ),
                        ),
                        const TextSpan(text: ' in my timezone.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (wanted)
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: t.surfaceSunken,
                    border: Border.all(color: t.rule),
                    borderRadius: AppRadius.xsR,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (id, name) in PendingLetterSetup.tones)
                        GestureDetector(
                          onTap: () => onTone(id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: tone == id ? t.surface : null,
                              borderRadius: AppRadius.xsR,
                            ),
                            child: Text(
                              name,
                              style: TextStyle(
                                fontFamily: AppTheme.fontSans,
                                fontSize: 11.5,
                                fontWeight: tone == id
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                                color: tone == id ? t.fg : t.fgSubtle,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: t.surfaceSunken,
                    border: Border.all(color: t.rule),
                    borderRadius: AppRadius.xsR,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: time,
                      isDense: true,
                      dropdownColor: t.surfaceRaised,
                      style: type.small,
                      iconEnabledColor: t.fgSubtle,
                      items: [
                        for (final v in PendingLetterSetup.times)
                          DropdownMenuItem(
                            value: v,
                            child: Text(PendingLetterSetup.formatTime(v)),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) onTime(v);
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    'You can change all of this later in Letter '
                    'settings.',
                    style: type.note,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The ink submit — `--ink` on `--bg`, which flip together.
class _Submit extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _Submit({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Opacity(
      opacity: onPressed == null ? 0.6 : 1,
      child: Material(
        color: t.fg,
        borderRadius: AppRadius.smR,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadius.smR,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: t.bg,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 13, color: t.bg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "By continuing you agree to our Terms & Privacy." — the static legal page,
/// which the reference serves at `/privacy` on its own host.
class _Legal extends StatelessWidget {
  final _ModalType type;
  const _Legal({required this.type});

  @override
  Widget build(BuildContext context) {
    final link = type.legal.copyWith(
      color: type.t.fgMuted,
      decoration: TextDecoration.underline,
    );
    Widget a(String text, String anchor) => GestureDetector(
      onTap: () => launchUrl(
        Uri.parse('https://noteletter.com/privacy#$anchor'),
        mode: LaunchMode.externalApplication,
      ),
      child: Text(text, style: link),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('By continuing you agree to our ', style: type.legal),
        a('Terms', 'terms'),
        Text(' & ', style: type.legal),
        a('Privacy', 'privacy'),
        Text('.', style: type.legal),
      ],
    );
  }
}
