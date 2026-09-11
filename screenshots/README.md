# Screenshots

The artifact of the fidelity ritual (ADR-041 §5): a **pair of pairs** per screen —

    <screen>.flutter.light.png   <screen>.flutter.dark.png
    <screen>.web.light.png       <screen>.web.dark.png

refreshed **in the same commit as the screen**. `<screen>` is the name from
`NoteLetter-web/scripts/theme-shots.mjs`, so the two clients' frames pair by name. A stale or
half pair is a failure the way an undeployed index is — a ritual whose only output is prose in a
task summary cannot be shown to have run — and `harness/screenshot_pair_check.py`
(`/conformance` 5aa) fails on a missing theme, a missing or stale web frame, and a done
`QUEUE.md` item whose files were committed after its frames.

**Capture:** `tool/shots.sh <screen> <route> [HOLD_STATE]` drives
`integration_test/hold_screen_test.dart` on the iPhone 17 simulator against the emulator suite and
catches each theme with `xcrun simctl io <UDID> screenshot` — by **UDID**, never `booted`: two
simulators are routinely booted here. **Both themes, always**: the ground tile rendered as a solid
white veil in dark mode for the whole life of the shell commit, and light-only verification could
never have seen it.

**Reference:** `tool/web_frames.sh <screen>` copies the web frame from `NoteLetter-web/screenshots/`
(the source, shot there and committed there). If it is absent, shoot it in the web repo first:
`VITE_USE_EMULATOR=true npm run dev` then `node scripts/theme-shots.mjs --only <screen>`.

Then **look at all four**, composition first (`/design-fidelity`). The gate proves the pair
exists and is current; only a person looking proves it matches.
