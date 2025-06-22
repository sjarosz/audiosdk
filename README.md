# audiosdk

**audiosdk** is a modern Swift framework for macOS 14.4+ that enables programmatic recording of audio output from any running application, using Apple's latest CoreAudio process tap APIs. It is inspired by the advanced patterns in [AudioCap](https://github.com/insidegui/AudioCap), but is designed for easy integration into your own apps and tools.

---

## ✨ Key Benefits

- **Record Any App's Audio**: Capture output from any running process by PID, not just system-wide audio.
- **Modern CoreAudio**: Uses Apple's new process tap APIs (`AudioHardwareCreateProcessTap`), available in macOS 14.4+.
- **No Kernel Extensions**: Pure user-space solution—no drivers, no hacks, no security prompts.
- **Clean Swift API**: Simple, developer-friendly interface with robust error handling.
- **Automatic Resource Cleanup**: Cleans up orphaned CoreAudio devices/taps on startup.
- **Post-Processing Hooks**: Easily add normalization, transcoding, or notifications after recording.
- **Device Selection**: Record from the default output or any specific output device.
- **Audio-Capable Process Discovery**: List all running processes that are recognized by CoreAudio as audio-capable (see below).
- **Process Name Lookup**: Find the PID for a process by name from the audio-capable list.

---

## 🚀 What Does It Do?

- Translates a process PID to a CoreAudio object.
- Creates a process tap and aggregate device for that process.
- Streams audio data to a `.wav` file (or other formats if you wish).
- Lets you select the output device (e.g., built-in speakers, external audio).
- Provides real-time audio analysis hooks (RMS, dB).
- Ensures all CoreAudio resources are cleaned up, even after crashes.
- **Enumerates audio-capable processes** for easy selection and UI integration.
- **Looks up PIDs by process name** for convenience in scripting and automation.

---

## 🛠️ Requirements

- **macOS 14.4 or later** (due to new CoreAudio APIs)
- Swift 5.9+
- Xcode 15+

---

## 🧑‍💻 Usage

### 1. List Available Output Devices

```swift
let devices = AudioRecorder.listOutputAudioDevices()
for device in devices {
    print("\(device.name) [ID: \(device.id)]")
}
```

### 2. List Audio-Capable Processes

```swift
let audioProcs = AudioRecorder.listAudioCapableProcesses()
for (pid, name) in audioProcs {
    print("Audio-capable process: \(name) [PID: \(pid)]")
}
```

*This function returns all running processes that CoreAudio recognizes as having an audio object. These are the only processes you can tap for audio output. Note: This does not guarantee the process is currently producing audio, only that it is recognized by CoreAudio as audio-capable.*

### 3. Find PID by Process Name

```swift
if let pid = AudioRecorder.pidForAudioCapableProcess(named: "coreaudiod") {
    print("PID for coreaudiod: \(pid)")
} else {
    print("No audio-capable process found with that name.")
}
```

*This function searches the audio-capable process list for a process with the given name (case-insensitive) and returns its PID if found.*

### 4. Start Recording

```swift
let recorder = AudioRecorder()
let pid: pid_t = /* target process PID */
let outputURL = URL(fileURLWithPath: "/path/to/output.wav")
let deviceID: Int? = /* e.g. 62, or nil for default */

try recorder.startRecording(pid: pid, outputFile: outputURL, outputDeviceID: deviceID)
```

### 5. Stop Recording

```swift
recorder.stopRecording()
```

### 6. Post-Processing

Optionally, set a closure to run after recording stops:

```swift
recorder.postProcessingHandler = { fileURL in
    print("Post-processing at \(fileURL)")
    // Normalize, transcode, upload, etc.
}
```

---

## 🧩 Example: Minimal Command-Line App

```swift
import audiosdk

let devices = AudioRecorder.listOutputAudioDevices()
for device in devices {
    print("\(device.name) [ID: \(device.id)]")
}

let audioProcs = AudioRecorder.listAudioCapableProcesses()
for (pid, name) in audioProcs {
    print("Audio-capable process: \(name) [PID: \(pid)]")
}

if let pid = AudioRecorder.pidForAudioCapableProcess(named: "coreaudiod") {
    print("PID for coreaudiod: \(pid)")
}

let recorder = AudioRecorder()
let pid: pid_t = 12345 // Replace with your target app's PID
let outputURL = URL(fileURLWithPath: "/Users/yourname/Desktop/recording.wav")
try recorder.startRecording(pid: pid, outputFile: outputURL, outputDeviceID: 62) // Use your device ID

sleep(5)
recorder.stopRecording()
```

---

## ⚠️ Notes & Limitations

- **macOS 14.4+ only**: The process tap APIs are not available on earlier macOS versions.
- **Permissions**: Your app may need microphone/audio capture permissions.
- **Format**: Default output is `.wav` (uncompressed PCM). You can change this in your app.
- **Process Must Be Running**: The target PID must be valid and producing audio.
- **Audio-Capable Process Discovery**: Only processes recognized by CoreAudio as having an audio object can be tapped for output.
- **Process Name Lookup**: Only exact (case-insensitive) matches are returned; multiple processes with the same name will return the first found.

---

## 📚 Reference & Credits

- Inspired by [AudioCap](https://github.com/insidegui/AudioCap)
- Uses Apple's new CoreAudio process tap APIs

---

## 📝 License

See [LICENSE](LICENSE) for details.

---

**Happy hacking!**