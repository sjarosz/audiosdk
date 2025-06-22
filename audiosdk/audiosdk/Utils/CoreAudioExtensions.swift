//
//  CoreAudioExtensions.swift
//  AudioSDK
//
//  Core Audio helpers and extensions.
//

import Foundation
import AudioToolbox

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = kAudioObjectUnknown
    var isValid: Bool { self != .unknown }

    static func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        var deviceID: AudioDeviceID = .unknown
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let err = AudioObjectGetPropertyData(.system, &address, 0, nil, &size, &deviceID)
        guard err == noErr else {
            throw RecordingError.general("Failed to get default system output device: \(osStatusDescription(err))")
        }
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
            throw RecordingError.processNotFound(pid)
        }
        guard objectID != .unknown else {
            throw RecordingError.processNotFound(pid)
        }
        return objectID
    }

    func readDeviceUID() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString?>.size)
        let err = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0)
        }
        guard err == noErr else {
            throw RecordingError.general("Failed to read device UID for object \(self): \(osStatusDescription(err))")
        }
        return uid as String
    }

    func readAudioTapStreamBasicDescription() throws -> AudioStreamBasicDescription {
        var description = AudioStreamBasicDescription()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let err = AudioObjectGetPropertyData(self, &address, 0, nil, &size, &description)
        guard err == noErr else {
            throw RecordingError.general("Failed to read audio tap stream description for object \(self): \(osStatusDescription(err))")
        }
        return description
    }
}

func osStatusDescription(_ status: OSStatus) -> String {
    if let errorMessage = SecCopyErrorMessageString(status, nil) {
        return (errorMessage as String)
    }
    var code = status.bigEndian
    let cString: [CChar] = [
        CChar(truncatingIfNeeded: (code >> 24) & 0xFF),
        CChar(truncatingIfNeeded: (code >> 16) & 0xFF),
        CChar(truncatingIfNeeded: (code >> 8) & 0xFF),
        CChar(truncatingIfNeeded: code & 0xFF),
        0
    ]
    let isPrintable = cString.dropLast().allSatisfy { isprint(Int32($0)) != 0 }
    if isPrintable, let fourCC = String(cString: cString, encoding: .ascii)?.trimmingCharacters(in: .whitespaces), !fourCC.isEmpty {
        return "'\(fourCC)' (\(status))"
    } else {
        return "Error code \(status)"
    }
} 
