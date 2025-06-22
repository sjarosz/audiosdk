//
//  OrphanedResourceCleaner.swift
//  AudioSDK
//
//  Cleans up orphaned aggregate/tap devices created by the SDK.
//

import Foundation
import AudioToolbox
import OSLog

public struct OrphanedResourceCleaner {
    public static func cleanupOrphanedAudioObjects(logger: Logger) {
        logger.info("Scanning for orphaned SDK-Tap devices and process taps...")
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID.system, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else {
            logger.error("Failed to get device list size: \(osStatusDescription(status))")
            return
        }
        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: .unknown, count: deviceCount)
        status = AudioObjectGetPropertyData(AudioObjectID.system, &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else {
            logger.error("Failed to get device list: \(osStatusDescription(status))")
            return
        }
        for deviceID in deviceIDs {
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
            let deviceName = (nameStatus == noErr) ? (name as String) : ""
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
            let deviceUID = (uidStatus == noErr) ? (uid as String) : ""
            if deviceName.hasPrefix("SDK-Tap-") || deviceUID.hasPrefix("SDK-Tap-") {
                let destroyAggStatus = AudioHardwareDestroyAggregateDevice(deviceID)
                if destroyAggStatus == noErr {
                    logger.info("Destroyed orphaned aggregate device: \(deviceName, privacy: .public) [UID: \(deviceUID, privacy: .public)]")
                    continue
                }
                let destroyTapStatus = AudioHardwareDestroyProcessTap(deviceID)
                if destroyTapStatus == noErr {
                    logger.info("Destroyed orphaned process tap: \(deviceName, privacy: .public) [UID: \(deviceUID, privacy: .public)]")
                    continue
                }
                logger.warning("Failed to destroy orphaned device: \(deviceName, privacy: .public) [UID: \(deviceUID, privacy: .public)] (aggStatus=\(destroyAggStatus), tapStatus=\(destroyTapStatus))")
            }
        }
        logger.info("Orphaned SDK-Tap device/process tap cleanup complete.")
    }
} 