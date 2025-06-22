//
//  ProcessDiscovery.swift
//  AudioSDK
//
//  Enumerates and looks up audio-capable processes.
//

import Foundation
import AudioToolbox
import Darwin

public struct ProcessDiscovery {
    /// Returns a list of running processes that are audio-capable (i.e., have a valid CoreAudio object).
    public static func listAudioCapableProcesses() -> [(pid: pid_t, name: String)] {
        var result: [(pid_t, String)] = []
        var procCount = proc_listallpids(nil, 0)
        guard procCount > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(procCount))
        procCount = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        for pid in pids where pid > 0 {
            var nameBuf = [CChar](repeating: 0, count: 1024)
            let nameResult = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let procName = nameResult > 0 ? String(cString: nameBuf) : "(unknown)"
            do {
                _ = try AudioObjectID.translatePIDToProcessObjectID(pid: pid)
                result.append((pid, procName))
            } catch {
                continue
            }
        }
        return result
    }

    /// Returns the PID of the first audio-capable process matching the given name (case-insensitive).
    public static func pidForAudioCapableProcess(named name: String) -> pid_t? {
        let procs = listAudioCapableProcesses()
        return procs.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.pid
    }
} 