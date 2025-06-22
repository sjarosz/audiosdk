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
        OrphanedResourceCleaner.cleanupOrphanedAudioObjects(logger: logger)
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

