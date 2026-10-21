import Foundation
import Testing

@testable import ACCCore

@Suite struct OptimizerTests {
  /// 8192-bin spectrum at 2.4 MS/s with noise around -100 dB and an optional flat-topped signal.
  func spectrum(signalAt centre: Double?, width: Double, level: Float = -80, seed: UInt64) -> ([Float], Double) {
    let n = 8192
    let binHz = 2.4e6 / Double(n)
    var generator = SplitMix(seed: seed)
    var s = (0..<n).map { _ in -100 + Float.random(in: -1...1, using: &generator) }
    if let centre {
      for b in 0..<n {
        let f = (Double(b) - Double(n) / 2) * binHz
        let distance = abs(f - centre)
        if distance <= width / 2 {
          s[b] = level + Float.random(in: -0.5...0.5, using: &generator)
        } else if distance <= width / 2 + 1.5e3 {
          // 1.5 kHz skirts falling to the noise floor.
          let t = Float((distance - width / 2) / 1.5e3)
          s[b] = max(s[b], level + (-100 - level) * t)
        }
      }
    }
    return (s, binHz)
  }

  @Test func centresOnOffsetSignalThenFitsItsBandwidth() {
    var optimizer = TuneOptimizer(base: 250e3, bandwidth: 10e3, searchRange: 10e3)
    var seed: UInt64 = 1
    while !optimizer.finished && optimizer.history.count < 200 {
      let (s, binHz) = spectrum(signalAt: 253e3, width: 6e3, seed: seed)
      optimizer.step(spectrum: s, binHz: binHz)
      seed += 1
    }
    #expect(optimizer.finished && optimizer.failure == nil)
    #expect(abs(optimizer.offset - 3e3) <= 400)
    // Fitted to the occupied width (6 kHz plus skirts), not collapsed to a sliver.
    #expect(optimizer.bandwidth > 5e3 && optimizer.bandwidth < 9e3)
    #expect(optimizer.gain > 1)
    #expect(optimizer.history.contains { $0.phase == .centre && $0.accepted })
    #expect(optimizer.history.contains { $0.phase == .bandwidth && $0.accepted })
  }

  @Test func detectJumpsToNearbySignalAndReportsAbsence() {
    var jump = TuneOptimizer(base: 250e3, bandwidth: 10e3, searchRange: 20e3)
    let (s, binHz) = spectrum(signalAt: 265e3, width: 6e3, seed: 7)
    jump.step(spectrum: s, binHz: binHz)
    #expect(jump.phase == .centre && abs(jump.offset - 15e3) <= 3e3)

    var none = TuneOptimizer(base: 250e3, bandwidth: 10e3, searchRange: 20e3)
    let (flat, flatBin) = spectrum(signalAt: nil, width: 0, seed: 9)
    none.step(spectrum: flat, binHz: flatBin)
    #expect(none.finished && none.failure != nil)
  }

  @Test func meterSubtractsNoise() {
    let (s, binHz) = spectrum(signalAt: 0, width: 10e3, level: -90, seed: 3)
    let noise = SNRMeter.noiseDensity(s)
    let wide = SNRMeter.measure(spectrum: s, binHz: binHz, offset: 0, bandwidth: 40e3, noise: noise)
    let fit = SNRMeter.measure(spectrum: s, binHz: binHz, offset: 0, bandwidth: 10e3, noise: noise)
    #expect(fit.snr > wide.snr)
    #expect(fit.signal > 0.8 * wide.signal)
  }
}

struct SplitMix: RandomNumberGenerator {
  var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
