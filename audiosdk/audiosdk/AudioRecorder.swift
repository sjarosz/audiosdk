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
    private var microphoneTap: MicrophoneTap?
    public var outputDirectory: URL?
    /// Optional closure to run after a process recording completes
    public var postProcessingHandler: ((URL) -> Void)?
    /// Optional closure for microphone post-processing
    /// Called after microphone recording stops, with the file URL.
    public var microphonePostProcessingHandler: ((URL) -> Void)?

    public init() {
        // On init, attempt to clean up any orphaned tap or aggregate devices left over from previous runs
        OrphanedResourceCleaner.cleanupOrphanedAudioObjects(logger: logger)
    }

    /// Start recording with optional microphone input
    /// - Parameters:
    ///   - pid: Process ID to record
    ///   - outputFile: File for process audio
    ///   - microphoneFile: Optional file for microphone audio
    ///   - outputDeviceID: Optional output device (default: system output)
    ///   - inputDeviceID: Optional input device (default: system input)
    public func startRecording(
        pid: pid_t,
        outputFile: URL,
        microphoneFile: URL? = nil,
        outputDeviceID: Int? = nil,
        inputDeviceID: Int? = nil
    ) throws {
        stopBothRecordings()
        var processTap: ProcessTap?
        var micTap: MicrophoneTap?
        do {
            // Start process tap
            let objectID = try AudioObjectID.translatePIDToProcessObjectID(pid: pid)
            let resolvedOutputDevice: AudioDeviceID = outputDeviceID != nil ? AudioDeviceID(outputDeviceID!) : try AudioObjectID.readDefaultSystemOutputDevice()
            let newTap = ProcessTap(pid: pid, objectID: objectID, outputDeviceID: resolvedOutputDevice, logger: logger)
            try newTap.startRecording(to: outputFile)
            processTap = newTap

            // Start microphone tap if requested
            if let micFile = microphoneFile {
                // Warn user if a specific device was requested, as the new implementation uses the default.
                if inputDeviceID != nil {
                    logger.warning("A specific input device ID was provided, but the current implementation only supports the default system input. The selection will be ignored.")
                }
                
                let newMicTap = MicrophoneTap(logger: logger)
                try newMicTap.startRecording(to: micFile)
                micTap = newMicTap
            }
            self.tap = processTap
            self.microphoneTap = micTap
        } catch {
            processTap?.stopRecording()
            micTap?.stopRecording()
            throw RecordingError.simultaneousRecordingFailed(error.localizedDescription)
        }
    }

    /// Convenience method using device names
    public func startRecording(
        processName: String,
        outputFile: URL,
        microphoneFile: URL? = nil,
        outputDeviceName: String? = nil,
        inputDeviceName: String? = nil
    ) throws {
        guard let pid = AudioRecorder.pidForAudioCapableProcess(named: processName) else {
            throw RecordingError.processNotFound(-1)
        }
        let outputDeviceID = outputDeviceName.flatMap { AudioRecorder.deviceIDForOutputDevice(named: $0) }
        let inputDeviceID = inputDeviceName.flatMap { DeviceDiscovery.findInputDevice(named: $0)?.id }.map { Int($0) }
        try startRecording(pid: pid, outputFile: outputFile, microphoneFile: microphoneFile, outputDeviceID: outputDeviceID, inputDeviceID: inputDeviceID)
    }

    /// Stop both process and microphone recordings, trigger post-processing handlers, and clean up resources.
    public func stopRecording() {
        stopBothRecordings()
    }

    private func stopBothRecordings() {
        let processFileURL = tap?.currentFileURL
        let micFileURL = microphoneTap?.currentFileURL
        tap?.stopRecording()
        microphoneTap?.stopRecording()
        tap = nil
        microphoneTap = nil
        if let handler = postProcessingHandler, let url = processFileURL {
            handler(url)
        }
        if let micHandler = microphonePostProcessingHandler, let micURL = micFileURL {
            micHandler(micURL)
        }
    }

    /// Get currently recording microphone file URL
    /// Returns the file URL being written to by the microphone tap, or nil if not recording.
    public var currentMicrophoneFileURL: URL? {
        return microphoneTap?.currentFileURL
    }

    /// Check if microphone recording is active
    /// Returns true if microphone tap is recording, false otherwise.
    public var isMicrophoneRecording: Bool {
        return microphoneTap?.isActive ?? false
    }

    /// Enumerate output audio devices present on the system.
    public static func listOutputAudioDevices() -> [AudioDeviceInfo] {
        return DeviceDiscovery.listOutputAudioDevices()
    }

    /// List all available input audio devices (microphones, etc).
    public static func listInputAudioDevices() -> [AudioDeviceInfo] {
        return DeviceDiscovery.listInputAudioDevices()
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
        return ProcessDiscovery.listAudioCapableProcesses()
    }

    /// Returns the PID of the first audio-capable process matching the given name (case-insensitive).
    /// - Parameter name: The process name to search for.
    /// - Returns: The PID if found, or nil if not found.
    public static func pidForAudioCapableProcess(named name: String) -> pid_t? {
        return ProcessDiscovery.pidForAudioCapableProcess(named: name)
    }

    /// Returns the device ID (as Int) for the first output device matching the given name (case-insensitive).
    /// - Parameter name: The device name to search for.
    /// - Returns: The device ID as Int if found, or nil if not found.
    public static func deviceIDForOutputDevice(named name: String) -> Int? {
        return DeviceDiscovery.listOutputAudioDevices().first { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map { Int($0.id) }
    }
}

// Example usage:
// let recorder = AudioRecorder()
// try recorder.startRecording(
//     pid: 1234,
//     outputFile: URL(fileURLWithPath: "/tmp/process.wav"),
//     microphoneFile: URL(fileURLWithPath: "/tmp/mic.wav")
// )
// ...
// recorder.stopRecording()

// TODO: Add integration tests for AudioRecorder in AudioRecorderTests.swift


