import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/link.dart';

/// component-kit §6.4.3 (4.84.0, ADR-118) — every control that opens a source
/// in the reader is the platform's LINK primitive, not a bare tap target. The
/// reference renders `<a href="/reader/{id}">` (`shared/SourceLink.jsx`); a
/// button gave the browser no address, so a new-tab gesture had nothing to
/// open. On Flutter web `Link` lays a real anchor over the control.
///
/// A plain tap still runs the in-app navigation ([onOpen], default a
/// `context.push` of the reader route) — **not** `followLink`, which would hand
/// the route to the router a second time as a `go`. `followLink` is called only
/// under a modifier (cmd/ctrl/shift), which is when url_launcher_web lets the
/// browser follow the anchor itself; without that signal it prevents the
/// browser's navigation, so the plain path never double-navigates.
class KitSourceLink extends StatelessWidget {
  final String docId;

  /// Query string (without `?`) appended to the reader route, e.g. `p=<chunk>`.
  final String? query;

  /// The in-app open. Defaults to pushing [readerHref].
  final VoidCallback? onOpen;

  /// Builds the control; wire the given callback as its tap.
  final Widget Function(BuildContext context, VoidCallback open) builder;

  const KitSourceLink({
    super.key,
    required this.docId,
    required this.builder,
    this.query,
    this.onOpen,
  });

  /// The reader route a source opens at — the link's address.
  static String readerHref(String docId, [String? query]) =>
      '/reader/$docId${(query == null || query.isEmpty) ? '' : '?$query'}';

  static bool _modifier() {
    final k = HardwareKeyboard.instance;
    return k.isMetaPressed || k.isControlPressed || k.isShiftPressed;
  }

  @override
  Widget build(BuildContext context) {
    final href = readerHref(docId, query);
    return Link(
      uri: Uri.parse(href),
      builder: (context, followLink) => builder(context, () {
        if (_modifier() && followLink != null) {
          followLink();
          return;
        }
        (onOpen ?? () => context.push(href))();
      }),
    );
  }
}
