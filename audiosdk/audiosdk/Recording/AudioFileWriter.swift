//
//  AudioFileWriter.swift
//  AudioSDK
//
//  Handles audio file writing and format management.
//

import Foundation
import AVFoundation

struct AudioFileWriter {
    let fileURL: URL
    let format: AVAudioFormat
    private(set) var audioFile: AVAudioFile?

    init(fileURL: URL, format: AVAudioFormat) throws {
        self.fileURL = fileURL
        self.format = format
        self.audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
    }

    mutating func write(buffer: AVAudioPCMBuffer) throws {
        guard let file = audioFile else { throw RecordingError.general("Audio file not open.") }
        try file.write(from: buffer)
    }

    func close() {
        // AVAudioFile closes automatically on deinit, but you can nil out for explicit closure
        // (no-op in this implementation)
    }
} 