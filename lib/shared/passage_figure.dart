/// One source's passage figure (screens/library.md §States, *a passage figure
/// needs a count* — ruled by Xavier 2026-10-14; ADR-109). Web
/// `shared/passageFigure.js`.
///
/// `chunk_count` is a measurement only when it is a number. `null` is a count
/// NEVER TAKEN — a source indexed before the field, or a re-derive that
/// cleared it in its claim (5.4.0, ADR-162) — so it draws nothing: no figure,
/// no "0 passages", no dash. Every per-source site wrote `chunkCount ?? 0`,
/// which turned "never counted" into "0 passages", a figure nobody measured.
/// A measured 0 is a measurement and keeps its figure.
///
/// This is about ONE source. A total over several (a shelf's head, the rail,
/// the Sources total) adds the counts that exist and is not changed by it.
library;

/// "4 passages", "1 passage", "0 passages" — or null when never counted.
String? passagesLabel(int? count) =>
    count == null ? null : '$count passage${count == 1 ? '' : 's'}';
