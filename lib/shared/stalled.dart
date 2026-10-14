import '../models/document.dart';

/// The sentence a stalled run draws (web `shared/stalled.js`). There is no
/// `error_message` on a stalled document — nothing failed, a run stopped
/// existing — so the row needs copy of its own, saying the two things the
/// reader cannot see: that waiting will not help, and that Retry costs them
/// nothing already spent. The copy follows the status (sources.md §Stalled
/// rows, ruled 2026-10-13): a `queued` run never started, so it has nothing to
/// finish. Sources, For your review and Activity (activity.md §The row, ruled
/// 2026-10-14) all draw it — one spelling, here.
const stalledProcMsg =
    'Indexing stopped before it finished. Waiting will not help — Retry to start it again.';
const stalledQueuedMsg =
    'Indexing never started. Waiting will not help — Retry to start it.';

String stalledMessage(Document doc) =>
    doc.status == DocumentStatus.queued ? stalledQueuedMsg : stalledProcMsg;
