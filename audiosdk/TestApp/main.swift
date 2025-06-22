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

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    let dateString = formatter.string(from: Date())
    let outputURL = URL(fileURLWithPath: "recording-\(dateString).wav")

    do {
        try recorder.startRecording(pid: pid, outputFile: outputURL)
        print("▶️ Recording from pid \(pid) to file: \(outputURL.path)... Press Enter to stop.")
    } catch {
        print("❌ Failed to start recording: \(error)")
        return
    }

    // Wait for user to press Enter
    _ = readLine()

    recorder.stopRecording()
    print("✅ Recording stopped. File saved to: \(outputURL.path)")
}

main()
