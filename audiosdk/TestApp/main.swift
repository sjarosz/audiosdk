import Foundation
import audiosdk
import OSLog

let logger = Logger(subsystem: "com.audiocap.testapp", category: "main")

// Print all available output audio devices
let devices = AudioRecorder.listOutputAudioDevices()
logger.log("JRSZ Available audio output devices:")
for device in devices {
    logger.log("  \(device.name, privacy: .public) [ID: \(device.id)]")
}

// Print all audio-capable processes
let audioProcs = AudioRecorder.listAudioCapableProcesses()
logger.log("JRSZ Audio-capable processes:")
for (pid, name) in audioProcs {
    logger.log("  \(name, privacy: .public) [PID: \(pid)]")
}

// Example: Find the PID for a known audio-capable process by name
let processNameToFind = "QuickTime Player" // Change to a process you expect to be running and audio-capable
var targetPID: pid_t? = nil
if let foundPID = AudioRecorder.pidForAudioCapableProcess(named: processNameToFind) {
    logger.log("JRSZ PID for process '\(processNameToFind, privacy: .public)': \(foundPID)")
    targetPID = foundPID
} else {
    logger.log("JRSZ No audio-capable process found with name '\(processNameToFind, privacy: .public)'")
}

// --- Configuration ---
// Hardcode your desired device ID here after running the app once to see the list
let selectedDeviceID = 107

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
    //try recorder.startRecording(pid: targetPID, outputFile: outputFileURL)
    logger.log("...Recording for 5 seconds...")
    sleep(5)
    logger.log("⏹️ Stopping recording.")
    recorder.stopRecording()
    logger.log("✅ Recording session finished successfully.")
} catch {
    logger.error("❌ An error occurred: \(error.localizedDescription)")
    logger.error("➡️ Details: \(error.localizedDescription)")
}
