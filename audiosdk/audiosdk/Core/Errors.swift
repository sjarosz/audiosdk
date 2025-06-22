//
//  Errors.swift
//  AudioSDK
//
//  Defines all error types for the AudioSDK.
//

import Foundation

/// Errors thrown by the AudioSDK, with localized human-readable description.
public enum RecordingError: Error, LocalizedError {
    case general(String)
    case deviceNotFound(String)
    case processNotFound(pid_t)
    case audioFormatUnsupported(String)
    case permissionDenied(String)
    case recordingInProgress

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
        }
    }
} 
