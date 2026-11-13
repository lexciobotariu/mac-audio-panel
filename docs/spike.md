# audiotap (M0 spike)

A throwaway command-line tool that answers one question before we build the app:
**can a Core Audio process tap mute a single app on its own?**

Requires macOS 14.4+ and Xcode 15.3+ (or the matching Command Line Tools).

## Build

From the repository root:

```sh
make cli                      # builds .build/release/audiotap
cp .build/release/audiotap /usr/local/bin/   # optional
```

## Use

```sh
audiotap list              # apps playing sound right now
audiotap list --all        # every process that has used Core Audio
audiotap mute com.spotify.client                       # default mode: muted+reader
audiotap mute com.spotify.client --mode muted
audiotap mute com.spotify.client --mode when-tapped
```

`mute` keeps running and logs what it sees. Press Ctrl-C to unmute and quit.

The first time a tap is created, macOS asks to allow **system audio recording**.
Because this runs from a terminal, the prompt names your terminal app
(Terminal, iTerm, ...). Allow it. If you denied it earlier, turn it on in
System Settings > Privacy & Security > Screen & System Audio Recording.

## What to test

Finding so far (2026-11-13, Chrome): a plain `.muted` tap does **not** silence
the app; it only mutes once something reads the tap. `muted+reader` (now the
default) and `when-tapped` both work. Run the rows below with the default mode.

| # | Scenario | How |
|---|----------|-----|
| 1 | Basic mute | Play Spotify, `audiotap mute com.spotify.client`. Silent? Ctrl-C. Sound back? |
| 2 | Crash safety | While muted, `kill -9` the audiotap process from another terminal. Sound back? |
| 3 | Relaunch | While muted, quit and reopen Spotify, press play. Any sound before the log says MUTED? |
| 4 | Output switch | While muted, switch output (speakers → headphones / display). Still silent? |
| 5 | Browser tabs | `audiotap mute com.google.Chrome` (or Dia's bundle ID from `audiotap list`). Open a new tab with a video. Silent? |
| 6 | Safari | `audiotap list` while Safari plays: which process shows as PLAYING (look for `com.apple.WebKit.GPU`)? Does `audiotap mute com.apple.Safari` silence it? |
| 7 | Podcasts | `audiotap mute com.apple.podcasts`. |
| 8 | Sleep / wake | Mute, sleep the Mac, wake it. Still silent? |
| 9 | Recording indicator | While muted, is there a recording indicator in the menu bar? |

Paste the terminal output of anything that fails into the PR or project thread.

## Results

Fill in after testing (✅ / ❌ / notes).

| # | `muted` | `muted+reader` | `when-tapped` | Notes |
|---|---------|----------------|---------------|-------|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |
| 4 | | | | |
| 5 | | | | |
| 6 | | | | |
| 7 | | | | |
| 8 | | | | |
| 9 | | | | |

macOS version tested:
