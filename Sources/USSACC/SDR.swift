import ACCCore
import AVFoundation
import Darwin
import Foundation

/// libbladeRF loaded at runtime, so USS ACC still launches on machines without it.
final class BladeRFLibrary: @unchecked Sendable {
  typealias OpenFn = @convention(c) (UnsafeMutablePointer<OpaquePointer?>, UnsafePointer<CChar>?) -> Int32
  typealias CloseFn = @convention(c) (OpaquePointer?) -> Void
  typealias FrequencyFn = @convention(c) (OpaquePointer?, Int32, UInt64) -> Int32
  typealias RateFn = @convention(c) (OpaquePointer?, Int32, UInt32, UnsafeMutablePointer<UInt32>?) -> Int32
  typealias IntFn = @convention(c) (OpaquePointer?, Int32, Int32) -> Int32
  typealias SyncConfigFn = @convention(c) (OpaquePointer?, Int32, Int32, UInt32, UInt32, UInt32, UInt32) -> Int32
  typealias EnableFn = @convention(c) (OpaquePointer?, Int32, Bool) -> Int32
  typealias SyncRxFn = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?, UInt32) -> Int32
  typealias StrErrorFn = @convention(c) (Int32) -> UnsafePointer<CChar>?

  let open: OpenFn
  let close: CloseFn
  let setFrequency: FrequencyFn
  let setSampleRate: RateFn
  let setBandwidth: RateFn
  let setGainMode: IntFn
  let setGain: IntFn
  let syncConfig: SyncConfigFn
  let enableModule: EnableFn
  let syncRx: SyncRxFn
  let strerror: StrErrorFn

  static let shared = BladeRFLibrary()
  static let rx0: Int32 = 0  // BLADERF_CHANNEL_RX(0)

  private init?() {
    let paths = ["/opt/homebrew/lib/libbladeRF.dylib", "/usr/local/lib/libbladeRF.dylib", "libbladeRF.dylib"]
    guard let handle = paths.lazy.compactMap({ dlopen($0, RTLD_NOW) }).first else { return nil }
    func symbol<T>(_ name: String, _: T.Type) -> T? {
      dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
    }
    guard let open = symbol("bladerf_open", OpenFn.self), let close = symbol("bladerf_close", CloseFn.self),
      let setFrequency = symbol("bladerf_set_frequency", FrequencyFn.self),
      let setSampleRate = symbol("bladerf_set_sample_rate", RateFn.self),
      let setBandwidth = symbol("bladerf_set_bandwidth", RateFn.self),
      let setGainMode = symbol("bladerf_set_gain_mode", IntFn.self),
      let setGain = symbol("bladerf_set_gain", IntFn.self),
      let syncConfig = symbol("bladerf_sync_config", SyncConfigFn.self),
      let enableModule = symbol("bladerf_enable_module", EnableFn.self),
      let syncRx = symbol("bladerf_sync_rx", SyncRxFn.self),
      let strerror = symbol("bladerf_strerror", StrErrorFn.self)
    else { return nil }
    self.open = open
    self.close = close
    self.setFrequency = setFrequency
    self.setSampleRate = setSampleRate
    self.setBandwidth = setBandwidth
    self.setGainMode = setGainMode
    self.setGain = setGain
    self.syncConfig = syncConfig
    self.enableModule = enableModule
    self.syncRx = syncRx
    self.strerror = strerror
  }
  func message(_ code: Int32) -> String {
    strerror(code).map { String(cString: $0) } ?? "bladeRF error \(code)"
  }
}

/// One open bladeRF receiving on RX1 as SC16 Q11.
final class BladeRFDevice {
  private let lib: BladeRFLibrary
  private var device: OpaquePointer?
  private(set) var sampleRate: Double = 0
  private var streaming = false
  static let minimumFrequency = 70e6

  init() throws {
    guard let lib = BladeRFLibrary.shared else {
      throw IntegrationError.message("libbladeRF not found. Install it with: brew install libbladerf")
    }
    self.lib = lib
    let status = lib.open(&device, nil)
    guard status == 0, device != nil else {
      throw IntegrationError.message("bladeRF: \(lib.message(status))")
    }
  }
  deinit { close() }
  func close() {
    if streaming { _ = lib.enableModule(device, BladeRFLibrary.rx0, false) }
    streaming = false
    if let device { lib.close(device) }
    device = nil
  }
  private func check(_ status: Int32, _ what: String) throws {
    if status != 0 { throw IntegrationError.message("bladeRF \(what): \(lib.message(status))") }
  }
  /// Reconfigures the stream for a sample rate and analog bandwidth.
  func configure(sampleRate rate: Double, bandwidth: Double) throws {
    if streaming {
      _ = lib.enableModule(device, BladeRFLibrary.rx0, false)
      streaming = false
    }
    var actual: UInt32 = 0
    try check(lib.setSampleRate(device, BladeRFLibrary.rx0, UInt32(rate), &actual), "sample rate")
    sampleRate = Double(actual)
    try check(lib.setBandwidth(device, BladeRFLibrary.rx0, UInt32(bandwidth), &actual), "bandwidth")
    try check(lib.syncConfig(device, 0, 0, 16, 16384, 8, 3500), "stream")
    try check(lib.enableModule(device, BladeRFLibrary.rx0, true), "enable")
    streaming = true
  }
  func tune(_ frequency: Double) throws {
    try check(lib.setFrequency(device, BladeRFLibrary.rx0, UInt64(frequency)), "tune")
  }
  /// nil = hardware AGC; otherwise manual gain in dB.
  func setGain(_ gain: Int?) throws {
    if let gain {
      try check(lib.setGainMode(device, BladeRFLibrary.rx0, 1), "gain mode")
      try check(lib.setGain(device, BladeRFLibrary.rx0, Int32(gain)), "gain")
    } else {
      try check(lib.setGainMode(device, BladeRFLibrary.rx0, 0), "gain mode")
    }
  }
  /// Reads `count` complex samples.
  func read(_ count: Int) throws -> ([Float], [Float]) {
    var buffer = [Int16](repeating: 0, count: count * 2)
    let status = buffer.withUnsafeMutableBytes { lib.syncRx(device, $0.baseAddress, UInt32(count), nil, 3500) }
    try check(status, "receive")
    return buffer.withUnsafeBufferPointer { deinterleaveQ11($0, count: count) }
  }
}

/// Lock-protected audio FIFO feeding the output node.
final class AudioRing: @unchecked Sendable {
  private var samples: [Float] = []
  private var head = 0
  private let lock = NSLock()
  func push(_ audio: [Float]) {
    lock.lock()
    defer { lock.unlock() }
    if head > 48_000 {
      samples.removeFirst(head)
      head = 0
    }
    samples += audio
    // Bound latency to ~0.5 s by dropping the oldest audio.
    if samples.count - head > 24_000 { head = samples.count - 12_000 }
  }
  func pull(into buffer: UnsafeMutablePointer<Float>, count: Int) {
    lock.lock()
    defer { lock.unlock() }
    let available = min(count, samples.count - head)
    for k in 0..<available { buffer[k] = samples[head + k] }
    for k in available..<count { buffer[k] = 0 }
    head += available
  }
  func clear() {
    lock.lock()
    samples = []
    head = 0
    lock.unlock()
  }
}

/// Receiver state shared by the UI (main actor) and the radio thread.
/// Radio constants shared by the UI and the radio thread.
enum SDRTuning {
  static let hamItUpOffset = 125e6
  static let listenRate = 2_400_000.0
  static let scanRate = 10_000_000.0
  /// Listening tunes this far below the station so the DC spike stays out of the channel.
  static let listenOffset = 250e3
}

@MainActor final class SDRController: ObservableObject {

  @Published var online: Bool { didSet { save(); worker.update { $0.online = online } } }
  @Published var hamItUp: Bool {
    didSet {
      save()
      worker.update { $0.hamItUp = hamItUp }
      // Land somewhere receivable for the new path: the strongest known channel it can pass,
      // else WWV 10 MHz through the upconverter or FM without it.
      if BandPlan.receptionProblem(frequency, hamItUp: hamItUp) != nil {
        if let best = channels.filter({
          $0.mode.listenable && BandPlan.receptionProblem($0.frequency, hamItUp: hamItUp) == nil
        }).max(by: { $0.snr < $1.snr }) {
          tune(to: best)
        } else {
          frequency = hamItUp ? 10e6 : 98.1e6
          mode = hamItUp ? .am : .wfm
        }
      }
    }
  }
  @Published var frequency: Double { didSet { save(); worker.update { $0.frequency = frequency } } }
  @Published var mode: SDRMode { didSet { save(); worker.update { $0.mode = mode } } }
  @Published var gain: Int? { didSet { worker.update { $0.gain = gain } } }
  @Published var volume: Float = 0.8 { didSet { player.volume = volume } }
  /// User wants audio; it plays only while the PSYART station is on screen.
  @Published var audioOn = false { didSet { syncListen() } }
  var stationVisible = false { didSet { syncListen() } }
  @Published private(set) var status = "SDR offline"
  @Published private(set) var scanning = ""
  @Published private(set) var channels: [ChannelCandidate] = []
  @Published private(set) var spectrum: [Float] = []
  @Published private(set) var level: Float = -120
  let available = BladeRFLibrary.shared != nil

  private let worker: SDRWorker
  private let player = AudioPlayer()
  private let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("USSACC")

  init() {
    let defaults = UserDefaults.standard
    online = defaults.object(forKey: "sdr.online") as? Bool ?? true
    hamItUp = defaults.bool(forKey: "sdr.hamItUp")
    frequency = defaults.object(forKey: "sdr.frequency") as? Double ?? 98.1e6
    mode = SDRMode(rawValue: defaults.string(forKey: "sdr.mode") ?? "") ?? .wfm
    channels =
      (try? LocalPersistence.load(
        [ChannelCandidate].self,
        from: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
          .appendingPathComponent("USSACC/channels.json"))) ?? []
    worker = SDRWorker(ring: player.ring)
    worker.update {
      $0.online = online
      $0.hamItUp = hamItUp
      $0.frequency = frequency
      $0.mode = mode
    }
    worker.onStatus = { [weak self] text in Task { @MainActor in self?.status = text } }
    worker.onScan = { [weak self] text in Task { @MainActor in self?.scanning = text } }
    worker.onSpectrum = { [weak self] bins, level in
      Task { @MainActor in
        self?.spectrum = bins
        self?.level = level
      }
    }
    worker.onChannels = { [weak self] found in
      Task { @MainActor in self?.merge(found) }
    }
  }
  /// Starts the radio thread unless running developer checks.
  func start() { if available { worker.start() } else { status = "libbladeRF not installed" } }
  func tune(to channel: ChannelCandidate) {
    frequency = channel.frequency
    if channel.mode.listenable { mode = channel.mode }
  }
  func step(_ hz: Double) { frequency = max(100e3, frequency + hz) }
  func clearChannels() {
    channels = []
    saveChannels()
  }
  private func syncListen() {
    let listen = audioOn && stationVisible
    worker.update { $0.listen = listen }
    if listen { player.start(volume: volume) } else { player.stop() }
  }
  private func merge(_ found: [ChannelCandidate]) {
    channels = Array(
      ChannelList.merge(channels, with: found).sorted { $0.snr > $1.snr }.prefix(400)
    ).sorted { $0.frequency < $1.frequency }
    saveChannels()
  }
  private func saveChannels() {
    try? LocalPersistence.save(channels, to: folder.appendingPathComponent("channels.json"))
  }
  private func save() {
    let defaults = UserDefaults.standard
    defaults.set(online, forKey: "sdr.online")
    defaults.set(hamItUp, forKey: "sdr.hamItUp")
    defaults.set(frequency, forKey: "sdr.frequency")
    defaults.set(mode.rawValue, forKey: "sdr.mode")
  }
}

final class AudioPlayer {
  let ring = AudioRing()
  private let engine = AVAudioEngine()
  private var source: AVAudioSourceNode?
  var volume: Float = 0.8 { didSet { engine.mainMixerNode.outputVolume = volume } }
  func start(volume: Float) {
    self.volume = volume
    guard !engine.isRunning else { return }
    ring.clear()
    if source == nil {
      let format = AVAudioFormat(standardFormatWithSampleRate: Demodulator.audioRate, channels: 1)!
      let ring = self.ring
      let node = AVAudioSourceNode(format: format) { _, _, frameCount, buffers in
        let list = UnsafeMutableAudioBufferListPointer(buffers)
        if let data = list.first?.mData?.assumingMemoryBound(to: Float.self) {
          ring.pull(into: data, count: Int(frameCount))
        }
        return noErr
      }
      engine.attach(node)
      engine.connect(node, to: engine.mainMixerNode, format: format)
      source = node
    }
    engine.mainMixerNode.outputVolume = volume
    try? engine.start()
  }
  func stop() {
    engine.stop()
    ring.clear()
  }
}

/// Owns the device on a dedicated thread: listens when asked, otherwise sweeps the band plan.
final class SDRWorker: @unchecked Sendable {
  struct Config: Equatable {
    var online = false
    var listen = false
    var hamItUp = false
    var frequency = 98.1e6
    var mode: SDRMode = .wfm
    var gain: Int?
  }
  private var config = Config()
  private let lock = NSLock()
  private let ring: AudioRing
  private var thread: Thread?
  private var spurs = SpurFilter()
  var onStatus: (String) -> Void = { _ in }
  var onScan: (String) -> Void = { _ in }
  var onSpectrum: ([Float], Float) -> Void = { _, _ in }
  var onChannels: ([ChannelCandidate]) -> Void = { _ in }

  init(ring: AudioRing) { self.ring = ring }
  func update(_ change: (inout Config) -> Void) {
    lock.lock()
    change(&config)
    lock.unlock()
  }
  var snapshot: Config {
    lock.lock()
    defer { lock.unlock() }
    return config
  }
  func start() {
    guard thread == nil else { return }
    let thread = Thread { [weak self] in self?.run() }
    thread.name = "USS ACC SDR"
    thread.qualityOfService = .userInitiated
    thread.start()
    self.thread = thread
  }

  /// Converts an RF frequency to the tuner frequency, applying the upconverter offset.
  static func tunerFrequency(_ rf: Double, hamItUp: Bool) -> Double {
    hamItUp ? rf + SDRTuning.hamItUpOffset : rf
  }

  private func run() {
    var device: BladeRFDevice?
    var configuredRate = 0.0
    while true {
      let current = snapshot
      guard current.online else {
        device?.close()
        device = nil
        configuredRate = 0
        onStatus("SDR offline")
        Thread.sleep(forTimeInterval: 0.3)
        continue
      }
      do {
        if device == nil {
          device = try BladeRFDevice()
          configuredRate = 0
          onStatus("bladeRF 2.0 connected")
        }
        guard let radio = device else { continue }
        if current.listen {
          try listen(radio, &configuredRate)
        } else {
          try scan(radio, &configuredRate)
        }
      } catch {
        onStatus(error.localizedDescription)
        device?.close()
        device = nil
        Thread.sleep(forTimeInterval: 2)
      }
    }
  }

  private func listen(_ radio: BladeRFDevice, _ configuredRate: inout Double) throws {
    if configuredRate != SDRTuning.listenRate {
      try radio.configure(sampleRate: SDRTuning.listenRate, bandwidth: 1_500_000)
      configuredRate = SDRTuning.listenRate
    }
    var active = snapshot
    func retune(_ config: Config) throws -> Demodulator {
      if let problem = BandPlan.receptionProblem(config.frequency, hamItUp: config.hamItUp) {
        onStatus(problem)
      }
      let tuner = Self.tunerFrequency(config.frequency, hamItUp: config.hamItUp) - SDRTuning.listenOffset
      guard tuner >= BladeRFDevice.minimumFrequency else {
        throw IntegrationError.message("Below 70 MHz needs the Ham It Up upconverter (turn on HAM IT UP).")
      }
      try radio.tune(tuner)
      try radio.setGain(config.gain)
      if BandPlan.receptionProblem(config.frequency, hamItUp: config.hamItUp) == nil {
        onStatus("Listening \(String(format: "%.4f", config.frequency / 1e6)) MHz \(config.mode.rawValue)")
      }
      return Demodulator(mode: config.mode, inputRate: radio.sampleRate, offset: SDRTuning.listenOffset)
    }
    var demod = try retune(active)
    let analyzer = SpectrumAnalyzer(size: 1024)
    var blocks = 0
    while true {
      let current = snapshot
      if !current.online || !current.listen { return }
      if current.frequency != active.frequency || current.mode != active.mode
        || current.hamItUp != active.hamItUp || current.gain != active.gain
      {
        active = current
        demod = try retune(active)
      }
      let (i, q) = try radio.read(16384)
      ring.push(demod.process(i: i, q: q))
      blocks += 1
      if blocks % 6 == 0 {
        analyzer.reset()
        analyzer.add(i: Array(i.prefix(4096)), q: Array(q.prefix(4096)))
        let spectrum = analyzer.spectrum
        // Level near the station (offset bins either side of +250 kHz).
        let bin = Int(SDRTuning.listenOffset / radio.sampleRate * 1024) + 512
        let level = spectrum[max(0, bin - 3)...min(1023, bin + 3)].max() ?? -120
        onSpectrum(Self.downsample(spectrum, to: 160), level)
      }
    }
  }

  private func scan(_ radio: BladeRFDevice, _ configuredRate: inout Double) throws {
    if configuredRate != SDRTuning.scanRate {
      try radio.configure(sampleRate: SDRTuning.scanRate, bandwidth: 8_000_000)
      configuredRate = SDRTuning.scanRate
    }
    try radio.setGain(nil)
    let span = radio.sampleRate
    // Detection ignores the outer 15% each side, so each tuning covers ±35% of the span.
    let usableHalf = span * 0.35
    let analyzer = SpectrumAnalyzer(size: 4096)
    let hamItUp = snapshot.hamItUp
    let bands = BandPlan.scanBands(hamItUp: hamItUp)
    for band in bands {
      // Starting a full half-span above the band edge keeps narrow bands clear of the DC notch.
      var centre = band.low + usableHalf
      repeat {
        let current = snapshot
        if !current.online || current.listen || current.hamItUp != hamItUp { return }
        onScan("Scanning \(band.name) · \(String(format: "%.3f", centre / 1e6)) MHz")
        try radio.tune(Self.tunerFrequency(centre, hamItUp: hamItUp))
        _ = try radio.read(16384)  // settle after retune
        analyzer.reset()
        for _ in 0..<4 {
          let (i, q) = try radio.read(16384)
          analyzer.add(i: i, q: q)
        }
        let spectrum = analyzer.spectrum
        onSpectrum(Self.downsample(spectrum, to: 160), spectrum.max() ?? -120)
        let found = SignalDetector.detect(
          spectrum: spectrum, centerFrequency: centre, sampleRate: span, thresholdDB: 14,
          skipCenter: 60e3, edgeFraction: 0.15, minimumBins: 3
        ).filter { $0.frequency >= band.low && $0.frequency <= band.high }
        let confirmed = spurs.filter(found, centre: centre)
        if !confirmed.isEmpty { onChannels(confirmed) }
        centre += 2 * usableHalf
      } while centre - usableHalf < band.high
    }
    spurs.nextSweep()
  }

  static func downsample(_ spectrum: [Float], to count: Int) -> [Float] {
    let chunk = max(1, spectrum.count / count)
    return stride(from: 0, to: spectrum.count - chunk + 1, by: chunk).map {
      spectrum[$0..<($0 + chunk)].max() ?? -120
    }
  }
}
