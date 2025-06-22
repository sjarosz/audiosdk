//
//  DeviceDiscovery.swift
//  AudioSDK
//
//  Provides device enumeration and lookup services for audio devices.
//

import Foundation
import AudioToolbox
import CoreAudio
import AVFoundation
import OSLog

public final class DeviceDiscovery {
    /// List all audio devices (input and output) with metadata.
    public static func listAllDevices() -> [AudioDeviceInfo] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID.system, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else { return [] }
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        let status2 = AudioObjectGetPropertyData(AudioObjectID.system, &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        guard status2 == noErr else { return [] }
        var devices: [AudioDeviceInfo] = []
        for deviceID in deviceIDs {
            let info = deviceInfo(for: deviceID)
            if let info = info {
                devices.append(info)
            }
        }
        return devices
    }

    /// List all output audio devices (speakers, etc).
    public static func listOutputAudioDevices() -> [AudioDeviceInfo] {
        return listAllDevices().filter { $0.isOutput }
    }

    /// List all input audio devices (microphones, etc).
    public static func listInputAudioDevices() -> [AudioDeviceInfo] {
        return listAllDevices().filter { $0.isInput }
    }

    /// Find a device by (case-insensitive) name. Returns the first match.
    public static func findDevice(named name: String) -> AudioDeviceInfo? {
        return listAllDevices().first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Find a device by UID.
    public static func findDevice(withUID uid: String) -> AudioDeviceInfo? {
        return listAllDevices().first { $0.uid == uid }
    }

    /// Helper to build AudioDeviceInfo for a given device ID.
    private static func deviceInfo(for deviceID: AudioDeviceID) -> AudioDeviceInfo? {
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
        guard nameStatus == noErr else { return nil }
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
        guard uidStatus == noErr else { return nil }
        // Check for input/output streams
        var inputStreamsSize: UInt32 = 0
        var inputStreamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        let inputStatus = AudioObjectGetPropertyDataSize(deviceID, &inputStreamsAddress, 0, nil, &inputStreamsSize)
        let isInput = (inputStatus == noErr && inputStreamsSize > 0)
        var outputStreamsSize: UInt32 = 0
        var outputStreamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let outputStatus = AudioObjectGetPropertyDataSize(deviceID, &outputStreamsAddress, 0, nil, &outputStreamsSize)
        let isOutput = (outputStatus == noErr && outputStreamsSize > 0)
        return AudioDeviceInfo(
            id: deviceID,
            name: name as String,
            uid: uid as String,
            isInput: isInput,
            isOutput: isOutput
        )
    }
} 