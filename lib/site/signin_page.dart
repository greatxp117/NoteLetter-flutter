import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_errors.dart';
import '../services/auth_service.dart';
import '../theme/app_radius.dart';
import '../theme/tokens.dart';
import '../widgets/kit/kit_failure.dart';
import '../widgets/kit/kit_ground.dart';
import 'auth_modal.dart';
import 'site_sheet.dart';

/// `/signin` — the reference's `SignIn.jsx` + `signin.css`, site furniture
/// (see `site_sheet.dart`).
///
/// The addressable half of signing in: the URL a reader can be sent back to.
/// The landing's modal is the inline half; they share the auth calls and one
/// error vocabulary (`services/auth_errors.dart`), and "Start your library"
/// opens that same modal in its subscribe mode, so the sign-up form and its
/// letter opt-in exist once.
///
/// The reference's four recorded departures from its design mirror hold here
/// too: no "email me a sign-in link" (passwordless is not enabled), no stat
/// row (invented figures), "Forgot it?" actually sends, and the Google mark is
/// Google's.
///
/// A successful sign-in navigates nowhere: the router's redirect sees the
/// session and takes the reader into the app, as the reference's AuthGate does.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

/// The three points, the reference's unchanged.
const _points = <(String, String, String)>[
  (
    '01',
    'Connect the pile.',
    'Point it at a folder you already keep — Drive, Dropbox, Notion.',
  ),
  (
    '02',
    'Indexed by meaning.',
    'Ask in your own words and the passage turns up, not the filename.',
  ),
  (
    '03',
    'A letter, on your schedule.',
    'Read it in the inbox, or hear it on the walk.',
  ),
];

/// The reset sentence is the SAME whether or not the address has an account:
/// this form is unauthenticated, and any other answer tells a visitor which
/// addresses are registered.
const _resetSaid =
    'If that address has an account, a reset link is on its way.';

class _SignInPageState extends State<SignInPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  String _error = '';
  String _said = '';
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() call) async {
    setState(() {
      _error = '';
      _said = '';
      _loading = true;
    });
    try {
      await call();
    } catch (e) {
      if (mounted) setState(() => _error = humanizeAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signIn() =>
      _run(() => AuthService.instance.signIn(_email.text, _pass.text));

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
    setState(() => _loading = true);
    try {
      await AuthService.instance.sendPasswordReset(email);
      if (mounted) setState(() => _said = _resetSaid);
    } on FirebaseAuthException catch (e) {
      // `user-not-found` answers exactly as success does — the constant is the
      // point here, not a dropped sentence.
      if (!mounted) return;
      setState(
        () => e.code == 'user-not-found'
            ? _said = _resetSaid
            : _error = humanizeAuthCode(e.code),
      );
    } catch (e) {
      if (mounted) setState(() => _error = humanizeAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _leave() => context.go('/landing');

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width > 900;
    final roomy = width > 1100;
    final form = _FormPanel(
      width: width,
      email: _email,
      pass: _pass,
      error: _error,
      said: _said,
      loading: _loading,
      onSignIn: _signIn,
      onGoogle: _google,
      onForgot: _forgot,
      onStart: () => showAuthModal(context, AuthMode.signup),
    );
    return Scaffold(
      backgroundColor: Tokens.of(context).bg,
      body: SitePage(
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(onLeave: _leave),
                Padding(
                  // `.si-wrap`: 18 28 64 60, the left falling to 28 under 1100
                  // and the bottom to 44 once the columns stack.
                  padding: EdgeInsets.fromLTRB(
                    roomy ? 60 : 28,
                    18,
                    28,
                    wide ? 64 : 44,
                  ),
                  child: wide
                      ? Align(
                          alignment: Alignment.topLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1300),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 72, child: const _Aside()),
                                SizedBox(width: roomy ? 56 : 40),
                                Expanded(flex: 100, child: form),
                              ],
                            ),
                          ),
                        )
                      // Stacked: the form first, the case under it.
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            form,
                            const SizedBox(height: 36),
                            const _Aside(),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.si-top` — the lockup and the way back.
class _TopBar extends StatelessWidget {
  final VoidCallback onLeave;
  const _TopBar({required this.onLeave});

  @override
  Widget build(BuildContext context) {
    final type = SiteType.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: Row(
        children: [
          SiteBrand(onTap: onLeave),
          const Spacer(),
          SiteTextButton(
            '← Back to the site',
            style: type.back,
            onTap: onLeave,
          ),
        ],
      ),
    );
  }
}

/// `.si-aside` — the case, on the raised grain.
class _Aside extends StatelessWidget {
  const _Aside();

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final type = SiteType(t);
    final wide = MediaQuery.sizeOf(context).width > 900;
    final h2 = type.asideHeading;
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        border: Border.all(color: t.border),
        borderRadius: AppRadius.mdR,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.mdR,
        child: KitGround(
          lattice: false,
          child: Padding(
            padding: wide
                ? const EdgeInsets.fromLTRB(32, 30, 32, 28)
                : const EdgeInsets.fromLTRB(24, 26, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Why NoteLetter'.toUpperCase(), style: type.asideEyebrow),
                const SizedBox(height: 14),
                Text.rich(
                  TextSpan(
                    style: h2,
                    children: [
                      const TextSpan(text: 'Everything you’ve read, '),
                      TextSpan(text: 'coming back to you', style: type.em(h2)),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                for (final (n, lead, body) in _points)
                  Container(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: t.rule)),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(n, style: type.pointNumber),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              style: type.pointBody,
                              children: [
                                TextSpan(text: lead, style: type.pointLead),
                                TextSpan(text: ' $body'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.si-form-panel`.
class _FormPanel extends StatelessWidget {
  final double width;
  final TextEditingController email;
  final TextEditingController pass;
  final String error;
  final String said;
  final bool loading;
  final VoidCallback onSignIn;
  final VoidCallback onGoogle;
  final VoidCallback onForgot;
  final VoidCallback onStart;

  const _FormPanel({
    required this.width,
    required this.email,
    required this.pass,
    required this.error,
    required this.said,
    required this.loading,
    required this.onSignIn,
    required this.onGoogle,
    required this.onForgot,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final type = SiteType.of(context);
    final h = type.heading(width);
    // `.si-form`, `.si-or`, `.si-alt`, `.si-note` — all max-width 400.
    Widget column(Widget child) => Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: child,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('§ Sign in'.toUpperCase(), style: type.folio),
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(
            style: h,
            children: [
              const TextSpan(text: 'Welcome back to '),
              TextSpan(text: 'your library', style: type.em(h)),
              const TextSpan(text: '.'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            // 38ch of the lede's italic serif.
            constraints: const BoxConstraints(maxWidth: 340),
            child: Text(
              'Your passages are where you left them, and the next letter is '
              'already set.',
              style: type.lede,
            ),
          ),
        ),
        const SiteDash(),
        column(
          AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SiteField(
                  label: 'Email',
                  hint: 'you@example.com',
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  action: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                SiteField(
                  label: 'Password',
                  hint: '••••••••••',
                  controller: pass,
                  obscure: true,
                  autofillHints: const [AutofillHints.password],
                  action: TextInputAction.go,
                  onSubmitted: loading ? null : (_) => onSignIn(),
                  trailing: SiteTextButton(
                    'Forgot it?',
                    style: type.forgot,
                    onTap: loading ? null : onForgot,
                  ),
                ),
                // `.si-fail` is a SLOT: the line is the kit's §14.2, which is
                // the one app pattern these pages use — a rejection reads the
                // same wherever it happens.
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  KitFailureInline(error),
                ],
                if (said.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(said, style: type.said),
                ],
                const SizedBox(height: 20),
                SiteSubmit(
                  loading ? 'Please wait…' : 'Sign in',
                  onPressed: loading ? null : onSignIn,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        column(const SiteOr()),
        const SizedBox(height: 16),
        column(
          SiteGhost(
            'Continue with Google',
            leading: const GoogleMark(),
            onPressed: loading ? null : onGoogle,
          ),
        ),
        const SizedBox(height: 22),
        column(
          Text.rich(
            TextSpan(
              style: type.note,
              children: [
                const TextSpan(text: 'No account yet? '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: SiteTextButton(
                    'Start your library',
                    style: type.noteLink,
                    onTap: onStart,
                  ),
                ),
                const TextSpan(
                  text: '. It takes one source and about a minute.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
