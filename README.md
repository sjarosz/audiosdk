# audiosdk
I need to create a macOS framework called audiosdk that records audio output from any running application using modern CoreAudio APIs. Here are the detailed requirements:
Framework Specifications:

Name: audiosdk
Target: macOS 14.4+ (due to API requirements)
Architecture: Framework with clean public API
Core Technology: Must use CoreAudio process tapping APIs introduced in macOS 14.4, specifically AudioHardwareCreateProcessTap

Public API Requirements:
swift// Desired API structure
public class AudioSDK {
    public weak var delegate: AudioSDKDelegate?
    
    public func startRecording(processID: pid_t, outputDirectory: URL) throws
    public func stopRecording()
    public var isRecording: Bool { get }
}

public protocol AudioSDKDelegate: AnyObject {
    func audioSDKDidStartRecording(_ sdk: AudioSDK)
    func audioSDKDidStopRecording(_ sdk: AudioSDK, outputFileURL: URL?)
    func audioSDK(_ sdk: AudioSDK, didEncounterError error: Error)
}
Technical Implementation Requirements:

Use AudioHardwareCreateProcessTap and related modern CoreAudio process tap APIs
Follow the implementation patterns from https://github.com/insidegui/AudioCap as the primary reference
Handle the complete CoreAudio pipeline: PID → AudioObjectID → CATapDescription → ProcessTap → AggregateDevice → Audio capture
Implement proper permission handling (NSAudioCaptureUsageDescription)
Include comprehensive error handling and cleanup
Support standard audio formats (preferably M4A/AAC)

Framework Structure:

Clean separation between public API and internal CoreAudio implementation
Proper resource management and cleanup
Thread-safe operations
Comprehensive error types and handling

Key Technical Areas to Address:

CoreAudio utilities and extensions (similar to CoreAudioUtils.swift from reference)
Process tap creation and management
Aggregate device configuration
Audio format handling and file writing
Permission management
Delegate pattern implementation
Framework packaging and module structure

Please design and implement this framework, ensuring it follows macOS framework best practices and provides a developer-friendly API while leveraging the complex CoreAudio process tapping implementation from the reference project.