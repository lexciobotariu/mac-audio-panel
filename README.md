# Mac Audio Panel

A macOS menu-bar panel for muting individual apps. V1 does one thing: list the
apps playing sound and mute or unmute any of them with one click.

It uses Core Audio process taps (macOS 14.4+), so there is no audio driver to
install. See [docs/spike.md](docs/spike.md) for how muting was proven.

## Build and run

Needs macOS 14.4+ and Xcode 15.3+ (or the Command Line Tools: `xcode-select --install`).

```sh
make run      # builds build/MacAudioPanel.app and opens it
```

A speaker icon appears in the menu bar. The first time you mute an app, macOS
asks to allow **system audio recording** for Mac Audio Panel; allow it.

Because local builds are signed ad hoc, macOS may ask again after a rebuild.

Other targets:

```sh
make app      # build the .app only
make cli      # build the audiotap command-line tool
make clean
```

## Layout

| Path | What |
| --- | --- |
| `Sources/AudioCore` | Core Audio process listing and per-app muting (no UI) |
| `Sources/MacAudioPanel` | SwiftUI menu-bar app |
| `Sources/audiotap` | Command-line debugging tool from the M0 spike |
| `scripts/build-app.sh` | Wraps the binary into a signed `.app` |
