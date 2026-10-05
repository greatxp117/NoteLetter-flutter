/// The app's notifiers, in ONE list — the app, the device run and the
/// screenshot hold all build the tree from this.
///
/// Until 2026-10-05 the list was spelled three times (`main.dart`,
/// `integration_test/device_run_test.dart`, `hold_screen_test.dart`), and
/// F-72 (4.100.0) added `ReviewInbox` to the first only. `AppLayout` and the
/// rail read it on every authenticated screen, so every hold and every device
/// test would have drawn a ProviderNotFoundError wall where the screen should
/// be — while analyze and the contract suite stayed green, because neither
/// builds the app's tree. A copy of a list is a list that drifts.
library;

import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'state/activity_notifier.dart';
import 'state/auth_notifier.dart';
import 'state/chat_notifier.dart';
import 'state/cloud_notifier.dart';
import 'state/documents_notifier.dart';
import 'state/newsletter_notifier.dart';
import 'state/org_notifier.dart';
import 'state/review_inbox.dart';
import 'state/scripture_letter_notifier.dart';
import 'state/search_notifier.dart';
import 'state/settings_notifier.dart';
import 'state/support_notifier.dart';
import 'state/tags_notifier.dart';
import 'state/theme_notifier.dart';
import 'state/upload_notifier.dart';

/// [theme] is passed by a caller that drives the theme itself (the hold
/// switches light → dark); otherwise the app makes its own.
List<SingleChildWidget> appProviders(AuthNotifier auth, {ThemeNotifier? theme}) => [
      ChangeNotifierProvider<AuthNotifier>.value(value: auth),
      ChangeNotifierProvider<UploadNotifier>(create: (_) => UploadNotifier()),
      ChangeNotifierProvider<SearchNotifier>(create: (_) => SearchNotifier()),
      ChangeNotifierProvider<ChatNotifier>(create: (_) => ChatNotifier()),
      ChangeNotifierProvider<ActivityNotifier>(
        create: (_) => ActivityNotifier(),
      ),
      ChangeNotifierProvider<DocumentsNotifier>(
        create: (_) => DocumentsNotifier(),
      ),
      ChangeNotifierProvider<SettingsNotifier>(
        create: (_) => SettingsNotifier(),
      ),
      ChangeNotifierProvider<NewsletterNotifier>(
        create: (_) => NewsletterNotifier(),
      ),
      // The readings letter's own settings document (ADR-029) — separate
      // from the daily letter's, exactly as its endpoint is.
      ChangeNotifierProvider<ScriptureLetterNotifier>(
        create: (_) => ScriptureLetterNotifier(),
      ),
      ChangeNotifierProvider<CloudNotifier>(create: (_) => CloudNotifier()),
      ChangeNotifierProvider<OrgNotifier>(create: (_) => OrgNotifier()),
      // For your review's one inbox (4.100.0, ADR-135, INV-30): the rail's
      // attention count and the page read this same object.
      ChangeNotifierProvider<ReviewInbox>(create: (_) => ReviewInbox()),
      ChangeNotifierProvider<TagsNotifier>(create: (_) => TagsNotifier()),
      // INV-22: every authenticated screen sits inside SupportShell, which
      // reads this.
      ChangeNotifierProvider<SupportNotifier>(
        create: (_) => SupportNotifier(),
      ),
      if (theme != null)
        ChangeNotifierProvider<ThemeNotifier>.value(value: theme)
      else
        ChangeNotifierProvider<ThemeNotifier>(create: (_) => ThemeNotifier()),
    ];
