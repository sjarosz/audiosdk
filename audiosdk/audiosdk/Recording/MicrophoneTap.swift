//
//  MicrophoneTap.swift
//  AudioSDK
//
//  Manages input device (microphone) recording lifecycle.
//

import Foundation
import AVFoundation
import OSLog

/// Manages input device (microphone) recording lifecycle.
/// Handles permission, format, file writing, and resource cleanup for input device audio capture.
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

    /// Initialize a MicrophoneTap for a given input device
    /// - Parameters:
    ///   - logger: Logger for diagnostics
    init(logger: Logger) {
        self.logger = logger
    }

    /// Start recording from the input device to a file
    /// - Parameter fileURL: The file to write audio to
    /// - Throws: RecordingError if permission, format, or device issues occur
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

    /// Stop recording and clean up resources
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

    /// Check microphone permission synchronously
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
