import Foundation
import AudioToolbox
import AVFoundation
import OSLog

public enum RecordingError: Error, LocalizedError {
    case general(String)

    public var errorDescription: String? {
        switch self {
        case .general(let message):
            return message
        }
    }
}

public final class AudioRecorder {
    private let logger = Logger(subsystem: "com.audiocap.sdk", category: "AudioRecorder")
    private var tap: ProcessTap?

    public init() {}

    public func startRecording(pid: pid_t, outputFile: URL) throws {
        let objectID = try AudioObjectID.translatePIDToProcessObjectID(pid: pid)
        
        let newTap = ProcessTap(pid: pid, objectID: objectID, logger: logger)
        try newTap.startRecording(to: outputFile)

        self.tap = newTap
    }

    public func stopRecording() {
        tap?.stopRecording()
        tap = nil
    }
}

// MARK: - Internal Implementation (based on the working app code)

fileprivate final class ProcessTap {
    private let pid: pid_t
    private let objectID: AudioObjectID
    private let logger: Logger
    private let queue = DispatchQueue(label: "ProcessTapRecorder", qos: .userInitiated)

    private var processTapID: AudioObjectID = .unknown
    private var aggregateDeviceID: AudioObjectID = .unknown
    private var deviceProcID: AudioDeviceIOProcID?
    
    private var isRecording = false
    private var currentFile: AVAudioFile?

    init(pid: pid_t, objectID: AudioObjectID, logger: Logger) {
        self.pid = pid
        self.objectID = objectID
        self.logger = logger
    }

    func startRecording(to fileURL: URL) throws {
        guard !isRecording else {
            logger.warning("startRecording() called while already recording.")
            return
        }

        logger.debug("Activating audio tap for pid \(self.pid)...")

        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [objectID])
        tapDescription.uuid = UUID()
        
        var tapID: AUAudioObjectID = .unknown
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard err == noErr else { throw RecordingError.general("Failed to create process tap: \(err)") }
        self.processTapID = tapID

        let systemOutputID = try AudioObjectID.readDefaultSystemOutputDevice()
        let outputUID = try systemOutputID.readDeviceUID()
        let aggregateUID = UUID().uuidString

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SDK-Tap-\(pid)",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapDescription.uuid.uuidString]]
        ]

        var tapStreamDescription = try tapID.readAudioTapStreamBasicDescription()
        
        aggregateDeviceID = .unknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)
        guard err == noErr else { throw RecordingError.general("Failed to create aggregate device: \(err)") }

        logger.debug("Aggregate device #\(self.aggregateDeviceID, privacy: .public) created.")

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

        err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue) { [weak self] _, inData, _, _, _ in
            guard let self, let currentFile = self.currentFile else { return }

            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inData) else {
                self.logger.warning("Failed to create PCM buffer from incoming data.")
                return
            }
            
            do {
                try currentFile.write(from: pcmBuffer)
            } catch {
                self.logger.error("Failed to write audio buffer to file: \(error.localizedDescription)")
            }
        }
        guard err == noErr else { throw RecordingError.general("Failed to create IO proc: \(err)") }

        err = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard err == noErr else { throw RecordingError.general("Failed to start audio device: \(err)") }
        
        isRecording = true
        logger.debug("Recording started.")
    }

    func stopRecording() {
        guard isRecording else { return }
        
        logger.debug("Stopping recording...")

        isRecording = false
        currentFile = nil

        if aggregateDeviceID != .unknown, let procID = deviceProcID {
            _ = AudioDeviceStop(aggregateDeviceID, procID)
            _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            self.deviceProcID = nil
        }
        
        if aggregateDeviceID != .unknown {
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            self.aggregateDeviceID = .unknown
        }

        if processTapID != .unknown {
            _ = AudioHardwareDestroyProcessTap(processTapID)
            self.processTapID = .unknown
        }
        
        logger.debug("Recording stopped and resources cleaned up.")
    }

    deinit {
        if isRecording {
            stopRecording()
        }
    }
}


// MARK: - CoreAudio Helpers (from CoreAudioUtils.swift)

fileprivate extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = kAudioObjectUnknown
    var isValid: Bool { self != .unknown }

    static func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        var deviceID: AudioDeviceID = .unknown
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let err = AudioObjectGetPropertyData(.system, &address, 0, nil, &size, &deviceID)
        guard err == noErr else { throw RecordingError.general("Failed to get default system output device: \(err)") }
        return deviceID
    }

    static func translatePIDToProcessObjectID(pid: pid_t) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var processID = pid
        var objectID: AudioObjectID = .unknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        
        let err = AudioObjectGetPropertyData(
            AudioObjectID.system,
            &address,
            UInt32(MemoryLayout.size(ofValue: processID)),
            &processID,
            &size,
            &objectID
        )

        guard err == noErr else {
            throw RecordingError.general("Failed to translate PID to object ID: \(err)")
        }

        guard objectID != .unknown else {
            throw RecordingError.general("Process \(pid) has no audio object representation")
        }

        return objectID
    }
    
    func readDeviceUID() throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString?>.size)
        let err = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0)
        }
        guard err == noErr else { throw RecordingError.general("Failed to read device UID for object \(self): \(err)") }
        return uid as String
    }
    
    func readAudioTapStreamBasicDescription() throws -> AudioStreamBasicDescription {
        var description = AudioStreamBasicDescription()
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let err = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &description)
        guard err == noErr else { throw RecordingError.general("Failed to read audio tap stream description for object \(self): \(err)") }
        return description
    }

    func read<T>(_ property: AudioObjectPropertySelector, defaultValue: T? = nil) throws -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: property,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size)

        guard err == noErr else { throw RecordingError.general("Failed to read size for property \(property) on object \(self): \(err)") }

        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }

        err = AudioObjectGetPropertyData(self, &address, 0, nil, &size, pointer)

        guard err == noErr else { throw RecordingError.general("Failed to read data for property \(property) on object \(self): \(err)") }

        if T.self == String.self {
            let cfString = pointer.load(as: CFString.self)
            return (cfString as String) as! T
        }

        return pointer.load(as: T.self)
    }
} 
