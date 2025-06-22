# Audio SDK Refactoring Plan

## Current State Analysis
The current implementation is a single 400+ line file containing:
- High-level `AudioRecorder` public API
- Internal `ProcessTap` implementation 
- Core Audio utility extensions
- Error definitions
- Device enumeration logic
- Process discovery logic

## Proposed Module Structure

### 1. **Core/Errors.swift**
```swift
public enum RecordingError: Error, LocalizedError {
    case general(String)
    case deviceNotFound(String)
    case processNotFound(pid_t)
    case audioFormatUnsupported(String)
    case permissionDenied
    case recordingInProgress
    // ... expanded error cases
}
```
**Responsibilities:**
- Centralized error definitions
- Localized error messages
- Error categorization for better handling

### 2. **Core/AudioDeviceInfo.swift**
```swift
public struct AudioDeviceInfo {
    public let id: AudioDeviceID
    public let name: String
    public let uid: String
    public let isInput: Bool
    public let isOutput: Bool
    // ... additional device metadata
}
```
**Responsibilities:**
- Device information data structure
- Device capability flags
- Device metadata handling

### 3. **Utils/CoreAudioExtensions.swift**
```swift
extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = kAudioObjectUnknown
    
    // All the current extension methods
    static func readDefaultSystemOutputDevice() throws -> AudioDeviceID
    static func translatePIDToProcessObjectID(pid: pid_t) throws -> AudioObjectID
    func readDeviceUID() throws -> String
    func readAudioTapStreamBasicDescription() throws -> AudioStreamBasicDescription
    func read<T>(_ property: AudioObjectPropertySelector, defaultValue: T?) throws -> T
}

func osStatusDescription(_ status: OSStatus) -> String
```
**Responsibilities:**
- Core Audio API wrappers
- Safe property reading
- Error handling for CA calls
- Status code translation

### 4. **Discovery/DeviceDiscovery.swift**
```swift
public class DeviceDiscovery {
    public static func listOutputDevices() -> [AudioDeviceInfo]
    public static func listInputDevices() -> [AudioDeviceInfo] 
    public static func listAllDevices() -> [AudioDeviceInfo]
    public static func findDevice(named: String) -> AudioDeviceInfo?
    public static func findDevice(withUID: String) -> AudioDeviceInfo?
    private static func deviceHasStreams(deviceId: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool
}
```
**Responsibilities:**
- Audio device enumeration
- Device filtering by capabilities
- Device search functionality
- Stream validation

### 5. **Discovery/ProcessDiscovery.swift**
```swift
//
//  ProcessDiscovery.swift
//  AudioSDK
//
//  Provides process enumeration and lookup for audio-capable processes.
//

import Foundation
import AudioToolbox

/// Struct describing an audio-capable process.
public struct AudioProcessInfo {
    public let pid: pid_t
    public let name: String
    public let objectID: AudioObjectID

    public init(pid: pid_t, name: String, objectID: AudioObjectID) {
        self.pid = pid
        self.name = name
        self.objectID = objectID
    }
}

public final class ProcessDiscovery {
    /// List all running processes that are audio-capable (i.e., have a valid CoreAudio object).
    public static func listAudioCapableProcesses() -> [AudioProcessInfo] {
        var result: [AudioProcessInfo] = []
        var procCount = proc_listallpids(nil, 0)
        guard procCount > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(procCount))
        procCount = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        for pid in pids where pid > 0 {
            var nameBuf = [CChar](repeating: 0, count: 1024)
            let nameResult = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let procName = nameResult > 0 ? String(cString: nameBuf) : "(unknown)"
            do {
                let objectID = try AudioObjectID.translatePIDToProcessObjectID(pid: pid)
                result.append(AudioProcessInfo(pid: pid, name: procName, objectID: objectID))
            } catch {
                continue
            }
        }
        return result
    }

    /// Find the PID of the first audio-capable process matching the given name (case-insensitive).
    public static func pidForAudioCapableProcess(named name: String) -> pid_t? {
        return listAudioCapableProcesses().first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.pid
    }

    /// Find an audio-capable process by PID.
    public static func findProcess(withPID pid: pid_t) -> AudioProcessInfo? {
        return listAudioCapableProcesses().first { $0.pid == pid }
    }
}
```
**Responsibilities:**
- Process enumeration
- Audio capability detection
- Process name resolution
- PID to AudioObjectID translation

### 6. **Recording/ProcessTap.swift**
```swift
internal class ProcessTap {
    private let configuration: TapConfiguration
    private let logger: Logger
    private var tapState: TapState
    
    init(configuration: TapConfiguration, logger: Logger)
    func startRecording(to fileURL: URL) throws
    func stopRecording()
    func getCurrentFileURL() -> URL?
    
    private func createProcessTap() throws -> AudioObjectID
    private func createAggregateDevice() throws -> AudioObjectID  
    private func setupIOProc() throws
    private func cleanupResources()
}

internal struct TapConfiguration {
    let pid: pid_t
    let objectID: AudioObjectID
    let outputDeviceID: AudioDeviceID
    let audioFormat: AudioStreamBasicDescription?
}

internal struct TapState {
    var processTapID: AudioObjectID = .unknown
    var systemOutputDeviceID: AudioObjectID = .unknown
    var deviceProcID: AudioDeviceIOProcID?
    var isRecording: Bool = false
}
```
**Responsibilities:**
- Core Audio tap lifecycle management
- Aggregate device creation/destruction
- IO proc setup and callbacks
- Audio buffer processing
- Resource cleanup

### 7. **Recording/AudioFileWriter.swift**
```swift
internal class AudioFileWriter {
    private let fileURL: URL
    private let audioFormat: AVAudioFormat
    private var audioFile: AVAudioFile?
    
    init(fileURL: URL, format: AudioStreamBasicDescription) throws
    func write(buffer: AVAudioPCMBuffer) throws
    func close()
    
    private func createAVAudioFormat(from description: AudioStreamBasicDescription) -> AVAudioFormat?
    private func validateAudioFormat(_ description: AudioStreamBasicDescription) throws
}
```
**Responsibilities:**
- File I/O operations
- Audio format conversion
- Buffer writing
- File lifecycle management

### 8. **Recording/AudioMetrics.swift**
```swift
public struct AudioMetrics {
    public let rmsValues: [Float]  // Per channel
    public let decibelValues: [Float]  // Per channel
    public let timestamp: TimeInterval
}

internal class AudioMetricsCalculator {
    func calculateMetrics(from buffer: AVAudioPCMBuffer) -> AudioMetrics
    private func calculateRMS(for channelData: UnsafeBufferPointer<Float>) -> Float
    private func rmsToDecibels(_ rms: Float) -> Float
}
```
**Responsibilities:**
- Real-time audio analysis
- RMS/decibel calculations
- Metrics data structures
- Performance-optimized calculations

### 9. **Management/OrphanedResourceCleaner.swift**
```swift
internal class OrphanedResourceCleaner {
    private let logger: Logger
    
    init(logger: Logger)
    func cleanupOrphanedDevices()
    func cleanupOrphanedTaps()
    
    private func findOrphanedDevices() -> [AudioDeviceID]
    private func isSDKDevice(_ deviceID: AudioDeviceID) -> Bool
    private func destroyDevice(_ deviceID: AudioDeviceID) -> Bool
}
```
**Responsibilities:**
- Cleanup of leftover resources
- Device identification
- Error recovery
- System state management

### 10. **AudioRecorder.swift** (Main Public API)
```swift
public final class AudioRecorder {
    private let logger: Logger
    private let cleaner: OrphanedResourceCleaner
    private var currentTap: ProcessTap?
    
    public var outputDirectory: URL?
    public var postProcessingHandler: ((URL) -> Void)?
    public var metricsHandler: ((AudioMetrics) -> Void)?
    
    public init()
    public func startRecording(pid: pid_t, outputFile: URL, outputDeviceID: Int?) throws
    public func stopRecording()
    
    // Convenience methods
    public func startRecording(processName: String, outputFile: URL, outputDeviceName: String?) throws
    public static func listOutputAudioDevices() -> [AudioDeviceInfo]
    public static func listInputAudioDevices() -> [AudioDeviceInfo] 
    public static func listAudioCapableProcesses() -> [AudioProcessInfo]
    // ... other convenience methods
}
```
**Responsibilities:**
- Public API coordination
- High-level recording operations
- Convenience method delegation
- Resource lifecycle management

## Implementation Strategy

### Phase 1: Extract Utilities and Data Structures
1. Create `Core/Errors.swift` with expanded error types
2. Create `Core/AudioDeviceInfo.swift` and `Discovery/AudioProcessInfo.swift`
3. Move `Utils/CoreAudioExtensions.swift` with minimal changes
4. Update imports and ensure compilation

### Phase 2: Extract Discovery Services
1. Create `Discovery/DeviceDiscovery.swift` and move device enumeration logic
2. Create `Discovery/ProcessDiscovery.swift` and move process discovery logic
3. Update `AudioRecorder` to use new discovery services
4. Add unit tests for discovery functionality

### Phase 3: Extract Recording Components
1. Create `Recording/AudioFileWriter.swift` for file operations
2. Create `Recording/AudioMetrics.swift` for real-time analysis
3. Create `Management/OrphanedResourceCleaner.swift`
4. Refactor `ProcessTap` to use extracted components

### Phase 4: Finalize and Test
1. Update `AudioRecorder` to orchestrate all components
2. Add comprehensive unit tests for each module
3. Add integration tests for end-to-end scenarios
4. Performance testing and optimization

## Benefits of This Refactoring

### **Maintainability**
- Single responsibility principle for each module
- Easier to locate and fix bugs
- Clearer code organization

### **Testability** 
- Each component can be unit tested in isolation
- Mock/stub dependencies for testing
- Better test coverage of edge cases

### **Reusability**
- Discovery services can be used independently
- Utility extensions available across the SDK
- Components can be composed differently for different use cases

### **Extensibility**
- Easy to add new device types or audio formats
- New recording modes can reuse existing components
- Plugin architecture for post-processing

### **Performance**
- Specialized classes can be optimized independently
- Lazy loading of discovery services
- Better memory management with focused lifecycles

## Breaking Changes and Migration

### **Public API Changes**
- `AudioDeviceInfo` gains additional properties
- New convenience methods added to `AudioRecorder`
- Error types expanded (backwards compatible)

### **Migration Path**
- Current public API remains functional
- New convenience methods added alongside existing ones
- Deprecation warnings for any removed functionality
- Migration guide with before/after examples

## File Structure
```
AudioSDK/
├── Core/
│   ├── Errors.swift
│   └── AudioDeviceInfo.swift
├── Utils/
│   └── CoreAudioExtensions.swift
├── Discovery/
│   ├── DeviceDiscovery.swift
│   └── ProcessDiscovery.swift
├── Recording/
│   ├── ProcessTap.swift
│   ├── AudioFileWriter.swift
│   └── AudioMetrics.swift
├── Management/
│   └── OrphanedResourceCleaner.swift
├── AudioRecorder.swift
└── Tests/
    ├── CoreTests/
    ├── UtilsTests/
    ├── DiscoveryTests/
    ├── RecordingTests/
    ├── ManagementTests/
    └── IntegrationTests/
```