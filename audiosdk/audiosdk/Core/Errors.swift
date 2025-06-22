//
//  Errors.swift
//  AudioSDK
//
//  Defines all error types for the AudioSDK.
//

import Foundation

/// Errors thrown by the AudioSDK, with localized human-readable description.
/// Includes device, process, format, permission, and simultaneous recording errors.
public enum RecordingError: Error, LocalizedError {
    case general(String)
    case deviceNotFound(String)
    case processNotFound(pid_t)
    case audioFormatUnsupported(String)
    case permissionDenied(String)
    case recordingInProgress
    /// Thrown when the specified input device is not found by name
    case inputDeviceNotFound(String)
    /// Thrown when the specified input device is not available (by ID)
    case inputDeviceNotAvailable(Int)
    /// Thrown when microphone permission is denied
    case microphonePermissionDenied
    /// Thrown when the microphone format is unsupported
    case microphoneFormatUnsupported(String)
    /// Thrown when simultaneous process+microphone recording fails
    case simultaneousRecordingFailed(String)
    /// Thrown when an input device stream error occurs
    case inputDeviceStreamError(String)
    /// Thrown when an AVAudioEngine error occurs
    case audioEngineError(String)

    public var errorDescription: String? {
        switch self {
        case .general(let message):
            return message
        case .deviceNotFound(let name):
            return "Audio device not found: \(name)"
        case .processNotFound(let pid):
            return "Audio process not found for PID: \(pid)"
        case .audioFormatUnsupported(let desc):
            return "Audio format unsupported: \(desc)"
        case .permissionDenied(let reason):
            return "Permission denied: \(reason)"
        case .recordingInProgress:
            return "A recording is already in progress."
        case .inputDeviceNotFound(let name):
            return "Input audio device not found: \(name)"
        case .inputDeviceNotAvailable(let id):
            return "Input audio device not available: \(id)"
        case .microphonePermissionDenied:
            return "Microphone permission denied."
        case .microphoneFormatUnsupported(let desc):
            return "Microphone format unsupported: \(desc)"
        case .simultaneousRecordingFailed(let reason):
            return "Simultaneous recording failed: \(reason)"
        case .inputDeviceStreamError(let desc):
            return "Input device stream error: \(desc)"
        case .audioEngineError(let reason):
            return "Audio engine error: \(reason)"
        }
    }
}

// Example usage:
// throw RecordingError.inputDeviceNotFound("USB Microphone") 
