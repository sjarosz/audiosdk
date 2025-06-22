//
//  MicrophoneTap.swift
//  AudioSDK
//
//  Manages microphone recording using AVAudioEngine.
//

import Foundation
import AVFoundation
import OSLog

/// Manages recording from the system's default input device using `AVAudioEngine`.
///
/// This class handles microphone permissions, audio capture, and file writing.
/// It is a high-level abstraction over `AVAudioEngine` and does not support
/// selection of a specific input device; it will always use the system default.
internal final class MicrophoneTap {
    /// Logger for diagnostics
    private let logger: Logger
    /// Audio engine for capturing audio
    private let audioEngine = AVAudioEngine()
    /// Audio file for writing
    private var audioFile: AVAudioFile?
    /// Flag to track recording state
    private var isRecording = false

    /// Current file URL being written to
    var currentFileURL: URL? { return audioFile?.url }

    /// True if currently recording
    var isActive: Bool { isRecording }

    /// Initializes the microphone tap.
    /// - Parameter logger: A logger for diagnostics.
    init(logger: Logger) {
        self.logger = logger
    }

    /// Starts recording from the default microphone to the specified file.
    ///
    /// This function will request microphone permission if it has not already been granted.
    /// It configures the audio engine, installs a tap on the input node, and starts writing
    /// audio data to the file.
    /// - Parameter fileURL: The URL of the file to write the recording to.
    /// - Throws: A `RecordingError` if permission is denied, the audio format is invalid,
    ///   or the audio engine fails to start.
    func startRecording(to fileURL: URL) throws {
        guard !isRecording else {
            logger.warning("startRecording() called while already recording.")
            return
        }

        let permissionGranted = try checkMicrophonePermission()
        guard permissionGranted else {
            throw RecordingError.microphonePermissionDenied
        }

        // Get the input node and its format
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Validate format
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecordingError.microphoneFormatUnsupported("Invalid audio format from input device")
        }

        // Create audio file for writing
        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: inputFormat.settings)

            // Install tap on input node
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                guard let self = self, let audioFile = self.audioFile else { return }
                do {
                    try audioFile.write(from: buffer)
                } catch {
                    self.logger.error("Failed to write audio buffer: \(error.localizedDescription)")
                }
            }

            // Start the audio engine
            try audioEngine.start()
            isRecording = true

            logger.info("Microphone recording started to file: \(fileURL.path)")

        } catch {
            // Clean up if something went wrong
            audioEngine.inputNode.removeTap(onBus: 0)
            audioFile = nil
            throw RecordingError.audioEngineError("Failed to start recording: \(error.localizedDescription)")
        }
    }

    /// Stops the recording, removes the audio tap, and cleans up resources.
    func stopRecording() {
        guard isRecording else { return }
        logger.debug("Stopping microphone recording...")

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioFile = nil
        isRecording = false
        logger.debug("Microphone recording stopped and resources cleaned up.")
    }

    deinit {
        if isRecording {
            stopRecording()
        }
    }

    /// Checks for microphone permission and requests it if necessary.
    ///
    /// This function synchronously checks the current authorization status. If it's
    /// `notDetermined`, it will block while prompting the user for permission.
    /// - Returns: `true` if permission is granted, `false` otherwise.
    private func checkMicrophonePermission() throws -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .audio) { result in
                granted = result
                semaphore.signal()
            }
            semaphore.wait()
            return granted
        @unknown default:
            return false
        }
    }
}

// Example usage:
// let tap = MicrophoneTap(inputDeviceID: 42, logger: Logger(subsystem: "test", category: "mic"))
// try tap.startRecording(to: URL(fileURLWithPath: "/tmp/mic.wav"))
// Thread.sleep(forTimeInterval: 5.0) // Record for 5 seconds
// tap.stopRecording()
