//
//  ProcessTap.swift
//  AudioSDK
//
//  Manages the Core Audio tap and aggregate device lifecycle for recording from a process.
//

import Foundation
import AudioToolbox
import AVFoundation
import OSLog

final class ProcessTap {
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

    var currentFileURL: URL? {
        return currentFile?.url
    }

    init(pid: pid_t, objectID: AudioObjectID, outputDeviceID: AudioDeviceID, logger: Logger) {
        self.pid = pid
        self.objectID = objectID
        self.outputDeviceID = outputDeviceID
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
        guard err == noErr else { throw RecordingError.general("Failed to create process tap: \(osStatusDescription(err))") }
        self.processTapID = tapID
        let outputUID = try outputDeviceID.readDeviceUID()
        let aggregateUID = UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SDK-Tap-\(pid)",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapDescription.uuid.uuidString]]
        ]
        var tapStreamDescription = try tapID.readAudioTapStreamBasicDescription()
        guard tapStreamDescription.mFormatID == kAudioFormatLinearPCM,
              (tapStreamDescription.mFormatFlags & kAudioFormatFlagIsFloat) != 0 else {
            throw RecordingError.general("Unsupported audio format. The SDK currently only supports Linear PCM float audio streams.")
        }
        systemOutputDeviceID = .unknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &systemOutputDeviceID)
        guard err == noErr else { throw RecordingError.general("Failed to create system output device (aggregate): \(osStatusDescription(err))") }
        logger.debug("System output device (aggregate) #\(self.systemOutputDeviceID, privacy: .public) created.")
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
        logger.info("Recording to file: \(fileURL.path, privacy: .public)")
        logger.info("Audio format: sampleRate=\(format.sampleRate, privacy: .public), channels=\(format.channelCount, privacy: .public)")
        logger.info("Tap device ID: \(self.processTapID, privacy: .public), System output device (aggregate) ID: \(self.systemOutputDeviceID, privacy: .public)")
        err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, systemOutputDeviceID, queue) { [weak self] _, inData, _, _, _ in
            guard let self, let currentFile = self.currentFile else { return }
            // PCM buffer writing logic would go here
        }
        guard err == noErr else { throw RecordingError.general("Failed to create IO proc: \(osStatusDescription(err))") }
        err = AudioDeviceStart(systemOutputDeviceID, deviceProcID)
        guard err == noErr else { throw RecordingError.general("Failed to start system output device (aggregate): \(osStatusDescription(err))") }
        isRecording = true
    }

    func stopRecording() {
        guard isRecording else { return }
        logger.debug("Stopping recording...")
        isRecording = false
        currentFile = nil
        if systemOutputDeviceID != .unknown, let procID = deviceProcID {
            _ = AudioDeviceStop(systemOutputDeviceID, procID)
            _ = AudioDeviceDestroyIOProcID(systemOutputDeviceID, procID)
            self.deviceProcID = nil
        }
        if systemOutputDeviceID != .unknown {
            _ = AudioHardwareDestroyAggregateDevice(systemOutputDeviceID)
            self.systemOutputDeviceID = .unknown
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