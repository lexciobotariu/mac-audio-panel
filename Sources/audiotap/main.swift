import Foundation
import AudioCore

let usage = """
audiotap: M0 spike for per-app mute with Core Audio process taps.

USAGE
  audiotap list [--all]
      Apps using Core Audio. --all also shows processes that are not playing.

  audiotap mute <bundle-id> [--mode muted|muted+reader|when-tapped]
      Mutes every audio process of the app (helpers included) until Ctrl-C.
      Keeps following the app: relaunches and new helper processes are re-muted.
      Modes:
        muted+reader   .muted tap + private aggregate device reading it (default)
        muted          .muted tap, nothing reads it (does NOT mute on its own; kept for reference)
        when-tapped    .mutedWhenTapped tap + reader (fallback)

EXAMPLES
  audiotap list
  audiotap mute com.spotify.client
  audiotap mute com.google.Chrome --mode when-tapped
"""

func runList(showAll: Bool) {
    let processes: [AudioProcess]
    do {
        processes = try listAudioProcesses()
    } catch {
        print("error: \(error)")
        exit(1)
    }
    let shown = processes
        .filter { showAll || $0.isRunningOutput }
        .sorted { ($0.appBundleID ?? "", $0.pid) < ($1.appBundleID ?? "", $1.pid) }

    let header = "STATE    PID     OBJ   BUNDLE ID                                     APP (responsible)"
    print(header)
    print(String(repeating: "-", count: header.count))
    for p in shown {
        let state = p.isRunningOutput ? "PLAYING" : "silent "
        let bundle = (p.bundleID ?? "?").padding(toLength: 45, withPad: " ", startingAt: 0)
        let app = p.responsibleBundleID.map { "\($0) (pid \(p.responsiblePID))" } ?? "-"
        print("\(state)  \(String(p.pid).padding(toLength: 6, withPad: " ", startingAt: 0))  "
            + "\(String(p.objectID).padding(toLength: 4, withPad: " ", startingAt: 0))  \(bundle) \(app)")
    }
    if shown.isEmpty {
        print(showAll ? "(no audio processes)" : "(nothing playing; try --all)")
    }
}

var activeMuter: Muter?
var signalSources: [DispatchSourceSignal] = []

func runMute(target: String, mode: Muter.Mode) {
    let muter = Muter(target: target, mode: mode)
    activeMuter = muter
    log("muting \(target), mode \(mode.rawValue). Ctrl-C to unmute and quit.")

    for sig in [SIGINT, SIGTERM] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler {
            activeMuter?.stop()
            exit(0)
        }
        source.resume()
        signalSources.append(source)
    }

    do {
        try muter.start()
    } catch {
        log("ERROR: \(error)")
        exit(1)
    }
    dispatchMain()
}

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "list":
    runList(showAll: arguments.contains("--all"))

case "mute":
    guard arguments.count >= 2, !arguments[1].hasPrefix("-") else {
        print(usage)
        exit(2)
    }
    var mode = Muter.Mode.mutedWithReader
    if let i = arguments.firstIndex(of: "--mode") {
        guard i + 1 < arguments.count, let parsed = Muter.Mode(rawValue: arguments[i + 1]) else {
            print("unknown mode; use muted, muted+reader or when-tapped")
            exit(2)
        }
        mode = parsed
    }
    runMute(target: arguments[1], mode: mode)

case nil, "help", "-h", "--help":
    print(usage)

default:
    print(usage)
    exit(2)
}
