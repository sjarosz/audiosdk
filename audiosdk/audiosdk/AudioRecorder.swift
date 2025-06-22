import Foundation
import AudioToolbox
import AVFoundation
import OSLog
import Security
import Accelerate
import Darwin
import CoreAudio
//import AudioSDK_Core



// MARK: - Audio Recorder SDK

/// High-level object for managing per-process audio capture via Core Audio.
/// Handles starting/stopping taps, device cleanup, and output file coordination.
public final class AudioRecorder {
    private let logger = Logger(subsystem: "com.audiocap.sdk", category: "AudioRecorder")
    private var tap: ProcessTap?
    public var outputDirectory: URL?
    /// Optional closure to run after a recording completes (can be used for post-processing or notifications)
    public var postProcessingHandler: ((URL) -> Void)?

    public init() {
        // On init, attempt to clean up any orphaned tap or aggregate devices left over from previous runs
        cleanupOrphanedAudioObjects()
    }

    /// Start recording output from a process.
    /// - Parameters:
    ///   - pid: The PID of the target process whose audio will be tapped.
    ///   - outputFile: File location to save the audio.
    ///   - outputDeviceID: Optional output device ID (default: system output).
    public func startRecording(pid: pid_t, outputFile: URL, outputDeviceID: Int? = nil) throws {
        // Translate PID to the corresponding Core Audio object ID
        let objectID = try AudioObjectID.translatePIDToProcessObjectID(pid: pid)
        // Determine which device to route audio through (system output by default)
        let resolvedOutputDevice: AudioDeviceID
        if let outputDeviceID = outputDeviceID {
            resolvedOutputDevice = AudioDeviceID(outputDeviceID)
        } else {
            resolvedOutputDevice = try AudioObjectID.readDefaultSystemOutputDevice()
        }
        // Create and start a tap for the process
        let newTap = ProcessTap(pid: pid, objectID: objectID, outputDeviceID: resolvedOutputDevice, logger: logger)
        try newTap.startRecording(to: outputFile)
        self.tap = newTap
    }

    /// Stop any ongoing recording and trigger the post-processing handler if present.
    public func stopRecording() {
        let fileURL = tap?.currentFileURL

        tap?.stopRecording()
        tap = nil

        // Optionally perform post-processing (such as moving, uploading, etc.)
        if let handler = postProcessingHandler, let url = fileURL {
            handler(url)
        }
    }

    /// Search for and destroy any orphaned aggregate/tap devices created by the SDK but not cleaned up (e.g., after a crash).
    private func cleanupOrphanedAudioObjects() {
        logger.info("Scanning for orphaned SDK-Tap devices and process taps...")
        // Query all audio devices
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID.system, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else {
            logger.error("Failed to get device list size: \(osStatusDescription(status))")
            return
        }
        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: .unknown, count: deviceCount)
        status = AudioObjectGetPropertyData(AudioObjectID.system, &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else {
            logger.error("Failed to get device list: \(osStatusDescription(status))")
            return
        }
        // Inspect each device for "SDK-Tap-" naming pattern
        for deviceID in deviceIDs {
            // Query device name
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString?>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let nameStatus = withUnsafeMutablePointer(to: &name) {
                AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, $0)
            }
            let deviceName = (nameStatus == noErr) ? (name as String) : ""
            // Query device UID (unique identifier)
            var uid: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString?>.size)
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let uidStatus = withUnsafeMutablePointer(to: &uid) {
                AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, $0)
            }
            let deviceUID = (uidStatus == noErr) ? (uid as String) : ""
            // Destroy if it's a tap or aggregate device from this SDK
            if deviceName.hasPrefix("SDK-Tap-") || deviceUID.hasPrefix("SDK-Tap-") {
                // Attempt to destroy as aggregate device
                let destroyAggStatus = AudioHardwareDestroyAggregateDevice(deviceID)
                if destroyAggStatus == noErr {
                    logger.info("Destroyed orphaned aggregate device: \(deviceName, privacy: .public) [UID: \(deviceUID, privacy: .public)]")
                    continue
                }
                // Attempt to destroy as process tap
                let destroyTapStatus = AudioHardwareDestroyProcessTap(deviceID)
                if destroyTapStatus == noErr {
                    logger.info("Destroyed orphaned process tap: \(deviceName, privacy: .public) [UID: \(deviceUID, privacy: .public)]")
                    continue
                }
                logger.warning("Failed to destroy orphaned device: \(deviceName, privacy: .public) [UID: \(deviceUID, privacy: .public)] (aggStatus=\(destroyAggStatus), tapStatus=\(destroyTapStatus))")
            }
        }
        logger.info("Orphaned SDK-Tap device/process tap cleanup complete.")
    }

    /// Enumerate output audio devices present on the system.
    public static func listOutputAudioDevices() -> [AudioDeviceInfo] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID.system, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return [] }
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(AudioObjectID.system, &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else { return [] }
        var outputDevices: [AudioDeviceInfo] = []
        for deviceID in deviceIDs {
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString?>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let nameStatus = withUnsafeMutablePointer(to: &name) {
                AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, $0)
            }
            if nameStatus != noErr { continue }
            // Fetch UID
            var uid: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString?>.size)
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let uidStatus = withUnsafeMutablePointer(to: &uid) {
                AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, $0)
            }
            if uidStatus != noErr { continue }
            // Only include devices that actually have output audio streams
            var streamsSize: UInt32 = 0
            var streamsAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            let streamsStatus = AudioObjectGetPropertyDataSize(deviceID, &streamsAddress, 0, nil, &streamsSize)
            if streamsStatus == noErr, streamsSize > 0 {
                outputDevices.append(AudioDeviceInfo(id: deviceID, name: name as String, uid: uid as String, isInput: false, isOutput: true))
            }
        }
        return outputDevices
    }

    /// List all available input audio devices (microphones, etc).
    public static func listInputAudioDevices() -> [AudioDeviceInfo] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID.system, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return [] }
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(AudioObjectID.system, &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else { return [] }
        var inputDevices: [AudioDeviceInfo] = []
        for deviceID in deviceIDs {
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString?>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let nameStatus = withUnsafeMutablePointer(to: &name) {
                AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, $0)
            }
            if nameStatus != noErr { continue }
            // Fetch UID
            var uid: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString?>.size)
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let uidStatus = withUnsafeMutablePointer(to: &uid) {
                AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, $0)
            }
            if uidStatus != noErr { continue }
            // Only include devices that actually have input audio streams
            var streamsSize: UInt32 = 0
            var streamsAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            let streamsStatus = AudioObjectGetPropertyDataSize(deviceID, &streamsAddress, 0, nil, &streamsSize)
            if streamsStatus == noErr, streamsSize > 0 {
                inputDevices.append(AudioDeviceInfo(id: deviceID, name: name as String, uid: uid as String, isInput: true, isOutput: false))
            }
        }
        return inputDevices
    }

    /// Returns a list of running processes that are audio-capable (i.e., have a valid CoreAudio object).
    ///
    /// This function enumerates all running processes on the system and attempts to translate each PID
    /// to a CoreAudio AudioObjectID. Only processes that CoreAudio recognizes as having an audio object
    /// (i.e., are capable of being tapped for audio output) are included in the result.
    ///
    /// - Returns: An array of (pid, name) tuples for all audio-capable processes.
    /// - Note: This does not guarantee the process is currently producing audio, only that it is recognized by CoreAudio.
    public static func listAudioCapableProcesses() -> [(pid: pid_t, name: String)] {
        var result: [(pid_t, String)] = []
        // Get all running PIDs using Darwin's proc_listallpids
        var procCount = proc_listallpids(nil, 0)
        guard procCount > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(procCount))
        procCount = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        for pid in pids where pid > 0 {
            // Get process name using proc_name
            var nameBuf = [CChar](repeating: 0, count: 1024)
            let nameResult = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let procName = nameResult > 0 ? String(cString: nameBuf) : "(unknown)"
            // Try to get AudioObjectID for this PID; if it throws, the process is not audio-capable
            do {
                _ = try AudioObjectID.translatePIDToProcessObjectID(pid: pid)
                result.append((pid, procName))
            } catch {
                continue // PID not associated with audio
            }
        }
        return result
    }

    /// Returns the PID of the first audio-capable process matching the given name (case-insensitive).
    /// - Parameter name: The process name to search for.
    /// - Returns: The PID if found, or nil if not found.
    public static func pidForAudioCapableProcess(named name: String) -> pid_t? {
        let procs = listAudioCapableProcesses()
        return procs.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.pid
    }

    /// Returns the device ID (as Int) for the first output device matching the given name (case-insensitive).
    /// - Parameter name: The device name to search for.
    /// - Returns: The device ID as Int if found, or nil if not found.
    public static func deviceIDForOutputDevice(named name: String) -> Int? {
        let devices = listOutputAudioDevices()
        return devices.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map { Int($0.id) }
    }
}

// MARK: - Internal Implementation (ProcessTap)

/// Manages the Core Audio tap and aggregate device lifecycle for recording from a process.
/// Handles all audio buffer delivery, IOProc setup, and writing to disk.
fileprivate final class ProcessTap {
    private let pid: pid_t
    private let objectID: AudioObjectID
    private let outputDeviceID: AudioDeviceID
    private let logger: Logger
    private let queue = DispatchQueue(label: "ProcessTapRecorder", qos: .userInitiated)

    private var processTapID: AudioObjectID = .unknown
    private var systemOutputDeviceID: AudioObjectID = .unknown
    private var deviceProcID: AudioDeviceIOProcID?

    private var isRecording = false
    private var currentFile: AVAudioFile?

    /// The output file URL currently being written to (if any)
    var currentFileURL: URL? {
        return currentFile?.url
    }

    /// Initialize a tap for a specific process and audio output device.
    init(pid: pid_t, objectID: AudioObjectID, outputDeviceID: AudioDeviceID, logger: Logger) {
        self.pid = pid
        self.objectID = objectID
        self.outputDeviceID = outputDeviceID
        self.logger = logger
    }

    /// Start recording: create tap, create system output device (aggregate), start IO proc, and begin writing to file.
    func startRecording(to fileURL: URL) throws {
        guard !isRecording else {
            logger.warning("startRecording() called while already recording.")
            return
        }

        logger.debug("Activating audio tap for pid \(self.pid)...")

        // Build tap descriptor for target process
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [objectID])
        tapDescription.uuid = UUID() // Assign a fresh UUID for this tap session

        var tapID: AUAudioObjectID = .unknown
        // Create Core Audio tap for the given process
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard err == noErr else { throw RecordingError.general("Failed to create process tap: \(osStatusDescription(err))") }
        self.processTapID = tapID

        // Create a CoreAudio aggregate device (systemOutputDeviceID) that combines the tap and the real output device
        let outputUID = try outputDeviceID.readDeviceUID()
        let aggregateUID = UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SDK-Tap-\(pid)",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapDescription.uuid.uuidString]]
        ]

        // Get audio format details from tap (sample rate, channels, PCM type, etc)
        var tapStreamDescription = try tapID.readAudioTapStreamBasicDescription()
        // Enforce float PCM format (as used by AVAudioFile in this implementation)
        guard tapStreamDescription.mFormatID == kAudioFormatLinearPCM,
              (tapStreamDescription.mFormatFlags & kAudioFormatFlagIsFloat) != 0 else {
            throw RecordingError.general("Unsupported audio format. The SDK currently only supports Linear PCM float audio streams.")
        }

        systemOutputDeviceID = .unknown
        // Create the system output device (aggregate device) for routing audio (the tap plus the output device)
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &systemOutputDeviceID)
        guard err == noErr else { throw RecordingError.general("Failed to create system output device (aggregate): \(osStatusDescription(err))") }

        logger.debug("System output device (aggregate) #\(self.systemOutputDeviceID, privacy: .public) created.")

        // Prepare an AVAudioFile for writing the captured stream
        guard let format = AVAudioFormat(streamDescription: &tapStreamDescription) else {
            throw RecordingError.general("Failed to create AVAudioFormat from stream description.")
        }
        let settings: [String: Any] = [
            AVFormatIDKey: tapStreamDescription.mFormatID,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount
        ]
        let file = try AVAudioFile(forWriting: fileURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
        self.currentFile = file

        // Log device info and format
        logger.info("Recording to file: \(fileURL.path, privacy: .public)")
        logger.info("Audio format: sampleRate=\(format.sampleRate, privacy: .public), channels=\(format.channelCount, privacy: .public)")
        logger.info("Tap device ID: \(self.processTapID, privacy: .public), System output device (aggregate) ID: \(self.systemOutputDeviceID, privacy: .public)")

        // Register I/O proc callback that receives PCM buffers in real time from the system output device (aggregate)
        err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, systemOutputDeviceID, queue) { [weak self] _, inData, _, _, _ in
            guard let self, let currentFile = self.currentFile else { return }

            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inData) else {
                self.logger.warning("Failed to create PCM buffer from incoming data.")
                return
            }

            // --- RMS/Decibel computation for each channel (can be used for live metering in UI) ---
            let frameLength = Int(pcmBuffer.frameLength)
            for channel in 0..<Int(pcmBuffer.format.channelCount) {
                if let floatChannelData = pcmBuffer.floatChannelData?[channel] {
                    let buffer = UnsafeBufferPointer(start: floatChannelData, count: frameLength)
                    let rms = vDSP.rootMeanSquare(buffer)
                    let db = 20 * log10(rms)
                    // Example: self.logger.info("[RMS] Channel \(channel): RMS=\(rms), dB=\(db)")
                    // Optionally notify UI or observers about RMS/dB for visualization
                }
            }
            // --- End RMS/Decibel computation ---

            do {
                // Write captured audio buffer to file
                try currentFile.write(from: pcmBuffer)
            } catch {
                self.logger.error("Failed to write audio buffer to file: \(error.localizedDescription)")
            }
        }
        guard err == noErr else { throw RecordingError.general("Failed to create IO proc: \(osStatusDescription(err))") }

        // Start the system output device (aggregate), which begins the callback and audio streaming
        err = AudioDeviceStart(systemOutputDeviceID, deviceProcID)
        guard err == noErr else { throw RecordingError.general("Failed to start system output device (aggregate): \(osStatusDescription(err))") }

        isRecording = true
        logger.debug("Recording started.")
    }

    /// Stop the recording session and clean up all Core Audio resources
    func stopRecording() {
        guard isRecording else { return }

        logger.debug("Stopping recording...")

        isRecording = false
        currentFile = nil

        // Stop and remove IO proc from system output device (aggregate)
        if systemOutputDeviceID != .unknown, let procID = deviceProcID {
            _ = AudioDeviceStop(systemOutputDeviceID, procID)
            _ = AudioDeviceDestroyIOProcID(systemOutputDeviceID, procID)
            self.deviceProcID = nil
        }

        // Destroy system output device (aggregate) (removes from Core Audio device list)
        if systemOutputDeviceID != .unknown {
            _ = AudioHardwareDestroyAggregateDevice(systemOutputDeviceID)
            self.systemOutputDeviceID = .unknown
        }

        // Destroy process tap device
        if processTapID != .unknown {
            _ = AudioHardwareDestroyProcessTap(processTapID)
            self.processTapID = .unknown
        }

        logger.debug("Recording stopped and resources cleaned up.")
    }

    deinit {
        // Auto-clean up on deallocation if not already done
        if isRecording {
            stopRecording()
        }
    }
}
