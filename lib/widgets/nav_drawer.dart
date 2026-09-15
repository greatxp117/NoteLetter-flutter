import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'sidebar.dart';

/// The compact form of the chrome rail (`component-kit.md` §1.1): the rail
/// becomes a drawer.
///
/// **It renders [RailContent] — the same rail the wide viewport draws**, as
/// the reference's `Drawer` renders the same `SidebarContent` its sidebar
/// does. What was here was a second navigation: *Daily Digest*, *Knowledge
/// Base*, a `/library` route this app does not serve, Welcome and Branding as
/// primary destinations, plain `ListTile` rows with their own type, no library
/// card, no group labels, no identity footer — and, once the unread badge
/// existed, no badge, on the viewport where the drawer IS the nav.
///
/// Nothing could have gone red for that. A second nav is not a wrong nav to
/// any gate; it is only wrong beside the first one, which is why it survived
/// every screen recomposition that went past it.
class NavDrawer extends StatelessWidget {
  const NavDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.chrome,
      // The rail's own padding is §1.2's; the drawer adds only the device's
      // safe area, so the brand lockup clears the notch.
      child: SafeArea(
        child: RailContent(onNavigate: () => Navigator.of(context).pop()),
      ),
    );
  }
}
