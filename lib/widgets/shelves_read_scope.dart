import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../shared/shelf_pick.dart';
import '../state/tags_notifier.dart';
import 'kit/kit.dart';

/// Provides [KitShelvesRead] from the app's ONE tags subscription
/// ([TagsNotifier]), above every route and overlay, so each §20 host knows
/// whether the shelves it lists were read, are still out, or were refused
/// (INV-24, F-196; web `App.jsx`'s `ShelvesReadProvider`). A tree with no
/// [TagsNotifier] — a bare widget test — reads as answered.
class ShelvesReadScope extends StatelessWidget {
  final Widget child;
  const ShelvesReadScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final tags = context.watch<TagsNotifier?>();
    final error = tags?.error;
    final read = tags == null
        ? ShelvesRead.answered
        : error != null
            ? ShelvesRead.failed
            : tags.loading
                ? ShelvesRead.loading
                : ShelvesRead.answered;
    return KitShelvesRead(read: read, error: error, child: child);
  }
}
