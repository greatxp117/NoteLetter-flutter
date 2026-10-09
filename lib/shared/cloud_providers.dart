import 'package:flutter/material.dart';

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
    icon: Icons.add_to_drive_outlined
  ),
  'onedrive': (
    name: 'OneDrive',
    sub: 'Files & folders',
    icon: Icons.cloud_outlined
  ),
  'notion': (
    name: 'Notion',
    sub: 'Pages & databases',
    icon: Icons.article_outlined
  ),
  'dropbox': (
    name: 'Dropbox',
    sub: 'Files & folders',
    icon: Icons.inventory_2_outlined
  ),
};
