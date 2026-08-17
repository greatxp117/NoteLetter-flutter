# Screenshots

The artifact of the fidelity ritual (ADR-041 §5): `<screen>.<client>.<theme>.png`,
refreshed **in the same commit as the screen**. A stale pair is a failure the way
an undeployed index is — a ritual whose only output is prose in a task summary
cannot be shown to have run.

Captured from the real app on the iOS simulator (iPhone 17) against the emulator
suite: `integration_test/hold_screen_test.dart` holds one route in each theme
(ports and invocation in its header) while `xcrun simctl io booted screenshot`
catches it. **Both themes, always**: the ground tile rendered as a solid white
veil in dark mode for the whole life of the shell commit, and light-only
verification could never have seen it.

Still owed: the **web reference frame** beside each pair. The ritual wants the
comparison in the repo, not only the client side of it.
