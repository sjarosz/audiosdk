import Foundation
import audiosdk
import OSLog

// =================================================================================
// AudioSDK Test App
// =================================================================================
// This command-line tool demonstrates how to use the AudioRecorder SDK.
// It finds a target process by name, then simultaneously records its audio output
// and the system's default microphone input to separate files on the Desktop.
// =================================================================================

// --- Configuration ---
// Set the name of the process you want to record (must be audio-capable).
let processNameToFind = "QuickTime Player" // Change to a process you expect to be running.
// Set your desired output device name, or leave as nil to use the default system output.
let outputDeviceName: String? = "Mac Studio Speakers"
// Set your desired input device name. NOTE: The SDK currently ignores this and uses the system default.
let inputDeviceName: String? = "Elgato Wave XLR"
let logger = Logger(subsystem: "com.audiocap.testapp", category: "main")

// --- Device Lookups ---
// Look up the device ID for the given output device name. This is used for the process tap.
let selectedOutputDeviceID: Int? = outputDeviceName.flatMap { AudioRecorder.deviceIDForOutputDevice(named: $0) }
// Look up the input device ID. This is for demonstration; the SDK will log a warning and use the default.
let selectedInputDeviceID: Int? = inputDeviceName.flatMap { name in
    DeviceDiscovery.findInputDevice(named: name).map { Int($0.id) }
}

if let id = selectedOutputDeviceID {
    logger.log("JRSZ Output device '\(outputDeviceName ?? "")' has ID: \(id)")
} else {
    logger.log("JRSZ Output device '\(outputDeviceName ?? "")' not found.")
}

if let id = selectedInputDeviceID {
    logger.log("JRSZ Input device '\(inputDeviceName ?? "")' has ID: \(id)")
} else {
    logger.log("JRSZ Input device '\(inputDeviceName ?? "")' not found.")
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

// --- Find Target Process ---
// Uses AudioRecorder.pidForAudioCapableProcess(named:) to get the PID.
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

// --- Prepare for Recording ---
let recorder = AudioRecorder()

// Create a "Recordings" directory on the Desktop.
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

// Set post-processing handlers to be notified when recordings are finished.
recorder.postProcessingHandler = { fileURL in
    logger.log("✅ Process recording finished: \(fileURL.path)")
}
recorder.microphonePostProcessingHandler = { fileURL in
    logger.log("✅ Microphone recording finished: \(fileURL.path)")
}

// Create unique file names for the process and microphone recordings.
let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
let dateString = dateFormatter.string(from: Date())
let outputFileURL = outputDir.appendingPathComponent("process-recording-\(dateString).wav")
let micFileURL = outputDir.appendingPathComponent("mic-recording-\(dateString).wav")

// --- Start and Stop Recording ---
guard let pid = targetPID else {
    logger.error("❌ No valid target PID. Exiting.")
    exit(1)
}

do {
    logger.log("▶️ Starting simultaneous recording for PID \(pid)...")
    try recorder.startRecording(
        pid: pid,
        outputFile: outputFileURL,
        microphoneFile: micFileURL,
        outputDeviceID: selectedOutputDeviceID,
        inputDeviceID: selectedInputDeviceID // SDK will log a warning and use the default mic.
    )
    logger.log("...Recording for 5 seconds...")
    sleep(5)
    logger.log("⏹️ Stopping recording.")
    recorder.stopRecording()
    logger.log("✅ Recording session finished successfully.")
} catch {
    logger.error("❌ An error occurred: \(error.localizedDescription)")
    logger.error("➡️ Details: \(error.localizedDescription)")
}
