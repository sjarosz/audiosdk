import Foundation
import audiosdk

func main() {
    let recorder = AudioRecorder()

    let pid = Int32(39198)
    //print("Enter the process ID (pid) of the application you want to record:")
    //guard let input = readLine(), let pid = Int32(input) else {
    //    print("Invalid input. Please enter a number.")
    //    return
    //}

    do {
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let recordingsFolderURL = desktopURL.appendingPathComponent("Recordings")
        try FileManager.default.createDirectory(at: recordingsFolderURL, withIntermediateDirectories: true, attributes: nil)
        recorder.outputDirectory = recordingsFolderURL
        print("🎵 Recordings will be saved to: \(recordingsFolderURL.path)")
    } catch {
        print("❌ Could not create or find the recordings directory: \(error)")
        return
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    let dateString = formatter.string(from: Date())
    let outputURL = recorder.outputDirectory!.appendingPathComponent("recording-\(dateString).wav")

    do {
        try recorder.startRecording(pid: pid, outputFile: outputURL)
        print("▶️ Recording from pid \(pid)... Recording for 5 seconds.")
    } catch {
        print("❌ Failed to start recording: \(error)")
        return
    }

    // Wait for 5 seconds
    sleep(5)

    recorder.stopRecording()
    print("✅ Recording stopped. File saved to: \(outputURL.path)")
}

main()
