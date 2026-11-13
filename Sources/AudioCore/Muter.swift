import CoreAudio
import Foundation

/// Keeps every audio process of one app muted with a single process tap,
/// following the app as processes come and go.
public final class Muter {
    public enum Mode: String, Sendable {
        /// `.muted` tap, nobody reads it. The cheapest option, if it works.
        case muted
        /// `.muted` tap plus a private aggregate device that reads and discards it.
        case mutedWithReader = "muted+reader"
        /// `.mutedWhenTapped` tap plus the reader (what Mimir/AudioCap-style tools do).
        case mutedWhenTapped = "when-tapped"

        var muteBehavior: CATapMuteBehavior {
            self == .mutedWhenTapped ? .mutedWhenTapped : .muted
        }

        var needsReader: Bool { self != .muted }
    }

    public let target: String
    public let mode: Mode
    let queue = DispatchQueue(label: "audiotap.muter")

    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?
    private var tappedObjects: Set<AudioObjectID> = []
    private var runningOutput: [AudioObjectID: Bool] = [:]

    public init(target: String, mode: Mode) {
        self.target = target
        self.mode = mode
    }

    /// Starts watching. Everything after this runs on `queue`.
    public func start() throws {
        listeners.append(try onSystemChange(kAudioHardwarePropertyProcessObjectList, queue: queue) { [weak self] in
            log("process list changed")
            self?.refresh()
        })
        listeners.append(try onSystemChange(kAudioHardwarePropertyDefaultOutputDevice, queue: queue) { [weak self] in
            let uid = (try? defaultOutputDeviceUID()) ?? "?"
            log("default output changed to \(uid)")
            self?.rebuildReaderIfNeeded()
        })
        // A device appearing or disappearing (display, headphones) can kill the
        // reader's aggregate even when the default output stays the same.
        listeners.append(try onSystemChange(kAudioHardwarePropertyDevices, queue: queue) { [weak self] in
            log("device list changed")
            self?.rebuildReaderIfNeeded()
        })
        // Backup poll: also reports when the app starts or stops producing sound.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume()
        self.timer = timer

        queue.sync { refresh() }
    }

    private var timer: DispatchSourceTimer?
    private var listeners: [PropertyListener] = []
    private var readerOutputUID: String?

    /// Recreates the tap and reader from scratch, e.g. after the Mac wakes.
    public func rebuild() {
        queue.async { [weak self] in
            guard let self else { return }
            log("rebuilding mute for \(self.target)")
            self.tappedObjects = []
            self.refresh()
        }
    }

    /// Rebuilds only when the output the reader is attached to is no longer the
    /// default. Our own aggregate devices also change the device list, so a
    /// blind rebuild here would loop forever.
    private func rebuildReaderIfNeeded() {
        guard mode.needsReader, !tappedObjects.isEmpty else { return }
        let current = try? defaultOutputDeviceUID()
        guard current != readerOutputUID else { return }
        log("rebuilding reader for \(target): output is now \(current ?? "?")")
        tappedObjects = []
        refresh()
    }

    public func stop() {
        listeners.forEach { $0.cancel() }
        listeners = []
        queue.sync {
            timer?.cancel()
            destroy(tap: tapID, aggregate: aggregateID, ioProc: ioProcID)
            tapID = .unknown
            aggregateID = .unknown
            ioProcID = nil
            log("unmuted \(target)")
        }
    }

    // MARK: - Private

    private func refresh() {
        let processes: [AudioProcess]
        do {
            processes = try listAudioProcesses().filter { $0.matches(target) }
        } catch {
            log("could not list processes: \(error)")
            return
        }

        for p in processes where runningOutput[p.objectID] != p.isRunningOutput {
            let name = p.bundleID ?? "pid \(p.pid)"
            log("\(name) (pid \(p.pid)) is \(p.isRunningOutput ? "PLAYING" : "silent")")
            runningOutput[p.objectID] = p.isRunningOutput
        }

        let ids = Set(processes.map(\.objectID))
        guard ids != tappedObjects else { return }

        for p in processes where !tappedObjects.contains(p.objectID) {
            log("found \(p.bundleID ?? "?") pid \(p.pid) (object \(p.objectID))")
        }

        if ids.isEmpty {
            if tapID != .unknown {
                destroy(tap: tapID, aggregate: aggregateID, ioProc: ioProcID)
                tapID = .unknown
                aggregateID = .unknown
                ioProcID = nil
                log("\(target) has no audio processes left; tap removed")
            } else {
                log("waiting for \(target) to start using audio")
            }
            tappedObjects = []
            runningOutput = [:]
            return
        }

        do {
            try rebuild(with: ids.sorted())
            tappedObjects = ids
        } catch {
            log("ERROR: \(error)")
        }
    }

    /// Creates the new tap before destroying the old one, so there is no gap.
    private func rebuild(with objects: [AudioObjectID]) throws {
        let started = DispatchTime.now()

        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        description.uuid = UUID()
        description.name = "audiotap \(target)"
        description.isPrivate = true
        description.muteBehavior = mode.muteBehavior

        var newTap = AudioObjectID.unknown
        try check(AudioHardwareCreateProcessTap(description, &newTap), "AudioHardwareCreateProcessTap")

        var newAggregate = AudioObjectID.unknown
        var newIOProc: AudioDeviceIOProcID?
        if mode.needsReader {
            do {
                (newAggregate, newIOProc) = try startReader(tapUUID: description.uuid)
            } catch {
                AudioHardwareDestroyProcessTap(newTap)
                throw error
            }
        }

        destroy(tap: tapID, aggregate: aggregateID, ioProc: ioProcID)
        tapID = newTap
        aggregateID = newAggregate
        ioProcID = newIOProc

        let ms = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        log(String(format: "MUTED %@: tap %u over %d process(es), mode %@, took %.1f ms",
                   target, newTap, objects.count, mode.rawValue, ms))
    }

    /// A private aggregate device on the current output whose IOProc reads the tap
    /// and writes silence.
    private func startReader(tapUUID: UUID) throws -> (AudioObjectID, AudioDeviceIOProcID?) {
        let outputUID = try defaultOutputDeviceUID()
        readerOutputUID = outputUID
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "audiotap reader",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapUUID.uuidString,
            ]],
        ]

        var aggregate = AudioObjectID.unknown
        try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate), "AudioHardwareCreateAggregateDevice")

        var ioProc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, nil) { _, _, _, output, _ in
            // Discard the tapped audio and make sure the output stays silent.
            for buffer in UnsafeMutableAudioBufferListPointer(output) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
        }
        if status != noErr {
            AudioHardwareDestroyAggregateDevice(aggregate)
            throw CAError(status: status, what: "AudioDeviceCreateIOProcIDWithBlock")
        }

        // A fresh aggregate is sometimes not ready immediately; retry briefly.
        var startStatus = AudioDeviceStart(aggregate, ioProc)
        var attempts = 0
        while startStatus != noErr, attempts < 10 {
            usleep(50_000)
            attempts += 1
            startStatus = AudioDeviceStart(aggregate, ioProc)
        }
        if startStatus != noErr {
            destroy(tap: .unknown, aggregate: aggregate, ioProc: ioProc)
            throw CAError(status: startStatus, what: "AudioDeviceStart")
        }
        if attempts > 0 { log("reader started after \(attempts) retries") }
        return (aggregate, ioProc)
    }

    private func destroy(tap: AudioObjectID, aggregate: AudioObjectID, ioProc: AudioDeviceIOProcID?) {
        if aggregate != .unknown {
            if let ioProc {
                AudioDeviceStop(aggregate, ioProc)
                AudioDeviceDestroyIOProcID(aggregate, ioProc)
            }
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        if tap != .unknown {
            AudioHardwareDestroyProcessTap(tap)
        }
    }
}
