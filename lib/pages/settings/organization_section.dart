import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/cloud_integration.dart';
import '../../shared/cloud_providers.dart';
import '../../state/cloud_notifier.dart';
import '../../state/org_notifier.dart';
import '../../widgets/kit/kit.dart';

/// Settings → Organization (`screens/settings.md` §Organization card, 1.2.0;
/// web `SettingsView` `OrganizationSection`): one row per CONNECTED provider,
/// and the door to organizing it — **Enable organizing**, which explains the
/// write-scope grant and hands off to the provider (`fn_enable_organization`).
///
/// It lived on the connect card's in-card actions ("Enable
/// auto-organization") until the 2026-10-08 ruling made the card fixed. A
/// control that leaves a surface has to land somewhere, or the feature
/// silently has no door: this is where the reference and the spec keep it.
///
/// Once a provider's grant is write-ready (`organization.enabled` AND
/// `write_access`), the row points at Sources, where this client draws the
/// capability flags, the threshold and the organized folders
/// (`OrganizationSettingsPanel`). The reference draws the threshold and the
/// three toggles here instead — a placement difference this section does not
/// reopen.
///
/// Nothing is drawn while no provider is connected, as on the reference.
class OrganizationSection extends StatefulWidget {
  const OrganizationSection({super.key});

  @override
  State<OrganizationSection> createState() => _OrganizationSectionState();
}

class _OrganizationSectionState extends State<OrganizationSection> {
  /// The reference's order for this section (web `ORG_PROVIDERS`), which is
  /// not the connect grid's.
  static const _order = ['google_drive', 'onedrive', 'dropbox', 'notion'];

  String? _busy;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Without this read every provider renders as NOT connected, which is an
    // invitation to connect an account that is already connected (§14).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CloudNotifier?>()?.loadIntegrations();
    });
  }

  Future<void> _enable(String provider) async {
    final org = context.read<OrgNotifier?>();
    if (org == null) return;
    setState(() {
      _busy = provider;
      _error = null;
    });
    final err = await org.enableOrganization(provider);
    if (!mounted) return;
    setState(() {
      _busy = null;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudNotifier?>();
    if (cloud == null) return const SizedBox.shrink();
    final connected = <(String, CloudIntegration)>[
      for (final p in _order)
        if (cloud.integrationFor(p) case final i?) (p, i),
    ];
    if (connected.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Organization'),
        KitRowList(
          raised: true,
          rows: [
            for (final (p, i) in connected)
              KitSettingRow(
                icon: cloudProviders[p]!.icon,
                title: cloudProviders[p]!.name,
                description: i.orgWriteReady
                    ? null
                    : (!i.orgEnabled && i.orgScopeLevel == 'read'
                        ? 'Write access wasn’t granted — reconnect and approve '
                            'all permissions to turn organization on.'
                        : 'Organizing needs permission to move files and '
                            'write READMEs in your storage. You’ll approve '
                            'this with the provider.'),
                trailing: [
                  if (i.orgWriteReady)
                    KitSettingLink('Choose organized folders in Sources',
                        onTap: () => context.go('/sources'))
                  else
                    KitSettingLink('Enable organizing',
                        onTap: _busy != null ? null : () => _enable(p)),
                ],
              ),
          ],
        ),
        if (_error != null) KitFailureInline(_error!),
      ],
    );
  }
}
