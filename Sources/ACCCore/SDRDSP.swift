import Accelerate
import Foundation

// MARK: - Modes and band plan

public enum SDRMode: String, Codable, CaseIterable, Sendable {
  case wfm = "WFM", nfm = "NFM", am = "AM", usb = "USB", lsb = "LSB", digital = "DIGITAL"
  public var listenable: Bool { self != .digital }
}

public struct Band: Sendable, Equatable {
  public var name: String
  public var low: Double
  public var high: Double
  public var mode: SDRMode
  /// Channel raster for snapping detected centres (0 = none), offset from 0 Hz by `rasterOffset`.
  public var raster: Double
  public var rasterOffset: Double
  public var hf: Bool { high <= 60e6 }
  public init(
    _ name: String, _ low: Double, _ high: Double, _ mode: SDRMode, raster: Double = 0,
    offset: Double = 0
  ) {
    self.name = name
    self.low = low
    self.high = high
    self.mode = mode
    self.raster = raster
    rasterOffset = offset
  }
  public func snap(_ frequency: Double) -> Double {
    guard raster > 0 else { return frequency }
    return ((frequency - rasterOffset) / raster).rounded() * raster + rasterOffset
  }
}

public enum BandPlan {
  /// North American-oriented allocations used for scanning and modulation hints.
  public static let bands: [Band] = [
    Band("AM broadcast", 530e3, 1.7e6, .am, raster: 10e3),
    Band("WWV time signal", 2.495e6, 2.505e6, .am, raster: 5e3),
    Band("WWV time signal", 4.995e6, 5.005e6, .am, raster: 5e3),
    Band("WWV time signal", 9.995e6, 10.005e6, .am, raster: 5e3),
    Band("WWV time signal", 14.995e6, 15.005e6, .am, raster: 5e3),
    Band("49m shortwave", 5.9e6, 6.2e6, .am, raster: 5e3),
    Band("40m amateur", 7.0e6, 7.3e6, .lsb, raster: 0),
    Band("41m shortwave", 7.3e6, 7.45e6, .am, raster: 5e3),
    Band("31m shortwave", 9.4e6, 9.9e6, .am, raster: 5e3),
    Band("25m shortwave", 11.6e6, 12.1e6, .am, raster: 5e3),
    Band("20m amateur", 14.0e6, 14.35e6, .usb, raster: 0),
    Band("19m shortwave", 15.1e6, 15.8e6, .am, raster: 5e3),
    Band("CB", 26.965e6, 27.405e6, .am, raster: 10e3),
    Band("10m amateur", 28.0e6, 29.7e6, .usb, raster: 0),
    Band("FM broadcast", 87.9e6, 108e6, .wfm, raster: 200e3, offset: 100e3),
    Band("Airband", 118e6, 137e6, .am, raster: 25e3),
    Band("2m amateur", 144e6, 148e6, .nfm, raster: 5e3),
    Band("Marine VHF", 156e6, 162.025e6, .nfm, raster: 25e3),
    Band("NOAA weather", 162.4e6, 162.55e6, .nfm, raster: 25e3),
    Band("1.25m amateur", 222e6, 225e6, .nfm, raster: 5e3),
    Band("70cm amateur", 420e6, 450e6, .nfm, raster: 5e3),
    Band("ISM 433", 433.05e6, 434.79e6, .digital, raster: 0),
    Band("FRS/GMRS", 462.55e6, 467.725e6, .nfm, raster: 12.5e3),
    Band("ISM 915", 902e6, 928e6, .digital, raster: 0),
    Band("ADS-B", 1089e6, 1091e6, .digital, raster: 0),
  ]
  public static func band(at frequency: Double) -> Band? {
    bands.first { frequency >= $0.low && frequency <= $0.high }
  }
  /// The Ham It Up's upconvert path low-pass filters its input (about 65 MHz), so with it in line
  /// only HF is receivable; without it the bladeRF 2.0 micro tunes from 70 MHz.
  public static let upconverterCutoff = 65e6
  public static func scanBands(hamItUp: Bool) -> [Band] {
    bands.filter { hamItUp ? $0.high <= upconverterCutoff : $0.low >= 70e6 }
  }
  /// Why a frequency can't be received in the current configuration, if it can't.
  public static func receptionProblem(_ frequency: Double, hamItUp: Bool) -> String? {
    if hamItUp && frequency > upconverterCutoff {
      return "Ham It Up in upconvert mode only passes HF (below ~65 MHz). Switch it to bypass and turn HAM IT UP off for VHF/UHF."
    }
    if !hamItUp && frequency < 70e6 {
      return "Below 70 MHz needs the Ham It Up in upconvert mode (turn HAM IT UP on)."
    }
    return nil
  }
}

// MARK: - Detection and classification

public struct ChannelCandidate: Codable, Equatable, Identifiable, Sendable {
  public var frequency: Double
  public var bandwidth: Double
  public var power: Float
  public var snr: Float
  public var mode: SDRMode
  public var band: String
  public var hits: Int
  public var lastSeen: Date
  public var id: Double { frequency }
  public init(
    frequency: Double, bandwidth: Double, power: Float, snr: Float, mode: SDRMode, band: String,
    hits: Int = 1, lastSeen: Date = .now
  ) {
    self.frequency = frequency
    self.bandwidth = bandwidth
    self.power = power
    self.snr = snr
    self.mode = mode
    self.band = band
    self.hits = hits
    self.lastSeen = lastSeen
  }
}

public enum SignalDetector {
  /// Finds emissions in a centred (fft-shifted) power spectrum in dB.
  /// `skipCenter` hides the DC spike of a zero-IF receiver.
  public static func detect(
    spectrum: [Float], centerFrequency: Double, sampleRate: Double, thresholdDB: Float = 10,
    skipCenter: Double = 30e3, edgeFraction: Double = 0.1, minimumBins: Int = 1
  ) -> [ChannelCandidate] {
    let n = spectrum.count
    guard n > 16 else { return [] }
    let binWidth = sampleRate / Double(n)
    let floor = median(spectrum)
    let edge = Int(Double(n) * edgeFraction)
    var detections: [ChannelCandidate] = []
    var i = edge
    while i < n - edge {
      guard spectrum[i] >= floor + thresholdDB else {
        i += 1
        continue
      }
      // Grow the region while bins stay 6 dB over the floor.
      var lo = i
      var hi = i
      while lo > edge, spectrum[lo - 1] > floor + 6 { lo -= 1 }
      while hi < n - edge - 1, spectrum[hi + 1] > floor + 6 { hi += 1 }
      i = hi + 1
      // Power-weighted centroid locates the centre more precisely than the peak bin.
      var weight = 0.0
      var moment = 0.0
      var peak: Float = -.infinity
      var peakBin = lo
      for b in lo...hi {
        let linear = pow(10, Double(spectrum[b] - floor) / 10)
        weight += linear
        moment += linear * Double(b)
        if spectrum[b] > peak {
          peak = spectrum[b]
          peakBin = b
        }
      }
      let centreBin = moment / max(weight, 1e-12)
      var frequency = centerFrequency + (centreBin - Double(n) / 2) * binWidth
      // Receiver spurs are single tones; real emissions occupy several bins.
      if hi - lo + 1 < minimumBins { continue }
      let bandwidth = Double(hi - lo + 1) * binWidth
      // Channelised AM/NFM bands: a wide region is several adjacent stations; split on carriers.
      if let band = BandPlan.band(at: frequency), band.raster > 0, band.mode != .wfm,
        band.mode != .digital, bandwidth > 2.5 * band.raster
      {
        let reach = max(1, Int(band.raster * 0.4 / binWidth))
        var seen: Set<Double> = []
        for b in lo...hi where spectrum[b] >= floor + thresholdDB {
          guard spectrum[max(lo, b - reach)...min(hi, b + reach)].max() == spectrum[b] else { continue }
          let station = band.snap(centerFrequency + (Double(b) - Double(n) / 2) * binWidth)
          guard abs(station - centerFrequency) >= skipCenter, seen.insert(station).inserted else {
            continue
          }
          detections.append(
            ChannelCandidate(
              frequency: station, bandwidth: band.raster, power: spectrum[b],
              snr: spectrum[b] - floor, mode: band.mode, band: band.name))
        }
        continue
      }
      if abs(frequency - centerFrequency) < skipCenter { continue }
      let features = Features(
        spectrum: spectrum, lo: lo, hi: hi, peakBin: peakBin, centre: centreBin, floor: floor)
      let band = BandPlan.band(at: frequency)
      let mode = classify(bandwidth: bandwidth, features: features, band: band, binWidth: binWidth)
      if let band, band.raster > 0 {
        let snapped = band.snap(frequency)
        if abs(snapped - frequency) <= band.raster / 2 { frequency = snapped }
      }
      detections.append(
        ChannelCandidate(
          frequency: frequency, bandwidth: bandwidth, power: peak, snr: peak - floor, mode: mode,
          band: band?.name ?? "Unallocated"))
    }
    return detections
  }

  struct Features {
    /// Carrier prominence: peak bin minus mean of the occupied region (dB).
    var carrier: Float
    /// Energy balance between upper and lower halves around the peak, in dB (positive = upper).
    var asymmetry: Float
    init(spectrum: [Float], lo: Int, hi: Int, peakBin: Int, centre: Double, floor: Float) {
      let region = spectrum[lo...hi]
      let meanLinear = region.map { pow(10, ($0 - floor) / 10) }.reduce(0, +) / Float(region.count)
      carrier = (spectrum[peakBin] - floor) - 10 * log10(max(meanLinear, 1e-9))
      let pivot = peakBin
      let lower = spectrum[lo..<pivot].map { pow(10, ($0 - floor) / 10) }.reduce(0, +)
      let upper = spectrum[(pivot + 1)..<(hi + 1)].map { pow(10, ($0 - floor) / 10) }.reduce(0, +)
      asymmetry = 10 * log10(max(upper, 1e-6) / max(lower, 1e-6))
    }
  }

  static func classify(bandwidth: Double, features: Features, band: Band?, binWidth: Double)
    -> SDRMode
  {
    // Broadcast FM allocations carry WFM even when only the centre of a weak station is visible.
    if band?.mode == .wfm { return .wfm }
    if bandwidth >= 100e3 { return band == nil ? .wfm : .digital }
    if bandwidth <= 4.5e3 && binWidth < 1.5e3 && abs(features.asymmetry) > 6 {
      return features.asymmetry > 0 ? .usb : .lsb
    }
    if features.carrier > 8 { return .am }
    if let mode = band?.mode, mode != .wfm { return mode }
    return .nfm
  }
  static func median(_ values: [Float]) -> Float {
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
  }
}

/// Separates real emissions from receiver spurs during a sweep. Spurs follow the tuner, so they
/// reappear at the same offset from centre at many tunings; real signals stay at one RF frequency.
public struct SpurFilter: Sendable {
  private var offsetCentres: [Int: Set<Int>] = [:]
  private var sightings: [Int: Set<Int>] = [:]
  private var sweep = 0
  public init() {}
  public mutating func nextSweep() { sweep += 1 }
  /// Returns detections that are not spurs and have been seen on at least two sweeps.
  public mutating func filter(_ found: [ChannelCandidate], centre: Double) -> [ChannelCandidate] {
    let centreKey = Int((centre / 1e5).rounded())
    for candidate in found {
      offsetCentres[Self.offsetKey(candidate.frequency - centre), default: []].insert(centreKey)
    }
    return found.filter { candidate in
      let offset = Self.offsetKey(candidate.frequency - centre)
      // Allow neighbouring keys so rounding cannot split a spur's count.
      let tunings = (offset - 1...offset + 1).reduce(into: Set<Int>()) { $0.formUnion(offsetCentres[$1] ?? []) }
      guard tunings.count < 3 else { return false }
      let rf = Int((candidate.frequency / 5e3).rounded())
      sightings[rf, default: []].insert(sweep)
      return sightings[rf]!.count >= 2
    }
  }
  public func isSpur(offset: Double) -> Bool {
    let key = Self.offsetKey(offset)
    return (key - 1...key + 1).reduce(into: Set<Int>()) { $0.formUnion(offsetCentres[$1] ?? []) }.count >= 3
  }
  static func offsetKey(_ offset: Double) -> Int { Int((offset / 5e3).rounded()) }
}

public enum ChannelList {
  /// Merges detections into a list, matching within half a bandwidth (min 5 kHz).
  public static func merge(_ list: [ChannelCandidate], with found: [ChannelCandidate])
    -> [ChannelCandidate]
  {
    var result = list
    for candidate in found {
      let tolerance = max(5e3, min(candidate.bandwidth, 100e3) / 2)
      if let index = result.firstIndex(where: { abs($0.frequency - candidate.frequency) <= tolerance }) {
        var existing = result[index]
        existing.hits += 1
        existing.lastSeen = candidate.lastSeen
        if candidate.snr > existing.snr {
          existing.snr = candidate.snr
          existing.power = candidate.power
          existing.bandwidth = candidate.bandwidth
          existing.mode = candidate.mode
          existing.frequency = candidate.frequency
        }
        result[index] = existing
      } else {
        result.append(candidate)
      }
    }
    return coalesce(result)
  }
  /// Updating an entry can move it onto a neighbour; fold entries that now overlap.
  static func coalesce(_ list: [ChannelCandidate]) -> [ChannelCandidate] {
    var output: [ChannelCandidate] = []
    for candidate in list.sorted(by: { $0.frequency < $1.frequency }) {
      if var last = output.last,
        candidate.frequency - last.frequency <= max(5e3, min(last.bandwidth, candidate.bandwidth, 100e3) / 2)
      {
        let stronger = candidate.snr > last.snr ? candidate : last
        let hits = last.hits + candidate.hits
        last = stronger
        last.hits = hits
        last.lastSeen = max(candidate.lastSeen, output.last!.lastSeen)
        output[output.count - 1] = last
      } else {
        output.append(candidate)
      }
    }
    return output
  }
}

// MARK: - DSP blocks

public enum FIR {
  /// Blackman-windowed sinc low-pass; `cutoff` and `rate` in Hz.
  public static func lowpass(cutoff: Double, rate: Double, taps: Int) -> [Float] {
    let n = taps | 1
    let fc = cutoff / rate
    let mid = Double(n - 1) / 2
    var h = (0..<n).map { i -> Double in
      let x = Double(i) - mid
      let sinc = x == 0 ? 2 * fc : sin(2 * .pi * fc * x) / (.pi * x)
      let w = 0.42 - 0.5 * cos(2 * .pi * Double(i) / Double(n - 1)) + 0.08 * cos(4 * .pi * Double(i) / Double(n - 1))
      return sinc * w
    }
    let sum = h.reduce(0, +)
    h = h.map { $0 / sum }
    return h.map(Float.init)
  }
}

/// Real FIR filter with decimation and history across blocks.
public struct RealDecimator: Sendable {
  let taps: [Float]
  let factor: Int
  var history: [Float]
  public init(taps: [Float], factor: Int) {
    self.taps = taps
    self.factor = factor
    history = [Float](repeating: 0, count: taps.count - 1)
  }
  public mutating func process(_ input: [Float]) -> [Float] {
    let buffer = history + input
    guard buffer.count >= taps.count else {
      history = buffer
      return []
    }
    let outCount = (buffer.count - taps.count) / factor + 1
    var output = [Float](repeating: 0, count: outCount)
    // vDSP_desamp computes a correlation; the windowed-sinc kernel is symmetric so this is convolution.
    vDSP_desamp(buffer, factor, taps, &output, vDSP_Length(outCount), vDSP_Length(taps.count))
    history = Array(buffer[(outCount * factor)...])
    return output
  }
}

public struct ComplexDecimator: Sendable {
  var i: RealDecimator
  var q: RealDecimator
  public init(taps: [Float], factor: Int) {
    i = RealDecimator(taps: taps, factor: factor)
    q = RealDecimator(taps: taps, factor: factor)
  }
  public mutating func process(i inI: [Float], q inQ: [Float]) -> ([Float], [Float]) {
    (i.process(inI), q.process(inQ))
  }
}

/// Numerically controlled oscillator: shifts a complex stream by `-frequency`.
public struct Mixer: Sendable {
  public var frequency: Double
  let rate: Double
  var phase: Double = 0
  public init(frequency: Double, rate: Double) {
    self.frequency = frequency
    self.rate = rate
  }
  public mutating func process(i: inout [Float], q: inout [Float]) {
    let n = i.count
    guard n > 0, frequency != 0 else { return }
    let step = -2 * Double.pi * frequency / rate
    var start = Float(phase)
    var increment = Float(step)
    var phases = [Float](repeating: 0, count: n)
    vDSP_vramp(&start, &increment, &phases, 1, vDSP_Length(n))
    var sines = [Float](repeating: 0, count: n)
    var cosines = [Float](repeating: 0, count: n)
    var count = Int32(n)
    vvsincosf(&sines, &cosines, phases, &count)
    // (i + jq)(c + js) = (ic - qs) + j(is + qc)
    var outI = [Float](repeating: 0, count: n)
    var outQ = [Float](repeating: 0, count: n)
    vDSP_vmmsb(i, 1, cosines, 1, q, 1, sines, 1, &outI, 1, vDSP_Length(n))
    vDSP_vmma(i, 1, sines, 1, q, 1, cosines, 1, &outQ, 1, vDSP_Length(n))
    i = outI
    q = outQ
    phase = (phase + step * Double(n)).truncatingRemainder(dividingBy: 2 * .pi)
  }
}

/// Polar discriminator: instantaneous phase difference in radians per sample.
public struct FMDemodulator: Sendable {
  var lastI: Float = 1
  var lastQ: Float = 0
  public init() {}
  public mutating func process(i: [Float], q: [Float]) -> [Float] {
    let n = i.count
    guard n > 0 else { return [] }
    let previousI = [lastI] + i.dropLast()
    let previousQ = [lastQ] + q.dropLast()
    lastI = i[n - 1]
    lastQ = q[n - 1]
    var cross = [Float](repeating: 0, count: n)  // q*pi - i*pq
    var dot = [Float](repeating: 0, count: n)  // i*pi + q*pq
    vDSP_vmmsb(q, 1, previousI, 1, i, 1, previousQ, 1, &cross, 1, vDSP_Length(n))
    vDSP_vmma(i, 1, previousI, 1, q, 1, previousQ, 1, &dot, 1, vDSP_Length(n))
    var out = [Float](repeating: 0, count: n)
    var count = Int32(n)
    vvatan2f(&out, cross, dot, &count)
    return out
  }
}

public struct Deemphasis: Sendable {
  let alpha: Float
  var state: Float = 0
  public init(tau: Double, rate: Double) { alpha = Float(1 - exp(-1 / (rate * tau))) }
  public mutating func process(_ x: [Float]) -> [Float] {
    x.map { sample in
      state += alpha * (sample - state)
      return state
    }
  }
}

/// Slow automatic gain to a target RMS, used for AM and SSB audio.
public struct AudioAGC: Sendable {
  var level: Float = 0.01
  var dc: Float = 0
  public init() {}
  public mutating func process(_ x: [Float], removeDC: Bool) -> [Float] {
    x.map { sample in
      var s = sample
      if removeDC {
        dc += 0.0005 * (s - dc)
        s -= dc
      }
      level += 0.0005 * (abs(s) - level)
      return max(-1, min(1, s * 0.25 / max(level, 1e-4)))
    }
  }
}

/// Full receive chain from complex baseband at `inputRate` to 48 kHz mono audio.
public struct Demodulator: Sendable {
  public let mode: SDRMode
  public static let audioRate = 48_000.0
  let inputRate: Double
  var mixer: Mixer
  var stage1: ComplexDecimator  // → 240 kHz
  var stage2: ComplexDecimator  // → 48 kHz (narrow modes)
  var audioDecimator: RealDecimator  // WFM 240 kHz → 48 kHz
  var fm = FMDemodulator()
  var deemphasis: Deemphasis
  var agc = AudioAGC()
  var ssbDown: Mixer
  var ssbFilterI: RealDecimator
  var ssbFilterQ: RealDecimator
  var ssbUp: Mixer
  /// `offset` is the station's distance from the tuned centre (offset tuning avoids the DC spike).
  public init(mode: SDRMode, inputRate: Double, offset: Double) {
    self.mode = mode
    self.inputRate = inputRate
    mixer = Mixer(frequency: offset, rate: inputRate)
    let stage1Factor = Int((inputRate / 240_000).rounded())
    stage1 = ComplexDecimator(
      taps: FIR.lowpass(cutoff: mode == .wfm ? 110e3 : 60e3, rate: inputRate, taps: 8 * stage1Factor + 1),
      factor: stage1Factor)
    let narrowCutoff: Double = mode == .nfm ? 7.5e3 : mode == .am ? 5e3 : 3.2e3
    stage2 = ComplexDecimator(taps: FIR.lowpass(cutoff: narrowCutoff, rate: 240e3, taps: 121), factor: 5)
    audioDecimator = RealDecimator(taps: FIR.lowpass(cutoff: 15e3, rate: 240e3, taps: 81), factor: 5)
    deemphasis = Deemphasis(tau: 75e-6, rate: 240e3)
    let shift = mode == .lsb ? -1_500.0 : 1_500.0
    ssbDown = Mixer(frequency: shift, rate: Self.audioRate)
    ssbUp = Mixer(frequency: -shift, rate: Self.audioRate)
    let ssbTaps = FIR.lowpass(cutoff: 1_400, rate: Self.audioRate, taps: 161)
    ssbFilterI = RealDecimator(taps: ssbTaps, factor: 1)
    ssbFilterQ = RealDecimator(taps: ssbTaps, factor: 1)
  }
  public mutating func process(i inI: [Float], q inQ: [Float]) -> [Float] {
    var i = inI
    var q = inQ
    mixer.process(i: &i, q: &q)
    let (wI, wQ) = stage1.process(i: i, q: q)
    switch mode {
    case .wfm:
      let baseband = deemphasis.process(fm.process(i: wI, q: wQ))
      return audioDecimator.process(baseband).map { $0 * 0.6 }
    case .digital:
      return []
    default:
      let (nI, nQ) = stage2.process(i: wI, q: wQ)
      switch mode {
      case .nfm:
        // 5 kHz deviation at 48 kHz ≈ 0.65 rad/sample peak.
        return fm.process(i: nI, q: nQ).map { max(-1, min(1, $0 * 1.2)) }
      case .am:
        let magnitude = zip(nI, nQ).map { sqrt($0 * $0 + $1 * $1) }
        return agc.process(magnitude, removeDC: true)
      default:  // USB / LSB via Weaver method
        var sI = nI
        var sQ = nQ
        ssbDown.process(i: &sI, q: &sQ)
        var fI = ssbFilterI.process(sI)
        var fQ = ssbFilterQ.process(sQ)
        let count = min(fI.count, fQ.count)
        fI = Array(fI.prefix(count))
        fQ = Array(fQ.prefix(count))
        ssbUp.process(i: &fI, q: &fQ)
        return agc.process(fI, removeDC: false)
      }
    }
  }
}

/// Averaged, windowed, fft-shifted power spectrum in dB.
public final class SpectrumAnalyzer: @unchecked Sendable {
  public let size: Int
  private let setup: OpaquePointer
  private let window: [Float]
  private var accumulator: [Float]
  public private(set) var frames = 0
  public init(size: Int) {
    self.size = size
    setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(size), .FORWARD)!
    var w = [Float](repeating: 0, count: size)
    vDSP_hann_window(&w, vDSP_Length(size), Int32(vDSP_HANN_NORM))
    window = w
    accumulator = [Float](repeating: 0, count: size)
  }
  deinit { vDSP_DFT_DestroySetup(setup) }
  public func reset() {
    accumulator = [Float](repeating: 0, count: size)
    frames = 0
  }
  /// Adds every complete `size` frame in the block.
  public func add(i: [Float], q: [Float]) {
    var offset = 0
    while offset + size <= i.count {
      var inR = [Float](repeating: 0, count: size)
      var inI = [Float](repeating: 0, count: size)
      vDSP_vmul(Array(i[offset..<(offset + size)]), 1, window, 1, &inR, 1, vDSP_Length(size))
      vDSP_vmul(Array(q[offset..<(offset + size)]), 1, window, 1, &inI, 1, vDSP_Length(size))
      var outR = [Float](repeating: 0, count: size)
      var outI = [Float](repeating: 0, count: size)
      vDSP_DFT_Execute(setup, inR, inI, &outR, &outI)
      var power = [Float](repeating: 0, count: size)
      outR.withUnsafeMutableBufferPointer { r in
        outI.withUnsafeMutableBufferPointer { im in
          var split = DSPSplitComplex(realp: r.baseAddress!, imagp: im.baseAddress!)
          vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(size))
        }
      }
      vDSP_vadd(accumulator, 1, power, 1, &accumulator, 1, vDSP_Length(size))
      frames += 1
      offset += size
    }
  }
  public var spectrum: [Float] {
    guard frames > 0 else { return [Float](repeating: -120, count: size) }
    let half = size / 2
    let shifted = Array(accumulator[half...]) + Array(accumulator[..<half])
    return shifted.map { 10 * log10(max($0 / Float(frames), 1e-20)) }
  }
}

/// Converts interleaved SC16 Q11 samples to separate I/Q floats in [-1, 1).
public func deinterleaveQ11(_ samples: UnsafeBufferPointer<Int16>, count: Int) -> ([Float], [Float]) {
  var i = [Float](repeating: 0, count: count)
  var q = [Float](repeating: 0, count: count)
  guard let base = samples.baseAddress else { return (i, q) }
  vDSP_vflt16(base, 2, &i, 1, vDSP_Length(count))
  vDSP_vflt16(base + 1, 2, &q, 1, vDSP_Length(count))
  var scale: Float = 1 / 2048
  vDSP_vsmul(i, 1, &scale, &i, 1, vDSP_Length(count))
  vDSP_vsmul(q, 1, &scale, &q, 1, vDSP_Length(count))
  return (i, q)
}
