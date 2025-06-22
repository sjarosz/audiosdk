# AudioRecorder SDK

**AudioRecorder** is a modern Swift framework for macOS that enables programmatic audio capture from any running application and the system's default microphone—simultaneously. It uses Apple's latest Core Audio process tap APIs and the modern `AVAudioEngine` framework to provide a simple, powerful, and safe way to record audio without kernel extensions.

---

## ✨ Features

- **Record Any App's Audio**: Capture the audio output from any running process by its PID.
- **Simultaneous Microphone Recording**: Record from the system's default microphone at the same time as the process audio, saved to a separate file.
- **Modern & Safe**: Uses Apple's new user-space APIs (`AudioHardwareCreateProcessTap` on macOS 14.4+ and `AVAudioEngine`), requiring no kernel extensions or hacks.
- **Clean Swift API**: A simple, developer-friendly interface with robust error handling and clear documentation.
- **Device & Process Discovery**: Helper utilities to list all available audio devices and find audio-capable processes by name.
- **Automatic Resource Cleanup**: Ensures all Core Audio resources are cleaned up on exit, preventing orphaned audio devices.
- **Post-Processing Hooks**: Provides separate completion handlers for both the process and microphone recordings.
- **Selectable Output Device**: Choose a specific output device for the process audio tap, or use the system default.

---

## 🛠️ Requirements

- macOS 14.4 or later
- Swift 5.9+
- Xcode 15+

---

## 🧑‍💻 How It Works

- **For Process Audio**: It translates a process PID to a Core Audio object, creates a process tap for it, and wraps it in an aggregate device to capture the audio stream.
- **For Microphone Audio**: It uses a modern `AVAudioEngine` instance to capture audio from the system's default input device.
- **Synchronization**: Both recordings are started and stopped together, managed by a single `startRecording()` and `stopRecording()` call.
- **File Output**: Each stream is written to a separate `.wav` file.

---

## 🚀 Usage Example

The following example demonstrates how to find a process named "QuickTime Player" and record both its audio and the microphone's audio for 5 seconds.

```swift
import audiosdk
import Foundation

let recorder = AudioRecorder()
let processNameToFind = "QuickTime Player"

// 1. Find the Process ID (PID)
guard let pid = AudioRecorder.pidForAudioCapableProcess(named: processNameToFind) else {
    print("❌ Could not find an audio-capable process named '\(processNameToFind)'.")
    exit(1)
}
print("✅ Found PID for '\(processNameToFind)': \(pid)")

// 2. Prepare Output File URLs
guard let outputDir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.appendingPathComponent("Recordings") else {
    fatalError("Could not get desktop directory.")
}
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let dateString = ISO86GNCDateFormatter().string(from: Date())
let processOutputFile = outputDir.appendingPathComponent("process-\(dateString).wav")
let microphoneOutputFile = outputDir.appendingPathComponent("mic-\(dateString).wav")

// 3. (Optional) Set Post-Processing Handlers
recorder.postProcessingHandler = { url in
    print("✅ Process recording finished: \(url.path)")
}
recorder.microphonePostProcessingHandler = { url in
    print("✅ Microphone recording finished: \(url.path)")
}

// 4. Start Simultaneous Recording
do {
    print("▶️ Starting simultaneous recording...")
    try recorder.startRecording(
        pid: pid,
        outputFile: processOutputFile,
        microphoneFile: microphoneOutputFile
        // You can also specify an `outputDeviceID` here for the process tap.
        // `inputDeviceID` is ignored, as the mic recording uses the system default.
    )

    print("...Recording for 5 seconds...")
    sleep(5)

} catch {
    print("❌ An error occurred: \(error.localizedDescription)")
    exit(1)
}

// 5. Stop Recording
print("⏹️ Stopping recording.")
recorder.stopRecording()
```

---

## ⚙️ API Helpers

The SDK also provides several static helper methods for device and process discovery.

### List Output Devices
```swift
let devices = AudioRecorder.listOutputAudioDevices()
for device in devices {
    print("Output Device: \(device.name) [ID: \(device.id)]")
}
```

### List Input Devices
```swift
let devices = AudioRecorder.listInputAudioDevices()
for device in devices {
    print("Input Device: \(device.name) [ID: \(device.id)]")
}
```

### List Audio-Capable Processes
This function returns all running processes that Core Audio recognizes as having an audio object. These are the only processes you can tap for audio output.
```swift
let processes = AudioRecorder.listAudioCapableProcesses()
for (pid, name) in processes {
    print("Audio-Capable Process: \(name) [PID: \(pid)]")
}
```

---

## ⚠️ Notes & Limitations

- **macOS 14.4+ Required**: The Core Audio process tap APIs are only available on recent versions of macOS.
- **Permissions**: Your app must have the "Audio Input" capability enabled in its entitlements to record from the microphone.
- **Default Microphone Only**: The current implementation of microphone recording uses the system's default input device. The API to select a specific input device is present but ignored.
- **Test App**: The project includes a command-line `TestApp` that demonstrates the SDK's functionality. You can configure the `processNameToFind` and device names at the top of `main.swift`.

---

## 📚 Credits

- Inspired by the advanced Core Audio patterns in [AudioCap](https://github.com/insidegui/AudioCap).

---

## 📝 License

See [LICENSE](LICENSE) for details.

---

**Happy hacking!**