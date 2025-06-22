//
//  AudioDeviceInfo.swift
//  AudioSDK
//
//  Describes an audio device with all relevant metadata.
//

import Foundation
import AudioToolbox

/// Immutable struct describing an audio device.
public struct AudioDeviceInfo {
    public let id: AudioDeviceID
    public let name: String
    public let uid: String
    public let isInput: Bool
    public let isOutput: Bool

    public init(id: AudioDeviceID, name: String, uid: String, isInput: Bool, isOutput: Bool) {
        self.id = id
        self.name = name
        self.uid = uid
        self.isInput = isInput
        self.isOutput = isOutput
    }
} 
