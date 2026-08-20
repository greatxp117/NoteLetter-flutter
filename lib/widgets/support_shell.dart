import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/support_notifier.dart';
import '../theme/tokens.dart';
import 'kit/kit.dart';

/// **INV-22, and the only place it is composed.**
///
/// The support footer is shell furniture, not screen content: it is rendered
/// here, beneath the routed view, for every authenticated route. No screen
/// renders it and no screen may suppress it — a client that adds a screen gets
/// the footer without editing that screen and without remembering it exists.
///
/// It wraps the whole authenticated routing surface rather than [AppLayout],
/// which covers only the rail-and-pane routes. The reader is deliberately
/// outside that inner shell (it is a full-bleed screen), and putting the footer
/// in [AppLayout] would have left exactly one authenticated screen without a way
/// out — the precise failure INV-22 exists to prevent, arrived at by a different
/// road. `test/contract/support_footer_test.dart` walks the real route table
/// and fails on any authenticated route that does not sit under this widget.
///
/// The two exemptions the invariant names are outside it by construction, not
/// by a condition in this file: the pre-auth landing page (sending requires a
/// signed-in caller, INV-01, so there is nothing to link to) and a first-run
/// onboarding wizard, which replaces the shell rather than routing inside it.
/// This client has no wizard yet; when it gets one it goes outside this route,
/// never behind a flag here — a suppressible footer is a footer that is
/// suppressed.
class SupportShell extends StatefulWidget {
  final Widget child;

  /// The route the shell is showing. It travels with the message so whoever
  /// answers knows where the bug was — "it broke" and "it broke on the reader"
  /// are different bug reports. **Only the shell knows this**, which is the
  /// practical half of why the footer is the shell's and not a screen's.
  final String route;

  const SupportShell({super.key, required this.child, required this.route});

  @override
  State<SupportShell> createState() => _SupportShellState();
}

class _SupportShellState extends State<SupportShell> {
  @override
  void initState() {
    super.initState();
    // The subscription starts HERE, not on the Support screen: the badge is on
    // every screen, so the thread has to be live before the user ever opens
    // the conversation. Starting it from the screen would leave the count at
    // zero until someone happened to visit.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SupportNotifier>().start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    // The badge is the one thing the footer reads. `watch` on the count alone
    // keeps every screen in the app from rebuilding when a message arrives.
    final unread = context.select<SupportNotifier, int>((s) => s.unreadForUser);

    return Material(
      color: t.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: widget.child),
          KitSupportFooter(
            unread: unread,
            onOpen: () {
              if (widget.route == supportRoute) return;
              context.go(
                '$supportRoute?from=${Uri.encodeComponent(widget.route)}',
              );
            },
          ),
        ],
      ),
    );
  }
}

const String supportRoute = '/support';

/// The navigator this shell owns.
///
/// It exists so INV-22's gate can find this exact `ShellRoute` in the route
/// table by **identity** rather than by assuming it is the first one. A test
/// that guesses which shell is the footer's would keep passing after someone
/// added a second one above it.
final GlobalKey<NavigatorState> supportShellNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'support-shell');
