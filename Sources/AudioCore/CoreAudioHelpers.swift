import AppKit
import CoreAudio
import Foundation

// MARK: - Errors and logging

public struct CAError: Error, CustomStringConvertible {
    public let status: OSStatus
    public let what: String

    public var description: String { "\(what) failed: \(fourCC(status))" }
}

func check(_ status: OSStatus, _ what: String) throws {
    if status != noErr { throw CAError(status: status, what: what) }
}

/// Core Audio errors are often four-character codes such as 'who?'.
func fourCC(_ status: OSStatus) -> String {
    let n = UInt32(bitPattern: status)
    let bytes = [24, 16, 8, 0].map { UInt8((n >> UInt32($0)) & 0xFF) }
    if bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) {
        return "'" + String(decoding: bytes, as: UTF8.self) + "' (\(status))"
    }
    return "\(status)"
}

private let startTime = Date()

public func log(_ message: String) {
    let t = Date().timeIntervalSince(startTime)
    print(String(format: "[%8.3f] ", t) + message)
    fflush(stdout)
}

// MARK: - Property access

func propertyAddress(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    /// Reads a fixed-size property (UInt32, pid_t, AudioObjectID, ...).
    func read<T>(_ selector: AudioObjectPropertySelector, initial: T) throws -> T {
        var address = propertyAddress(selector)
        var size = UInt32(MemoryLayout<T>.size)
        var value = initial
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0)
        }
        try check(status, "read \(fourCC(OSStatus(bitPattern: selector))) on \(self)")
        return value
    }

    /// Reads a property that is an array of AudioObjectIDs.
    func readObjectIDs(_ selector: AudioObjectPropertySelector) throws -> [AudioObjectID] {
        var address = propertyAddress(selector)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size), "size of object list")
        let count = Int(size) / MemoryLayout<AudioObjectID>.stride
        var ids = [AudioObjectID](repeating: .unknown, count: count)
        try check(AudioObjectGetPropertyData(self, &address, 0, nil, &size, &ids), "read object list")
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride))
    }

    /// Reads a CFString property. Returns nil when the property is empty.
    func readString(_ selector: AudioObjectPropertySelector) throws -> String? {
        var address = propertyAddress(selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0)
        }
        try check(status, "read string \(fourCC(OSStatus(bitPattern: selector)))")
        guard let value else { return nil }
        let string = value.takeRetainedValue() as String
        return string.isEmpty ? nil : string
    }
}

// MARK: - Audio processes

/// The private libSystem call macOS uses to attribute helper processes
/// (WebKit GPU, Chrome helpers) to the app that launched them.
/// Fine for a spike; the real app must not depend on it.
private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
private let responsiblePIDFn: ResponsibleFn? = {
    guard let handle = dlopen(nil, RTLD_NOW),
          let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid")
    else { return nil }
    return unsafeBitCast(symbol, to: ResponsibleFn.self)
}()

public struct AudioProcess: Sendable {
    public let objectID: AudioObjectID
    public let pid: pid_t
    public let bundleID: String?
    public let isRunningOutput: Bool
    public let responsiblePID: pid_t
    public let responsibleBundleID: String?

    /// The bundle ID a user would recognise: the responsible app's, if any.
    public var appBundleID: String? { responsibleBundleID ?? bundleID }

    /// Matches the target bundle ID itself, its helpers (bundle ID prefix),
    /// or anything macOS says the target app is responsible for.
    public func matches(_ target: String) -> Bool {
        if bundleID == target || responsibleBundleID == target { return true }
        if let bundleID, bundleID.hasPrefix(target + ".") { return true }
        return false
    }
}

public func listAudioProcesses() throws -> [AudioProcess] {
    try AudioObjectID.system.readObjectIDs(kAudioHardwarePropertyProcessObjectList).compactMap { id in
        guard let pid = try? id.read(kAudioProcessPropertyPID, initial: pid_t(-1)), pid > 0 else {
            return nil
        }
        let bundleID = try? id.readString(kAudioProcessPropertyBundleID)
        let running = (try? id.read(kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))) ?? 0
        let responsible = responsiblePIDFn?(pid) ?? pid
        let responsibleBundle = responsible != pid
            ? NSRunningApplication(processIdentifier: responsible)?.bundleIdentifier
            : nil
        return AudioProcess(
            objectID: id,
            pid: pid,
            bundleID: bundleID ?? nil,
            isRunningOutput: running != 0,
            responsiblePID: responsible,
            responsibleBundleID: responsibleBundle
        )
    }
}

public func defaultOutputDeviceUID() throws -> String {
    let device = try AudioObjectID.system.read(kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID.unknown)
    guard device != .unknown, let uid = try device.readString(kAudioDevicePropertyDeviceUID) else {
        throw CAError(status: -1, what: "find default output device")
    }
    return uid
}

/// Keeps a Core Audio property listener installed until it is cancelled or released.
public final class PropertyListener {
    private var address: AudioObjectPropertyAddress
    private let queue: DispatchQueue
    private let block: AudioObjectPropertyListenerBlock
    private var active = true

    fileprivate init(selector: AudioObjectPropertySelector, queue: DispatchQueue, handler: @escaping () -> Void) throws {
        self.address = propertyAddress(selector)
        self.queue = queue
        self.block = { _, _ in handler() }
        try check(AudioObjectAddPropertyListenerBlock(.system, &address, queue, block), "add listener")
    }

    public func cancel() {
        guard active else { return }
        active = false
        AudioObjectRemovePropertyListenerBlock(.system, &address, queue, block)
    }

    deinit { cancel() }
}

/// Calls `handler` on `queue` whenever a system-object property changes,
/// until the returned listener is cancelled or released.
public func onSystemChange(
    _ selector: AudioObjectPropertySelector,
    queue: DispatchQueue,
    _ handler: @escaping () -> Void
) throws -> PropertyListener {
    try PropertyListener(selector: selector, queue: queue, handler: handler)
}
