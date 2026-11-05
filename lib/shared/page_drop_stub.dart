import 'package:flutter/foundation.dart';

import 'page_drop.dart';

/// A device build: no page-wide drop (the drop zone and the picker are the way
/// in), so nothing listens.
VoidCallback attach(PageDropController controller) => () {};
