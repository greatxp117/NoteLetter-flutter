# NoteLetter — Flutter client

The whole NoteLetter app in Flutter, composed from a named component kit
(`lib/widgets/kit/`) against the contract in `../NoteLetter-contracts/`. The web app
(`../NoteLetter-web/`) is the reference implementation; this client matches it screen by screen.

- **Rules and traps:** [`CLAUDE.md`](CLAUDE.md)
- **What this client must satisfy:** `../NoteLetter-contracts/spec/clients/flutter.md`
- **What is owed, in order:** [`QUEUE.md`](QUEUE.md) — worked by `/flutter-next`, refreshed by
  `/parity flutter`, linted by `python3 tool/queue.py lint`

## Run

```bash
flutter pub get
tool/dev.sh chrome          # iterate (emulator; refuses unless the suite is proven ours)
tool/dev.sh ios             # the iPhone 17 simulator
```

Development is emulator-only (umbrella law 1). A bare `flutter run` in debug refuses to boot
against prod; `tool/dev.sh` passes the emulator defines, and `--dart-define=ALLOW_PROD=true` is
the deliberate override. The emulator suite comes up per `/emu`; the functions shim is
`NoteLetter-Firebase-Functions/functions/dev_server.py`.

## Gates

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test test/contract test/kit -x pin      # queue mode; the pin is held by policy
tool/device_test.sh ["<test name>"]             # the device run, or one test of it
tool/shots.sh <screen> <route> && tool/web_frames.sh <screen>   # the screenshot pair
```

The full battery is `/conformance`; the umbrella harness gates that read this repo are listed in
`spec/clients/flutter.md` §Conformance.
