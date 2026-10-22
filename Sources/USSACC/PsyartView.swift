import ACCCore
import AppKit
import Charts
import SwiftUI
import WebKit

struct PsyartView: View {
  @EnvironmentObject private var psy: PsyartModel
  @EnvironmentObject private var sdr: SDRController
  @State private var keyEditor = false
  @State private var featured = 0
  @State private var place: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      if let page = psy.page {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            hero(page)
            HStack(alignment: .top, spacing: 16) {
              videoWall(page).frame(maxWidth: .infinity)
              listeningRoom(page).frame(width: 430)
            }
            coordinates(page)
          }.padding(.bottom, 6)
        }
        .onChange(of: page.created) { _, _ in
          featured = 0
          place = nil
        }
      } else {
        ACCPanel {
          EmptyStation(
            symbol: "sparkles", title: "AWAITING TRANSMISSION",
            detail: "Compose a new cultural transmission: music and video curated on device.")
        }.frame(maxHeight: .infinity)
      }
      if sdr.optimizing || !sdr.optimizerSteps.isEmpty { SNROptimizerPanel() }
      SDRStrip()
    }
    .onAppear { sdr.stationVisible = true }
    .onDisappear { sdr.stationVisible = false }
  }

  var header: some View {
    HStack(alignment: .bottom, spacing: 16) {
      StationTitle(station: .psyart)
      Spacer(minLength: 20)
      if psy.busy || !psy.error.isEmpty {
        Text(psy.busy ? psy.phase : psy.error).font(.acc(17)).foregroundStyle(
          psy.busy ? Color.accLavender : Color.accPeach
        ).lineLimit(2).frame(maxWidth: 420, alignment: .trailing)
      }
      if !psy.youtubeKeySaved {
        Button("Add YouTube key") { keyEditor = true }.buttonStyle(.plain).font(.lcars(16))
          .foregroundStyle(Color.accLavender)
          .popover(isPresented: $keyEditor) { YouTubeKeyEditor().environmentObject(psy) }
      }
      ACCButton(
        title: psy.busy ? "COMPOSING…" : "NEW TRANSMISSION", symbol: "dice.fill", primary: true
      ) { Task { await psy.generate() } }.fixedSize().disabled(psy.busy)
    }
  }

  // MARK: Hero

  func hero(_ page: PsyartPage) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(page.title.uppercased()).font(.lcars(58, weight: .bold)).foregroundStyle(Color.accPeach)
        .lineLimit(1).minimumScaleFactor(0.6)
      Text(page.tagline).font(.acc(23, weight: .medium)).foregroundStyle(Color.accLavender)
        .lineLimit(1)
      Text(page.reading).font(.acc(15)).foregroundStyle(Color.accDim).lineLimit(2)
        .help(page.reading)
    }.padding(.horizontal, 4)
  }

  // MARK: Video

  func videoWall(_ page: PsyartPage) -> some View {
    let videos = page.videos
    let index = min(featured, max(0, videos.count - 1))
    return VStack(alignment: .leading, spacing: 12) {
      sectionLabel("SCREENING ROOM", detail: psy.youtubeKeySaved ? "YouTube" : "YouTube search · add a key in Settings to play inline")
      if videos.indices.contains(index) {
        let video = videos[index]
        ZStack {
          if let id = video.videoID {
            YouTubePlayer(videoID: id)
          } else {
            Button {
              NSWorkspace.shared.open(video.link)
            } label: {
              ZStack {
                cover(video.thumbnail ?? video.artwork, blur: video.thumbnail == nil)
                Circle().fill(Color.black.opacity(0.55)).frame(width: 86, height: 86)
                Image(systemName: "play.fill").font(.system(size: 34)).foregroundStyle(Color.accPeach)
              }
            }.buttonStyle(.plain)
          }
        }.aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 16))
          .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.accBorder.opacity(0.6), lineWidth: 1))
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text(video.videoTitle ?? video.title).font(.acc(22, weight: .medium)).lineLimit(1)
            Text(video.channel ?? "Opens YouTube search").font(.acc(15)).foregroundStyle(Color.accDim)
          }
          Spacer()
          Link(destination: video.link) {
            Label("YOUTUBE", systemImage: "arrow.up.right").font(.lcars(15))
          }.foregroundStyle(Color.accLavender)
        }
        HStack(spacing: 10) {
          ForEach(Array(videos.enumerated()), id: \.element.id) { n, other in
            if n != index {
              Button {
                featured = n
              } label: {
                VStack(alignment: .leading, spacing: 5) {
                  ZStack {
                    cover(other.thumbnail ?? other.artwork, blur: false)
                    Image(systemName: "play.circle.fill").font(.system(size: 22))
                      .foregroundStyle(.white.opacity(0.9)).shadow(radius: 3)
                  }.aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10))
                  Text(other.videoTitle ?? other.title).font(.acc(13)).foregroundStyle(Color.accText)
                    .lineLimit(2).multilineTextAlignment(.leading)
                }.frame(maxWidth: .infinity, alignment: .leading)
              }.buttonStyle(.plain)
            }
          }
        }
      }
    }
  }

  // MARK: Music

  func listeningRoom(_ page: PsyartPage) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionLabel("LISTENING ROOM", detail: "Apple Music")
      HStack(spacing: 12) {
        ForEach(page.albums) { album in
          Button {
            if let link = album.link { NSWorkspace.shared.open(link) }
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              artwork(album.artwork, size: 203)
              Text(album.title).font(.acc(15, weight: .medium)).lineLimit(1)
              Text(album.artist).font(.acc(13)).foregroundStyle(Color.accDim).lineLimit(1)
            }
          }.buttonStyle(.plain)
        }
      }
      VStack(spacing: 6) {
        ForEach(page.songs) { song in
          HStack(spacing: 12) {
            artwork(song.artwork, size: 44)
            VStack(alignment: .leading, spacing: 0) {
              Text(song.title).font(.acc(17, weight: .medium)).lineLimit(1)
              Text(song.artist).font(.acc(13)).foregroundStyle(Color.accDim).lineLimit(1)
            }
            Spacer(minLength: 6)
            if song.preview != nil {
              Button {
                psy.togglePreview(song.preview)
              } label: {
                Image(systemName: psy.playing == song.preview ? "pause.fill" : "play.fill")
                  .font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                  .frame(width: 30, height: 30).background(Color.accPeach, in: Circle())
              }.buttonStyle(.plain).help("30-second preview")
            }
            if let link = song.link {
              Button {
                NSWorkspace.shared.open(link)
              } label: {
                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(Color.accLavender)
              }.buttonStyle(.plain).help("Open in Apple Music")
            }
          }.padding(.vertical, 2)
        }
      }
      HStack(spacing: 14) {
        ForEach(page.artists) { artist in
          Button {
            if let link = artist.link { NSWorkspace.shared.open(link) }
          } label: {
            HStack(spacing: 8) {
              artwork(artist.artwork, size: 40, circle: true)
              VStack(alignment: .leading, spacing: 0) {
                Text(artist.title).font(.acc(14, weight: .medium)).lineLimit(1)
                Text(artist.artist).font(.acc(11)).foregroundStyle(Color.accDim).lineLimit(1)
              }
            }
          }.buttonStyle(.plain)
        }
      }
    }
  }

  // MARK: Coordinates (minor)

  func coordinates(_ page: PsyartPage) -> some View {
    let ids = page.countries.map(\.id) + page.places.map(\.id)
    let selected = place.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first ?? ""
    let country = page.countries.first { $0.id == selected }
    let world = page.places.first { $0.id == selected }
    let info = page.info[selected]
    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Text("COORDINATES").font(.lcars(15)).foregroundStyle(Color.accLavender)
        ForEach(page.countries) { c in
          selectorChip(id: c.id, selected: selected) { Text(c.flag).font(.system(size: 22)) }
            .help(c.name)
        }
        Rectangle().fill(Color.accBorder).frame(width: 1, height: 22)
        ForEach(page.places) { p in
          selectorChip(id: p.id, selected: selected) {
            if let image = page.info[p.id]?.image {
              AsyncImage(url: image) { $0.resizable().scaledToFill() } placeholder: { Color.accField }
                .frame(width: 26, height: 26).clipShape(Circle())
            } else {
              Image(systemName: symbol(p.kind)).font(.system(size: 16))
                .foregroundStyle(p.trek ? Color.accLavender : Color.accGreen)
            }
          }.help(p.name)
        }
        Spacer()
      }
      HStack(alignment: .top, spacing: 12) {
        ZStack {
          Color.accField
          if let image = info?.image {
            AsyncImage(url: image) { $0.resizable().scaledToFill() } placeholder: { Color.accField }
          } else if let country {
            Text(country.flag).font(.system(size: 34))
          }
        }.frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 8) {
            Text(country?.name ?? world?.name ?? "").font(.acc(17, weight: .medium))
            if let world {
              Text(world.trek ? "STAR TREK · \(world.kind.label.uppercased())" : world.kind.label.uppercased())
                .font(.lcars(11)).foregroundStyle(Color.accDim)
            }
          }
          Text(info?.summary ?? "No record found.").font(.acc(14)).foregroundStyle(Color.accDim)
            .lineLimit(3)
          if let link = info?.link {
            Link("OPEN RECORD", destination: link).font(.lcars(12)).foregroundStyle(Color.accPeach)
          }
        }
        Spacer(minLength: 0)
      }
    }.padding(12)
      .background(Color.accCard.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
  }
  func selectorChip<Mark: View>(id: String, selected: String, @ViewBuilder mark: () -> Mark)
    -> some View
  {
    Button {
      place = id
    } label: {
      mark().frame(width: 34, height: 30)
        .background(
          id == selected ? Color.accPeach.opacity(0.28) : Color.clear,
          in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay(alignment: .bottom) {
          if id == selected { Rectangle().fill(Color.accPeach).frame(height: 2) }
        }
    }.buttonStyle(.plain)
  }

  // MARK: Shared

  func sectionLabel(_ title: String, detail: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Rectangle().fill(Color.accPeach).frame(width: 24, height: 4)
      Text(title).font(.lcars(20)).foregroundStyle(Color.accText)
      Text(detail).font(.acc(13)).foregroundStyle(Color.accDim)
    }
  }
  func cover(_ url: URL?, blur: Bool) -> some View {
    ZStack {
      LinearGradient(
        colors: [Color.accLavender.opacity(0.35), Color.accPeach.opacity(0.25)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
      if let url {
        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
          .blur(radius: blur ? 18 : 0).opacity(blur ? 0.85 : 1)
      }
    }
  }
  func symbol(_ kind: CelestialKind) -> String {
    switch kind {
    case .planet: "globe.americas.fill"
    case .dwarfPlanet: "circle.circle"
    case .moon: "moon.fill"
    case .starbase: "star.circle.fill"
    case .station: "antenna.radiowaves.left.and.right"
    }
  }
  func artwork(_ url: URL?, size: CGFloat, circle: Bool = false) -> some View {
    ZStack {
      Color.accField
      if let url {
        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.accField }
      } else {
        Image(systemName: "music.note").foregroundStyle(Color.accLavender)
      }
    }.frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: circle ? size / 2 : 8))
  }
}

/// YouTube's privacy-enhanced embedded player.
struct YouTubePlayer: NSViewRepresentable {
  let videoID: String
  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.mediaTypesRequiringUserActionForPlayback = []
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.setValue(false, forKey: "drawsBackground")
    return view
  }
  func updateNSView(_ view: WKWebView, context: Context) {
    guard context.coordinator.loaded != videoID else { return }
    context.coordinator.loaded = videoID
    let html = """
      <html><body style="margin:0;background:#000">
      <iframe width="100%" height="100%" style="border:0;position:absolute;inset:0"
        src="https://www.youtube-nocookie.com/embed/\(videoID)?rel=0&modestbranding=1&playsinline=1"
        allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe>
      </body></html>
      """
    // YouTube requires a referring origin for embeds.
    view.loadHTMLString(html, baseURL: URL(string: "https://uss-acc.local"))
  }
  func makeCoordinator() -> Coordinator { Coordinator() }
  final class Coordinator { var loaded: String? }
}

struct YouTubeKeyEditor: View {
  @EnvironmentObject private var psy: PsyartModel
  @Environment(\.dismiss) private var dismiss
  @State private var key = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("YOUTUBE DATA API KEY").font(.lcars(22)).foregroundStyle(Color.accPeach)
      Text("Optional. Lets PSYART resolve real videos and thumbnails. Stored in your Keychain.")
        .font(.acc(15)).foregroundStyle(Color.accDim)
      SecureField(psy.youtubeKeySaved ? "Saved — enter a new key to replace" : "API key", text: $key)
        .textFieldStyle(.roundedBorder)
      HStack {
        if psy.youtubeKeySaved {
          Button("Remove key") {
            psy.saveYouTubeKey("")
            dismiss()
          }.buttonStyle(.plain).foregroundStyle(Color.accPeach)
        }
        Spacer()
        ACCButton(title: "SAVE", primary: true) {
          psy.saveYouTubeKey(key)
          dismiss()
        }.disabled(key.isEmpty).fixedSize()
      }
    }.padding(20).frame(width: 380).background(Color.black)
  }
}

/// Tuner along the bottom of PSYART. Audio plays only on this station; otherwise the radio scans.
struct SDRStrip: View {
  @EnvironmentObject private var sdr: SDRController
  @State private var entry = ""
  /// Only channels the current antenna path can actually pass, strongest first.
  var receivable: [ChannelCandidate] {
    sdr.channels.filter { BandPlan.receptionProblem($0.frequency, hamItUp: sdr.hamItUp) == nil }
      .sorted { $0.snr > $1.snr }
  }
  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 12) {
        Button {
          sdr.online.toggle()
        } label: {
          Text(sdr.online ? "SDR ONLINE" : "SDR OFFLINE").font(.lcars(16)).foregroundStyle(.black)
            .padding(.horizontal, 14).frame(height: 38)
            .background(sdr.online ? Color.accGreen : Color.accDim, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).disabled(!sdr.available).fixedSize()
        VStack(alignment: .leading, spacing: 0) {
          Text(String(format: "%.4f", sdr.frequency / 1e6))
            .font(.system(size: 28, weight: .semibold, design: .monospaced)).foregroundStyle(Color.accPeach)
          Text("MHz · \(BandPlan.band(at: sdr.frequency)?.name ?? "unallocated")").font(.acc(13))
            .foregroundStyle(Color.accLavender).lineLimit(1)
        }.frame(width: 170, alignment: .leading)
        HStack(spacing: 4) {
          ForEach([(-1e6, "−1M"), (-1e5, "−100k"), (-1e4, "−10k"), (1e4, "+10k"), (1e5, "+100k"), (1e6, "+1M")], id: \.1) { step, label in
            Button(label) { sdr.step(step) }.buttonStyle(.plain).font(.lcars(15))
              .foregroundStyle(Color.accText).padding(.horizontal, 8).frame(height: 32)
              .background(Color.accField, in: RoundedRectangle(cornerRadius: 7)).fixedSize()
          }
        }
        TextField("Tune MHz", text: $entry).textFieldStyle(.plain).font(.acc(17)).frame(width: 90)
          .padding(.horizontal, 8).frame(height: 32)
          .background(Color.accField, in: RoundedRectangle(cornerRadius: 7))
          .onSubmit {
            if let mhz = Double(entry) { sdr.frequency = mhz * 1e6 }
            entry = ""
          }
        Spacer(minLength: 8)
        Toggle(isOn: $sdr.hamItUp) { Text("HAM IT UP").font(.lcars(15)) }
          .toggleStyle(ACCCheckboxStyle()).help("Upconverter in line: tune RF + 125 MHz (enables HF)")
          .fixedSize()
        Image(systemName: "speaker.wave.1").foregroundStyle(Color.accLavender)
        Slider(value: $sdr.volume, in: 0...1).frame(width: 90).tint(Color.accPeach)
        Button {
          sdr.audioOn.toggle()
        } label: {
          Label(sdr.audioOn ? "AUDIO ON" : "AUDIO OFF", systemImage: sdr.audioOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
            .font(.lcars(16)).foregroundStyle(.black).padding(.horizontal, 14).frame(height: 38)
            .background(sdr.audioOn ? Color.accPeach : Color.accLavender, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).disabled(!sdr.online).fixedSize()
      }
      HStack(spacing: 12) {
        ACCSegmented(
          options: SDRMode.allCases.filter(\.listenable).map { ($0.rawValue, $0) },
          selection: $sdr.mode, height: 36
        ).fixedSize()
        Button {
          sdr.optimize()
        } label: {
          VStack(spacing: 0) {
            Label(sdr.optimizing ? "TUNING…" : "OPTIMIZE", systemImage: "scope").font(.lcars(15))
            Text(String(format: "BW %.1f kHz", sdr.effectiveBandwidth / 1e3)).font(.acc(11))
          }.foregroundStyle(.black).padding(.horizontal, 10).frame(height: 38)
            .background(Color.accPeach, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).disabled(!sdr.online || sdr.optimizing).fixedSize()
          .help("Find the signal, then step centre and bandwidth to maximise SNR")
        SpectrumBars(values: sdr.spectrum).frame(width: 220, height: 40)
        VStack(alignment: .leading, spacing: 2) {
          Text(sdr.audioOn && sdr.online ? sdr.status : (sdr.scanning.isEmpty ? sdr.status : sdr.scanning))
            .font(.acc(14)).foregroundStyle(Color.accText).lineLimit(1)
          Text("\(receivable.count) channels found · tap to tune").font(.acc(13))
            .foregroundStyle(Color.accDim)
        }.frame(width: 230, alignment: .leading)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(receivable.prefix(60)) { channel in
              Button {
                sdr.tune(to: channel)
              } label: {
                VStack(alignment: .leading, spacing: 0) {
                  Text(String(format: "%.3f", channel.frequency / 1e6)).font(.system(size: 13, weight: .semibold, design: .monospaced))
                  Text("\(channel.mode.rawValue) · \(Int(channel.snr)) dB").font(.lcars(11))
                }.foregroundStyle(abs(channel.frequency - sdr.frequency) < 5e3 ? Color.black : Color.accText)
                  .padding(.horizontal, 8).padding(.vertical, 4)
                  .background(
                    abs(channel.frequency - sdr.frequency) < 5e3 ? Color.accPeach : Color.accField,
                    in: RoundedRectangle(cornerRadius: 7)
                  ).help("\(channel.band) · bandwidth \(Int(channel.bandwidth / 1e3)) kHz · seen \(channel.hits)×")
              }.buttonStyle(.plain)
            }
          }
        }
        Button("CLEAR") { sdr.clearChannels() }.buttonStyle(.plain).font(.lcars(13))
          .foregroundStyle(Color.accLavender)
      }
    }.padding(12)
      .background(Color.black, in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accBorder, lineWidth: 1.4))
  }
}

struct SpectrumBars: View {
  let values: [Float]
  var body: some View {
    Canvas { context, size in
      guard !values.isEmpty else { return }
      let low = values.min() ?? -100
      let high = max((values.max() ?? -60), low + 20)
      let width = size.width / CGFloat(values.count)
      for (index, value) in values.enumerated() {
        let height = CGFloat((value - low) / (high - low)) * size.height
        let rect = CGRect(x: CGFloat(index) * width, y: size.height - height, width: max(1, width - 0.5), height: height)
        context.fill(Path(rect), with: .color(value > high - 6 ? Color.accPeach : Color.accLavender))
      }
    }.background(Color.accGrid, in: RoundedRectangle(cornerRadius: 8))
  }
}

/// Live view of the centre/bandwidth hill-climb, one point per measurement step.
struct SNROptimizerPanel: View {
  @EnvironmentObject private var sdr: SDRController
  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("SNR OPTIMIZER").font(.lcars(22)).foregroundStyle(Color.accPeach)
        Text(sdr.optimizerSummary).font(.acc(15)).foregroundStyle(Color.accText).lineLimit(2)
        if let last = sdr.optimizerSteps.last {
          Text("Phase \(last.phase.rawValue) · step \(last.index + 1)").font(.acc(14))
            .foregroundStyle(Color.accLavender)
          Text(String(format: "Centre %+.0f Hz · BW %.1f kHz · %.1f dB", last.offset, last.bandwidth / 1e3, last.snr))
            .font(.system(size: 13, design: .monospaced)).foregroundStyle(Color.accText)
        }
        if let live = sdr.liveSNR.last, !sdr.optimizing {
          Text(String(format: "Live SNR %.1f dB", live)).font(.acc(14)).foregroundStyle(Color.accGreen)
        }
        Spacer(minLength: 0)
        if !sdr.optimizing {
          Button("CLOSE") { sdr.dismissOptimizer() }.buttonStyle(.plain).font(.lcars(14))
            .foregroundStyle(Color.accLavender)
        }
      }.frame(width: 300, alignment: .leading)
      Chart {
        ForEach(sdr.optimizerSteps) { step in
          LineMark(x: .value("Step", step.index), y: .value("SNR dB", step.snr))
            .foregroundStyle(by: .value("Phase", step.phase.rawValue))
            .interpolationMethod(.monotone)
          if step.accepted {
            PointMark(x: .value("Step", step.index), y: .value("SNR dB", step.snr))
              .foregroundStyle(by: .value("Phase", step.phase.rawValue)).symbolSize(28)
          }
        }
      }
      .chartForegroundStyleScale([
        "DETECT": Color.accGreen, "CENTRE": Color.accPeach, "BANDWIDTH": Color.accLavender,
        "DONE": Color.accDim,
      ])
      .chartYAxisLabel("SNR dB").chartXAxisLabel("Step")
      .chartYScale(domain: .automatic(includesZero: false))
      .frame(maxWidth: .infinity)
      if !sdr.liveSNR.isEmpty && !sdr.optimizing {
        VStack(alignment: .leading, spacing: 2) {
          Text("LIVE").font(.lcars(14)).foregroundStyle(Color.accGreen)
          Chart {
            ForEach(Array(sdr.liveSNR.enumerated()), id: \.offset) { index, value in
              AreaMark(x: .value("t", index), y: .value("SNR", value))
                .foregroundStyle(Color.accGreen.opacity(0.25))
              LineMark(x: .value("t", index), y: .value("SNR", value)).foregroundStyle(Color.accGreen)
            }
          }.chartXAxis(.hidden).chartYScale(domain: .automatic(includesZero: false))
        }.frame(width: 220)
      }
    }.padding(12).frame(height: 150)
      .background(Color.black, in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accBorder, lineWidth: 1.4))
  }
}
