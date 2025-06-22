import Foundation
import audiosdk
import OSLog

// --- Configuration ---
// Set the name of the process you want to record from (must be audio-capable, see below)
let processNameToFind = "QuickTime Player" // Change to a process you expect to be running and audio-capable
// Set your desired output device name here, or leave as nil to use the default system output device
let outputDeviceName: String? = "Mac Studio Speakers" // Change to your device name, or set to nil
let inputDeviceName: String?="Elgato Wave XLR"
let logger = Logger(subsystem: "com.audiocap.testapp", category: "main")

// Look up the device ID for the given output device name using the SDK helper
let selectedDeviceID: Int? = outputDeviceName.flatMap { AudioRecorder.deviceIDForOutputDevice(named: $0) }

if let id = selectedDeviceID {
    logger.log("JRSZ Output device '\(outputDeviceName ?? "")' has ID: \(id)")
} else {
    logger.log("JRSZ Output device '\(outputDeviceName ?? "")' not found.")
}

// --- Optional: Print all available output audio devices (toggle with if (1 == 1/0)) ---
if (1 == 0) { // Print all available output audio devices
    // Uses: AudioRecorder.listOutputAudioDevices()
    let devices = AudioRecorder.listOutputAudioDevices()
    logger.log("JRSZ Available audio output devices:")
    for device in devices {
        logger.log("  \(device.name, privacy: .public) [ID: \(device.id)]")
    }
}

// --- Optional: Print all audio-capable processes (toggle with if (1 == 1/0)) ---
if (1 == 0) { // Print all audio-capable processes
    // Uses: AudioRecorder.listAudioCapableProcesses()
    let audioProcs = AudioRecorder.listAudioCapableProcesses()
    logger.log("JRSZ Audio-capable processes:")
    for (pid, name) in audioProcs {
        logger.log("  \(name, privacy: .public) [PID: \(pid)]")
    }
}

// --- Find the PID for a known audio-capable process by name ---
// Uses: AudioRecorder.pidForAudioCapableProcess(named:)
var targetPID: pid_t? = nil
if let foundPID = AudioRecorder.pidForAudioCapableProcess(named: processNameToFind) {
    logger.log("JRSZ PID for process '\(processNameToFind, privacy: .public)': \(foundPID)")
    targetPID = foundPID
} else {
    logger.log("JRSZ No audio-capable process found with name '\(processNameToFind, privacy: .public)'")
}

// --- Optional: Print all available input audio devices (toggle with if (1 == 1/0)) ---
if (1 == 1) { // Print all available input audio devices
    // Uses: AudioRecorder.listInputAudioDevices()
    let inputDevices = AudioRecorder.listInputAudioDevices()
    logger.log("JRSZ Available input audio devices:")
    for device in inputDevices {
        logger.log("  \(device.name, privacy: .public) [ID: \(device.id)]")
    }
}

// --- Standard SDK usage for recording ---
let recorder = AudioRecorder()

guard let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
    logger.error("❌ Could not find desktop directory.")
    exit(1)
}
let outputDir = desktopURL.appendingPathComponent("Recordings")
do {
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
    recorder.outputDirectory = outputDir
    logger.log("🎵 Recordings will be saved to: \(outputDir.path)")
} catch {
    logger.error("❌ Could not create or find the recordings directory: \(error.localizedDescription)")
    exit(1)
}

// Optional: Set a post-processing handler for after recording stops
recorder.postProcessingHandler = { fileURL in
    logger.log("✅ Post-processing recording at: \(fileURL.path)")
}

let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
let dateString = dateFormatter.string(from: Date())
let outputFileURL = outputDir.appendingPathComponent("recording-\(dateString).wav")

guard let pid = targetPID else {
    logger.error("❌ No valid target PID. Exiting.")
    exit(1)
}

do {
    logger.log("▶️ Starting recording for PID \(pid)...")
    try recorder.startRecording(pid: pid, outputFile: outputFileURL, outputDeviceID: selectedDeviceID)
    logger.log("...Recording for 5 seconds...")
    sleep(5)
    logger.log("⏹️ Stopping recording.")
    recorder.stopRecording()
    logger.log("✅ Recording session finished successfully.")
} catch {
    logger.error("❌ An error occurred: \(error.localizedDescription)")
    logger.error("➡️ Details: \(error.localizedDescription)")
}
