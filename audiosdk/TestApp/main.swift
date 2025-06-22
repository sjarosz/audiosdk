import Foundation
import audiosdk
import OSLog

let logger = Logger(subsystem: "com.audiocap.testapp", category: "main")

// --- Configuration ---
// Replace with the PID of the application you want to record.
// You can find the PID using `pgrep -f "Application Name"` in Terminal.
let targetPID: pid_t = 39198 // Example PID, please change

// --- Main Logic ---
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

// Set the post-processing handler.
recorder.postProcessingHandler = { fileURL in
    logger.log("✅ Post-processing recording at: \(fileURL.path)")
}

// Generate a unique filename.
let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
let dateString = dateFormatter.string(from: Date())
let outputFileURL = outputDir.appendingPathComponent("recording-\(dateString).wav")

do {
    logger.log("▶️ Starting recording for PID \(targetPID)...")
    try recorder.startRecording(pid: targetPID, outputFile: outputFileURL)

    logger.log("...Recording for 5 seconds...")
    sleep(5)

    logger.log("⏹️ Stopping recording.")
    recorder.stopRecording()

    logger.log("✅ Recording session finished successfully.")

} catch {
    logger.error("❌ An error occurred: \(error.localizedDescription)")
    logger.error("➡️ Details: \(error.localizedDescription)")
}
