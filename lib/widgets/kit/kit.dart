/// The NoteLetter component kit — the **composition** layer.
///
/// One widget per named pattern in `../../../NoteLetter-contracts/spec/
/// component-kit.md`. Screens compose from these; they do not build their own.
///
/// Why this exists (ADR-041): this client reached full feature parity, a
/// current contract pin and a green device run **with no component layer at
/// all**. Every screen composed `Padding`/`Column`/`Card` inline, so every
/// screen re-derived the app's look independently and eleven screens drifted
/// eleven different ways — while tokens, conformance and the device run all
/// stayed correctly green, because none of them look at composition.
///
/// The rule that keeps that from recurring is structural, not stylistic:
/// **a page file never styles its own type or spacing.** If a screen needs
/// something this kit does not have, the fix is a new kit widget (and a
/// `/contract-change` if it is a new pattern), never a local `TextStyle`.
library;

export 'kit_cards.dart';
export 'kit_composer.dart';
export 'kit_controls.dart';
export 'kit_empty.dart';
export 'kit_frame.dart';
export 'kit_ground.dart';
export 'kit_headers.dart';
export 'kit_rows.dart';
export 'kit_shell.dart';
export 'kit_support_footer.dart';
export 'kit_text.dart';
