import ACCCore
import os
import AppKit
import SwiftUI

/// Developer-only rendering of this app's own view, using demo content and no account access.
@MainActor enum PreviewExporter {
  /// Developer checks run with demo content and must not touch saved session state.
  static var isDevRun: Bool {
    let arguments = ProcessInfo.processInfo.arguments
    return [
      "--snapshot-dir", "--check-classifier", "--check-terminal", "--probe-imap", "--sdr-scan-test",
      "--sdr-listen-test", "--psyart-test", "--sdr-worker-test",
    ].contains(
      where: arguments.contains)
  }
  static func runIfRequested(model: AppModel, psyart: PsyartModel? = nil) async {
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--psyart-test"), let psyart {
      await psyart.generate()
      if let page = psyart.page, psyart.error.isEmpty {
        print("PSYART: \(page.title) — \(page.tagline)")
        print("PSYART: countries \(page.countries.map(\.name).joined(separator: ", "))")
        print("PSYART: worlds \(page.places.map { $0.name + ($0.trek ? " [trek]" : "") }.joined(separator: ", "))")
        print("PSYART: place records \(page.info.count)/10")
        for item in page.artists { print("PSYART: artist  \(item.verified ? "✓" : "✗") \(item.title)") }
        for item in page.songs { print("PSYART: song    \(item.verified ? "✓" : "✗") \(item.title) — \(item.artist)\(item.preview == nil ? "" : " ♪")") }
        for item in page.albums { print("PSYART: album   \(item.verified ? "✓" : "✗") \(item.title) — \(item.artist)") }
        for item in page.videos { print("PSYART: video   \(item.title) [\(item.query)]") }
      } else { print("PSYART: failed: \(psyart.error)") }
      NSApplication.shared.terminate(nil)
      return
    }
    if arguments.contains("--check-classifier") {
      print(Intelligence.availability)
      for (body, known) in [
        ("Can you confirm our meeting tonight, Allen?", true),
        ("Action required by Friday: your venue contract for the Oct 30 event must be signed or the booking is released.", false),
        ("Receipt for your order #4821: telescope eyepiece, $89.00. Thanks for shopping.", false),
        ("This week's newsletter: 10 stargazing tips and our autumn sale.", false),
        ("CONGRATULATIONS!!! You have been selected for a free cruise. Click here.", false),
        ("Your parcel is delayed. No action needed.", false),
      ] {
        let item = Communication(
          name: "Sample", address: "sample@example.com", channel: .email, body: body, isDemo: true)
        let result = await Intelligence.classify(item, known: known)
        print("CLASSIFIER: \(result.level.map(String.init) ?? "unscored") | \(result.reason)")
      }
      NSApplication.shared.terminate(nil)
      return
    }
    if let index = arguments.firstIndex(of: "--probe-imap"), arguments.indices.contains(index + 1) {
      // Checks TLS, greeting, capabilities and error handling with a deliberately invalid login.
      let host = arguments[index + 1]
      let transport = NetworkIMAPTransport(host: host, port: 993)
      do {
        try await transport.open()
        let session = IMAPSession(transport: transport)
        try await session.greeting()
        print("IMAP: TLS + greeting OK from \(host)")
        print("IMAP: capabilities \(await session.capabilities.sorted().prefix(12).joined(separator: " "))")
        do {
          try await session.login(user: "probe@invalid.example", password: "not-a-password")
          print("IMAP: unexpected login success")
        } catch { print("IMAP: invalid login rejected as expected: \(error.localizedDescription)") }
        await session.logout()
      } catch { print("IMAP: probe failed: \(error.localizedDescription)") }
      NSApplication.shared.terminate(nil)
      return
    }
    if arguments.contains("--sdr-worker-test") {
      // Runs the app's radio thread headless: 20 s background scan, then 4 s of listening.
      let ring = AudioRing()
      let worker = SDRWorker(ring: ring)
      let log = OSAllocatedUnfairLock(initialState: (statuses: [String](), scans: 0, found: [ChannelCandidate](), spectra: 0))
      worker.onStatus = { text in log.withLock { if $0.statuses.last != text { $0.statuses.append(text) } } }
      worker.onScan = { _ in log.withLock { $0.scans += 1 } }
      worker.onSpectrum = { _, _ in log.withLock { $0.spectra += 1 } }
      worker.onChannels = { found in log.withLock { $0.found = ChannelList.merge($0.found, with: found) } }
      let ham = ProcessInfo.processInfo.environment["SDR_HAM"] == "1"
      worker.update {
        $0.online = true
        $0.hamItUp = ham
        $0.frequency = ham ? 1.08e6 : 98.1e6
        $0.mode = ham ? .am : .wfm
      }
      if ProcessInfo.processInfo.environment["SDR_OPT"] == "1" {
        // Optimizer only: detect, centre and fit bandwidth at the configured frequency.
        let steps = OSAllocatedUnfairLock(initialState: [TuneOptimizer.Step]())
        let done = OSAllocatedUnfairLock(initialState: String?.none)
        worker.onOptimizerStep = { step in steps.withLock { $0.append(step) } }
        worker.onOptimizerDone = { offset, width, gain, failure in
          done.withLock {
            $0 = failure ?? String(format: "centre %+.0f Hz · bandwidth %.2f kHz · gain %+.1f dB", offset, width / 1e3, gain)
          }
        }
        worker.update { $0.optimizeRequest += 1 }
        worker.start()
        for _ in 0..<60 where done.withLock({ $0 }) == nil { try? await Task.sleep(for: .milliseconds(500)) }
        for step in steps.withLock({ $0 }) {
          print(String(format: "SDR opt: %2d %@ %@ centre %+6.0f Hz bw %6.2f kHz snr %5.1f dB", step.index, step.phase.rawValue, step.accepted ? "✓" : "·", step.offset, step.bandwidth / 1e3, step.snr))
        }
        print("SDR opt: result \(done.withLock { $0 } ?? "timed out") · statuses \(log.withLock { $0.statuses }.joined(separator: " | "))")
        NSApplication.shared.terminate(nil)
        return
      }
      worker.start()
      try? await Task.sleep(for: .seconds(20))
      let scan = log.withLock { $0 }
      print("SDR worker: \(scan.scans) scan steps · \(scan.spectra) spectra · \(scan.found.count) channels")
      for c in scan.found.sorted(by: { $0.snr > $1.snr }).prefix(8) {
        print(String(format: "SDR worker:   %.6f MHz bw %.0f %@ %@ snr %.0f dB hits %d", c.frequency / 1e6, c.bandwidth, c.mode.rawValue, c.band, c.snr, c.hits))
      }
      worker.update { $0.listen = true }
      try? await Task.sleep(for: .seconds(4))
      var probe = [Float](repeating: 0, count: 48_000)
      probe.withUnsafeMutableBufferPointer { ring.pull(into: $0.baseAddress!, count: 48_000) }
      let rms = sqrt(probe.map { $0 * $0 }.reduce(0, +) / 48_000)
      print("SDR worker: listening audio RMS \(String(format: "%.3f", rms)) · statuses: \(log.withLock { $0.statuses }.joined(separator: " | "))")
      NSApplication.shared.terminate(nil)
      return
    }
    if arguments.contains("--sdr-scan-test") {
      // Sweeps FM broadcast on the connected bladeRF and prints detected stations.
      do {
        let radio = try BladeRFDevice()
        try radio.configure(sampleRate: SDRTuning.scanRate, bandwidth: 8_000_000)
        try radio.setGain(nil)
        let analyzer = SpectrumAnalyzer(size: 4096)
        var channels: [ChannelCandidate] = []
        let env = ProcessInfo.processInfo.environment
        let start = env["SDR_START"].flatMap(Double.init) ?? 92e6
        let end = env["SDR_END"].flatMap(Double.init) ?? 108e6
        for centre in stride(from: start, through: end, by: 8e6) {
          try radio.tune(centre)
          _ = try radio.read(16384)
          analyzer.reset()
          for _ in 0..<4 {
            let (i, q) = try radio.read(16384)
            analyzer.add(i: i, q: q)
          }
          let found = SignalDetector.detect(
            spectrum: analyzer.spectrum, centerFrequency: centre, sampleRate: radio.sampleRate,
            thresholdDB: 14, skipCenter: 60e3, minimumBins: 3)
          channels = ChannelList.merge(channels, with: found)
        }
        radio.close()
        for c in channels.sorted(by: { $0.snr > $1.snr }).prefix(15) {
          print(String(format: "SDR: %8.3f MHz  bw %5.0f kHz  snr %4.1f dB  %@", c.frequency / 1e6, c.bandwidth / 1e3, c.snr, c.mode.rawValue))
        }
        print("SDR: \(channels.count) channels detected")
      } catch { print("SDR: scan failed: \(error.localizedDescription)") }
      NSApplication.shared.terminate(nil)
      return
    }
    if let index = arguments.firstIndex(of: "--sdr-listen-test"), arguments.indices.contains(index + 1),
      let mhz = Double(arguments[index + 1])
    {
      // Demodulates WFM for 3 s and checks the 19 kHz stereo pilot in the FM baseband.
      do {
        let radio = try BladeRFDevice()
        let env = ProcessInfo.processInfo.environment
        try radio.configure(
          sampleRate: env["SDR_RATE"].flatMap(Double.init) ?? SDRTuning.listenRate,
          bandwidth: env["SDR_BW"].flatMap(Double.init) ?? 1_500_000)
        let manualGain = ProcessInfo.processInfo.environment["SDR_GAIN"].flatMap { Int($0) }
        try radio.setGain(manualGain)
        let mode = SDRMode(rawValue: env["SDR_MODE"] ?? "WFM") ?? .wfm
        let ham = env["SDR_HAM"] == "1"
        try radio.tune(SDRWorker.tunerFrequency(mhz * 1e6, hamItUp: ham) - SDRTuning.listenOffset)
        _ = try radio.read(16384)
        var demod = Demodulator(mode: mode, inputRate: radio.sampleRate, offset: SDRTuning.listenOffset)
        var mixer = Mixer(frequency: SDRTuning.listenOffset, rate: radio.sampleRate)
        var decimator = ComplexDecimator(taps: FIR.lowpass(cutoff: 110e3, rate: radio.sampleRate, taps: 81), factor: 10)
        var fm = FMDemodulator()
        let baseband = SpectrumAnalyzer(size: 4096)
        var audio: [Float] = []
        var pending: [Float] = []
        for _ in 0..<Int(3 * radio.sampleRate / 16384) {
          let (i, q) = try radio.read(16384)
          audio += demod.process(i: i, q: q)
          var mi = i
          var mq = q
          mixer.process(i: &mi, q: &mq)
          let (di, dq) = decimator.process(i: mi, q: mq)
          pending += fm.process(i: di, q: dq)
          if pending.count >= 4096 {
            baseband.add(i: Array(pending.prefix(4096)), q: [Float](repeating: 0, count: 4096))
            pending.removeFirst(4096)
          }
        }
        // Channel power: station band vs equal-width noise reference elsewhere in the capture.
        let (ci, cq) = try radio.read(65536)
        let rf = SpectrumAnalyzer(size: 4096)
        rf.add(i: ci, q: cq)
        let rfSpectrum = rf.spectrum
        let hz = radio.sampleRate / 4096
        func bandPower(_ from: Double, _ to: Double) -> Float {
          let a = 2048 + Int(from / hz)
          let b = 2048 + Int(to / hz)
          return 10 * log10(rfSpectrum[a...b].map { pow(10, $0 / 10) }.reduce(0, +))
        }
        let half = mode == .wfm ? 90e3 : 5e3
        let station = bandPower(SDRTuning.listenOffset - half, SDRTuning.listenOffset + half)
        let noise = bandPower(SDRTuning.listenOffset + 60e3 - half, SDRTuning.listenOffset + 60e3 + half)
        let peaks = rfSpectrum.indices.sorted { rfSpectrum[$0] > rfSpectrum[$1] }.prefix(5)
          .map { String(format: "%+.0fk:%.0f", (Double($0) - 2048) * hz / 1e3, rfSpectrum[$0]) }
        let sortedRF = rfSpectrum.sorted()
        print("SDR: rate \(Int(radio.sampleRate)) · median \(String(format: "%.1f", sortedRF[2048])) dB · peaks \(peaks.joined(separator: " "))")
        print(String(format: "SDR: gain %@ · channel power %.1f dB vs reference %.1f dB (CNR ≈ %.1f dB)", manualGain.map(String.init) ?? "AGC", station, noise, station - noise))
        radio.close()
        let spectrum = baseband.spectrum
        let binHz = 240_000.0 / 4096
        let pilotBin = 2048 + Int(19_000 / binHz)
        let pilot = spectrum[(pilotBin - 2)...(pilotBin + 2)].max()!
        let around = (spectrum[(pilotBin - 40)...(pilotBin - 10)] + spectrum[(pilotBin + 10)...(pilotBin + 40)]).sorted()
        let floor = around[around.count / 2]
        let rms = sqrt(audio.map { $0 * $0 }.reduce(0, +) / Float(max(audio.count, 1)))
        print(String(format: "SDR: %.3f MHz · %d audio samples · RMS %.3f · 19 kHz pilot %+.1f dB over neighbours", mhz, audio.count, rms, pilot - floor))
      } catch { print("SDR: listen failed: \(error.localizedDescription)") }
      NSApplication.shared.terminate(nil)
      return
    }
    if arguments.contains("--check-terminal") {
      let marker = "/private/tmp/ussacc-pty-" + UUID().uuidString
      let session = ShellSession(directory: "/private/tmp")
      session.start()
      try? await Task.sleep(for: .milliseconds(500))
      session.terminal.send(txt: "printf USS_ACC_PTY_OK > " + marker + "\n")
      for _ in 0..<20 {
        if let text = try? String(contentsOfFile: marker, encoding: .utf8), text == "USS_ACC_PTY_OK"
        {
          print("TERMINAL: interactive PTY command passed")
          try? FileManager.default.removeItem(atPath: marker)
          session.stop()
          NSApplication.shared.terminate(nil)
          return
        }
        try? await Task.sleep(for: .milliseconds(250))
      }
      print("TERMINAL: PTY check failed")
      session.stop()
      NSApplication.shared.terminate(nil)
      return
    }
    guard let index = arguments.firstIndex(of: "--snapshot-dir"),
      arguments.indices.contains(index + 1)
    else { return }
    let folder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      model.loadDemo(persist: false)
      guard let window = NSApplication.shared.windows.first(where: { $0.contentView != nil }) else {
        return
      }
      window.setContentSize(NSSize(width: 1450, height: 940))
      for station in Station.allCases {
        model.station = station
        model.settings = false
        try await Task.sleep(for: .milliseconds(650))
        try capture(
          window: window, to: folder.appendingPathComponent(station.rawValue.lowercased() + ".png"))
      }
      model.station = .dev
      model.settings = true
      model.settingsSection = "Spam Filter"
      try await Task.sleep(for: .milliseconds(650))
      try capture(window: window, to: folder.appendingPathComponent("settings.png"))
      model.settingsSection = "Connections"
      try await Task.sleep(for: .milliseconds(650))
      try capture(window: window, to: folder.appendingPathComponent("connections.png"))
      model.settingsSection = "Spam Filter"
      print("Rendered seven USS ACC previews to \(folder.path)")
      NSApplication.shared.terminate(nil)
    } catch {
      fputs("Preview export failed: \(error)\n", stderr)
      NSApplication.shared.terminate(nil)
    }
  }
  private static func capture(window: NSWindow, to url: URL) throws {
    guard let view = window.contentView else { return }
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      throw IntegrationError.message("Cannot render preview bitmap")
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
      throw IntegrationError.message("Cannot encode preview PNG")
    }
    try data.write(to: url, options: .atomic)
  }
}
