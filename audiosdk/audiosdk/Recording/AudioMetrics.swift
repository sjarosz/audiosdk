//
//  AudioMetrics.swift
//  AudioSDK
//
//  Provides real-time audio metrics (RMS, decibel).
//

import Foundation
import Accelerate

public struct AudioMetrics {
    /// Computes the RMS (root mean square) of a buffer of Float samples.
    public static func rms(samples: [Float]) -> Float {
        var meanSquare: Float = 0
        vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(samples.count))
        return sqrt(meanSquare)
    }

    /// Computes the decibel value from RMS.
    public static func decibels(rms: Float) -> Float {
        return 20 * log10(rms)
    }
} 