import Foundation

/// Signal-to-noise inside a channel window of a centred (fft-shifted) dB power spectrum.
public enum SNRMeter {
  /// Median per-bin linear power: robust noise density when signals occupy a minority of bins.
  public static func noiseDensity(_ spectrum: [Float]) -> Double {
    let sorted = spectrum.sorted()
    return pow(10, Double(sorted[sorted.count / 2]) / 10)
  }
  /// Linear signal power (noise subtracted) and SNR in dB for a window `offset ± bandwidth/2`,
  /// where `offset` is measured from the spectrum centre.
  public static func measure(
    spectrum: [Float], binHz: Double, offset: Double, bandwidth: Double, noise: Double
  ) -> (snr: Double, signal: Double) {
    let n = spectrum.count
    let centre = Double(n) / 2 + offset / binHz
    let half = max(0.5, bandwidth / binHz / 2)
    let lo = max(0, Int((centre - half).rounded()))
    let hi = min(n - 1, Int((centre + half).rounded()))
    guard lo <= hi else { return (-99, 0) }
    var total = 0.0
    for b in lo...hi { total += pow(10, Double(spectrum[b]) / 10) }
    let noisePower = noise * Double(hi - lo + 1)
    let signal = max(total - noisePower, 1e-30)
    return (10 * log10(signal / noisePower), signal)
  }
}

/// Hill-climbs a channel's centre, then its bandwidth, to maximise SNR.
/// Narrowing always raises the ratio until only the carrier remains, so the bandwidth phase
/// refuses windows that keep less than `minimumRetention` of the signal power seen at the start.
public struct TuneOptimizer: Sendable {
  public enum Phase: String, Sendable { case detect = "DETECT", centre = "CENTRE", bandwidth = "BANDWIDTH", done = "DONE" }
  public struct Step: Equatable, Sendable, Identifiable {
    public var index: Int
    public var phase: Phase
    public var offset: Double
    public var bandwidth: Double
    public var snr: Double
    public var accepted: Bool
    public var id: Int { index }
  }
  public private(set) var phase: Phase = .detect
  public private(set) var offset: Double
  public private(set) var bandwidth: Double
  public private(set) var history: [Step] = []
  public private(set) var failure: String?
  /// Frequency offset of the tuned channel from the spectrum centre (e.g. the listen offset).
  let base: Double
  let searchRange: Double
  var centreStep: Double
  let minimumCentreStep: Double
  var widthFactor = 0.25
  let minimumWidthFactor = 0.02
  let minimumRetention: Double
  var referenceSignal = 0.0
  var best = -Double.infinity
  let minimumWidth: Double
  let maximumWidth: Double
  /// AM: the carrier holds most of the power but no audio, so retention is judged on the
  /// sidebands with the carrier notched out.
  let excludeCarrier: Bool

  public init(
    base: Double, bandwidth: Double, searchRange: Double, minimumRetention: Double = 0.9,
    excludeCarrier: Bool = false
  ) {
    self.excludeCarrier = excludeCarrier
    self.base = base
    self.bandwidth = bandwidth
    self.searchRange = searchRange
    offset = 0
    centreStep = max(200, min(searchRange / 4, bandwidth / 4))
    minimumCentreStep = 100
    self.minimumRetention = minimumRetention
    minimumWidth = max(500, bandwidth / 8)
    maximumWidth = bandwidth * 3
  }
  public var finished: Bool { phase == .done }
  public var gain: Double {
    guard let first = history.first(where: { $0.phase != .detect || $0.accepted })?.snr,
      let last = history.last(where: { $0.accepted })?.snr
    else { return 0 }
    return last - first
  }

  /// One optimisation step on a fresh spectrum. Returns the step recorded.
  @discardableResult public mutating func step(spectrum: [Float], binHz: Double) -> Step {
    let noise = SNRMeter.noiseDensity(spectrum)
    func snr(_ offset: Double, _ width: Double) -> (snr: Double, signal: Double) {
      SNRMeter.measure(spectrum: spectrum, binHz: binHz, offset: base + offset, bandwidth: width, noise: noise)
    }
    /// Power that counts toward retention: everything, or sidebands only for AM.
    func retained(_ offset: Double, _ width: Double) -> Double {
      let total = snr(offset, width).signal
      guard excludeCarrier else { return total }
      let carrier = snr(offset, max(3 * binHz, 300)).signal
      return max(total - carrier, 0)
    }
    switch phase {
    case .detect:
      var current = snr(offset, bandwidth)
      if current.snr < 6 {
        // Look for the strongest window within the search range.
        var bestOffset = offset
        var bestSNR = current.snr
        var probe = -searchRange
        while probe <= searchRange {
          let value = snr(probe, bandwidth).snr
          if value > bestSNR {
            bestSNR = value
            bestOffset = probe
          }
          probe += max(binHz, bandwidth / 4)
        }
        guard bestSNR >= 6 else {
          failure = "No signal within ±\(Int(searchRange / 1e3)) kHz"
          phase = .done
          return record(.detect, current.snr, accepted: false)
        }
        offset = bestOffset
        current = snr(offset, bandwidth)
      }
      best = current.snr
      phase = .centre
      return record(.detect, current.snr, accepted: true)

    case .centre:
      // A half-width probe only peaks when it sits on the signal's energy; a full-width window
      // that already contains the whole signal would be flat across small shifts. AM locks onto
      // its carrier with a narrow probe, since program audio makes the sidebands lopsided.
      let probe = excludeCarrier ? max(3 * binHz, 300) : bandwidth / 2
      let up = snr(offset + centreStep, probe).snr
      let down = snr(offset - centreStep, probe).snr
      best = snr(offset, probe).snr  // re-measure: spectra are noisy frame to frame
      if max(up, down) > best + 0.05, abs(offset + (up >= down ? centreStep : -centreStep)) <= searchRange {
        offset += up >= down ? centreStep : -centreStep
        best = max(up, down)
        return record(.centre, best, accepted: true)
      }
      centreStep /= 2
      if centreStep < minimumCentreStep {
        referenceSignal = retained(offset, bandwidth * 2)
        phase = .bandwidth
        best = snr(offset, bandwidth).snr
      }
      return record(.centre, best, accepted: false)

    case .bandwidth:
      best = snr(offset, bandwidth).snr
      let candidates = [bandwidth * (1 - widthFactor), bandwidth * (1 + widthFactor)]
        .filter { $0 >= minimumWidth && $0 <= maximumWidth }
      var choice: (width: Double, snr: Double)?
      for width in candidates {
        let value = snr(offset, width)
        guard retained(offset, width) >= minimumRetention * referenceSignal else { continue }
        if value.snr > best + 0.05, value.snr > (choice?.snr ?? -.infinity) { choice = (width, value.snr) }
      }
      if let choice {
        bandwidth = choice.width
        best = choice.snr
        return record(.bandwidth, best, accepted: true)
      }
      widthFactor /= 2
      if widthFactor < minimumWidthFactor { phase = .done }
      return record(.bandwidth, best, accepted: false)

    case .done:
      return history.last ?? record(.done, best, accepted: false)
    }
  }
  private mutating func record(_ phase: Phase, _ snr: Double, accepted: Bool) -> Step {
    let step = Step(
      index: history.count, phase: phase, offset: offset, bandwidth: bandwidth, snr: snr,
      accepted: accepted)
    history.append(step)
    return step
  }
}

extension SDRMode {
  /// Starting channel bandwidth for each demodulator.
  public var defaultBandwidth: Double {
    switch self {
    case .wfm: 180e3
    case .nfm: 12.5e3
    case .am: 10e3
    case .usb, .lsb: 2.8e3
    case .digital: 25e3
    }
  }
}
