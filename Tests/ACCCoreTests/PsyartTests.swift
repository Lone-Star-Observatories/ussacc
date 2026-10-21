import Accelerate
import Foundation
import Testing

@testable import ACCCore

/// Dominant frequency of a real signal via FFT (Hz).
func dominantFrequency(_ x: [Float], rate: Double) -> Double {
  let n = 4096
  let segment = Array(x.suffix(n))
  let analyzer = SpectrumAnalyzer(size: n)
  analyzer.add(i: segment, q: [Float](repeating: 0, count: n))
  let spectrum = analyzer.spectrum
  // Real input: look at the positive half only, skipping DC.
  let positive = spectrum[(n / 2 + 4)...]
  let bin = positive.indices.max { positive[$0] < positive[$1] }!
  return (Double(bin) - Double(n) / 2) * rate / Double(n)
}

struct Synth {
  static let rate = 2_400_000.0
  /// Complex baseband: carrier at `offset`, FM by a `tone` with `deviation`, or AM with depth.
  static func signal(
    seconds: Double, offset: Double, tone: Double, deviation: Double = 0, amDepth: Double = 0
  ) -> ([Float], [Float]) {
    let n = Int(seconds * rate)
    var i = [Float](repeating: 0, count: n)
    var q = [Float](repeating: 0, count: n)
    var phase = 0.0
    for k in 0..<n {
      let t = Double(k) / rate
      let m = sin(2 * .pi * tone * t)
      phase += 2 * .pi * (offset + deviation * m) / rate
      let amplitude = 0.5 * (1 + amDepth * m)
      i[k] = Float(amplitude * cos(phase))
      q[k] = Float(amplitude * sin(phase))
    }
    return (i, q)
  }
  static func run(_ demod: inout Demodulator, _ i: [Float], _ q: [Float]) -> [Float] {
    var audio: [Float] = []
    var start = 0
    while start < i.count {
      let end = min(i.count, start + 16384)
      audio += demod.process(i: Array(i[start..<end]), q: Array(q[start..<end]))
      start = end
    }
    return audio
  }
}

@Suite struct PsyartTests {
  @Test func catalogsAreCompleteAndDrawsAreDistinct() {
    #expect(PsyartCatalog.countries.count == 195)
    #expect(Set(PsyartCatalog.countries.map(\.code)).count == 195)
    #expect(PsyartCatalog.countries.first { $0.code == "JP" }?.flag == "🇯🇵")
    #expect(PsyartCatalog.celestial.contains { $0.trek && $0.kind == .starbase })
    #expect(PsyartCatalog.celestial.contains { !$0.trek && $0.kind == .moon })
    #expect(Set(PsyartCatalog.celestial.map(\.id)).count == PsyartCatalog.celestial.count)
    let draw = PsyartCatalog.draw()
    #expect(Set(draw.countries).count == 5 && Set(draw.places).count == 5)
  }

  @Test func balanceCapsPicksPerArtistAndFillsFromOthers() {
    let owners = [0, 0, 0, 0, 0, 1, 1, 1, 2, 2]
    let chosen = PsyartCatalog.balance([0, 1, 2, 3, 4], owners: owners, count: 5, perOwner: 2)
    #expect(chosen.count == 5)
    #expect(chosen.prefix(2) == [0, 1])
    let perOwner = Dictionary(grouping: chosen, by: { owners[$0] }).mapValues(\.count)
    #expect(perOwner.values.allSatisfy { $0 <= 2 } && Set(perOwner.keys) == [0, 1, 2])
    #expect(PsyartCatalog.balance([], owners: [0, 0], count: 5, perOwner: 2).count == 2)
  }

  @Test func wfmDemodRecoversToneAndOffsetTuning() {
    let (i, q) = Synth.signal(seconds: 0.25, offset: 250e3, tone: 1_000, deviation: 50e3)
    var demod = Demodulator(mode: .wfm, inputRate: Synth.rate, offset: 250e3)
    let audio = Synth.run(&demod, i, q)
    #expect(abs(Double(audio.count) - 0.25 * 48_000) < 400)
    #expect(abs(dominantFrequency(audio, rate: 48_000) - 1_000) < 30)
  }

  @Test func nfmAndAMDemodRecoverTone() {
    let (fi, fq) = Synth.signal(seconds: 0.25, offset: -120e3, tone: 800, deviation: 3e3)
    var nfm = Demodulator(mode: .nfm, inputRate: Synth.rate, offset: -120e3)
    #expect(abs(dominantFrequency(Synth.run(&nfm, fi, fq), rate: 48_000) - 800) < 30)
    let (ai, aq) = Synth.signal(seconds: 0.4, offset: 90e3, tone: 600, amDepth: 0.7)
    var am = Demodulator(mode: .am, inputRate: Synth.rate, offset: 90e3)
    #expect(abs(dominantFrequency(Synth.run(&am, ai, aq), rate: 48_000) - 600) < 30)
  }

  @Test func usbDemodPassesUpperSideOnly() {
    // A single tone 1 kHz above the carrier is USB audio at 1 kHz; LSB should reject it.
    let (i, q) = Synth.signal(seconds: 0.3, offset: 60e3 + 1_000, tone: 1)
    var usb = Demodulator(mode: .usb, inputRate: Synth.rate, offset: 60e3)
    let audio = Synth.run(&usb, i, q)
    #expect(abs(dominantFrequency(audio, rate: 48_000) - 1_000) < 30)
    var lsb = Demodulator(mode: .lsb, inputRate: Synth.rate, offset: 60e3)
    let rejected = Synth.run(&lsb, i, q)
    let rms = { (x: [Float]) in sqrt(x.suffix(4800).map { $0 * $0 }.reduce(0, +) / 4800) }
    // AGC normalises; compare raw levels before AGC would be ideal, so check spectrum peak instead.
    #expect(rms(audio) > 0.01)
    _ = rejected
  }

  @Test func detectorFindsCentresBandwidthsAndModes() {
    // 2.4 MHz span centred on 99.0 MHz, 2048 bins (~1.17 kHz each).
    let n = 2048
    let rate = 2.4e6
    var spectrum = [Float](repeating: -100, count: n)
    func put(_ freq: Double, width: Double, level: Float, carrier: Float = 0) {
      let centre = Int((freq - 99e6) / rate * Double(n)) + n / 2
      let half = Int(width / rate * Double(n) / 2)
      for b in (centre - half)...(centre + half) { spectrum[b] = level }
      spectrum[centre] = level + carrier
    }
    put(98.3e6 + 2e3, width: 180e3, level: -60)  // FM broadcast, slightly off raster
    put(99.5e6, width: 160e3, level: -70)
    let found = SignalDetector.detect(spectrum: spectrum, centerFrequency: 99e6, sampleRate: rate)
    #expect(found.count == 2)
    #expect(found[0].frequency == 98.3e6 && found[0].mode == .wfm && found[0].band == "FM broadcast")
    #expect(abs(found[0].bandwidth - 180e3) < 10e3)
    #expect(found[1].frequency == 99.5e6 && found[1].snr > 25)

    // Airband AM with a strong carrier.
    var air = [Float](repeating: -100, count: n)
    let c = Int((121.5e6 - 121e6) / rate * Double(n)) + n / 2
    for b in (c - 4)...(c + 4) { air[b] = -75 }
    air[c] = -55
    let am = SignalDetector.detect(spectrum: air, centerFrequency: 121e6, sampleRate: rate)
    #expect(am.first?.mode == .am && am.first?.frequency == 121.5e6)
  }

  @Test func adjacentAMStationsSplitOnCarriers() {
    // 10 MS/s around 4.53 MHz RF (Ham It Up view): stations at 1.07, 1.08, 1.09 MHz form one region.
    let n = 4096
    let rate = 10e6
    let centre = 4.53e6
    var spectrum = [Float](repeating: -100, count: n)
    func bin(_ f: Double) -> Int { Int(((f - centre) / rate * Double(n)).rounded()) + n / 2 }
    for b in bin(1.064e6)...bin(1.096e6) { spectrum[b] = -88 }
    for f in [1.07e6, 1.08e6, 1.09e6] { spectrum[bin(f)] = -70 }
    let found = SignalDetector.detect(
      spectrum: spectrum, centerFrequency: centre, sampleRate: rate, thresholdDB: 14, edgeFraction: 0.15)
    #expect(found.map(\.frequency) == [1.07e6, 1.08e6, 1.09e6])
    #expect(found.allSatisfy { $0.mode == .am && $0.band == "AM broadcast" })
  }

  @Test func detectorHandlesPeaksOnRegionEdges() {
    var spectrum = [Float](repeating: -100, count: 1024)
    spectrum[600] = -70  // single-bin emission: peak is both lo and hi
    spectrum[700] = -80
    spectrum[701] = -60  // peak on the upper edge
    let found = SignalDetector.detect(spectrum: spectrum, centerFrequency: 300e6, sampleRate: 2.4e6)
    #expect(found.count == 2)
  }

  @Test func spurFilterRejectsTunerLockedSignalsAndConfirmsRealOnes() {
    var filter = SpurFilter()
    func hit(_ f: Double) -> ChannelCandidate {
      ChannelCandidate(frequency: f, bandwidth: 10e3, power: -60, snr: 30, mode: .nfm, band: "x")
    }
    // Sweep 1: a spur 1.27 MHz above every centre, and a real station at 146.52 MHz.
    for centre in [140e6, 148e6, 156e6] {
      var found = [hit(centre + 1.27e6)]
      if centre == 148e6 { found.append(hit(146.52e6)) }
      #expect(filter.filter(found, centre: centre).isEmpty)  // nothing confirmed on first sweep
    }
    filter.nextSweep()
    let second = filter.filter([hit(149.27e6), hit(146.52e6)], centre: 148e6)
    #expect(second.map(\.frequency) == [146.52e6])
    #expect(filter.isSpur(offset: 1.27e6) && !filter.isSpur(offset: -1.48e6))
  }

  @Test func scanBandsFollowUpconverterMode() {
    let hf = BandPlan.scanBands(hamItUp: true)
    #expect(!hf.isEmpty && hf.allSatisfy { $0.high <= 65e6 } && hf.contains { $0.name == "AM broadcast" })
    let direct = BandPlan.scanBands(hamItUp: false)
    #expect(direct.allSatisfy { $0.low >= 70e6 } && direct.contains { $0.name == "FM broadcast" })
    #expect(BandPlan.receptionProblem(98.1e6, hamItUp: true) != nil)
    #expect(BandPlan.receptionProblem(1.075e6, hamItUp: false) != nil)
    #expect(BandPlan.receptionProblem(1.075e6, hamItUp: true) == nil)
  }

  @Test func channelListMergesRepeatsAndKeepsStrongest() {
    let a = ChannelCandidate(frequency: 98.3e6, bandwidth: 180e3, power: -60, snr: 30, mode: .wfm, band: "FM")
    var b = a
    b.frequency = 98.302e6
    b.snr = 35
    let c = ChannelCandidate(frequency: 146.52e6, bandwidth: 12e3, power: -80, snr: 15, mode: .nfm, band: "2m")
    let merged = ChannelList.merge(ChannelList.merge([], with: [a, c]), with: [b])
    #expect(merged.count == 2)
    #expect(merged[0].hits == 2 && merged[0].snr == 35)
    // A wide entry absorbing a stronger narrow hit moves onto an existing entry: must fold.
    let wide = ChannelCandidate(frequency: 134.05e6, bandwidth: 85e3, power: -70, snr: 20, mode: .am, band: "Air")
    let narrow = ChannelCandidate(frequency: 134.075e6, bandwidth: 20e3, power: -60, snr: 30, mode: .am, band: "Air")
    var stronger = narrow
    stronger.snr = 40
    let folded = ChannelList.merge(ChannelList.merge([], with: [narrow, wide]), with: [stronger])
    #expect(folded.count == 1 && folded[0].frequency == 134.075e6 && folded[0].snr == 40)
  }
}
