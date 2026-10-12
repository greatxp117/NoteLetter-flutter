import 'package:flutter/material.dart';

import '../widgets/kit/kit_provider_logo.dart';

/// Canonical provider ids (1.2.0) with display names for not-yet-connected
/// providers (the integration list only carries connected ones). The ids are
/// exactly the backend provider strings — earlier web builds passed `gdrive`
/// and got a 400.
///
/// One table for every surface that names a provider — Sources' connect grid
/// and "Import from" headers, and Settings' Organization rows — in the
/// reference's connect-grid order (web `CONNECTORS`).
const cloudProviders = <String, ({String name, String sub, IconData icon})>{
  'google_drive': (
    name: 'Google Drive',
    sub: 'Docs, PDFs, slides',
    icon: KitProviderLogo.googleDrive
  ),
  'onedrive': (
    name: 'OneDrive',
    sub: 'Files & folders',
    icon: KitProviderLogo.oneDrive
  ),
  'notion': (
    name: 'Notion',
    sub: 'Pages & databases',
    icon: KitProviderLogo.notion
  ),
  'dropbox': (
    name: 'Dropbox',
    sub: 'Files & folders',
    icon: KitProviderLogo.dropbox
  ),
};
