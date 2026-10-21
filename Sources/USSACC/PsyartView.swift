import ACCCore
import AppKit
import SwiftUI

struct PsyartView: View {
  @EnvironmentObject private var psy: PsyartModel
  @EnvironmentObject private var sdr: SDRController
  @State private var keyEditor = false
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      if let page = psy.page {
        ScrollView {
          VStack(spacing: 12) {
            coordinates(page)
            HStack(alignment: .top, spacing: 12) {
              psyche(page).frame(maxWidth: .infinity)
              audio(page).frame(width: 470)
            }
            videos(page)
          }
        }
      } else {
        ACCPanel {
          EmptyStation(
            symbol: "sparkles", title: "AWAITING COORDINATES",
            detail:
              "Draw five Earth cultures and five worlds, then let Apple Intelligence compose a cultural transmission."
          )
        }.frame(maxHeight: .infinity)
      }
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
      Button(psy.youtubeKeySaved ? "YouTube key ✓" : "Add YouTube key") { keyEditor = true }
        .buttonStyle(.plain).font(.lcars(16)).foregroundStyle(Color.accLavender)
        .popover(isPresented: $keyEditor) { YouTubeKeyEditor().environmentObject(psy) }
      ACCButton(
        title: psy.busy ? "COMPOSING…" : "NEW TRANSMISSION", symbol: "dice.fill", primary: true
      ) { Task { await psy.generate() } }.fixedSize().disabled(psy.busy)
    }
  }

  func coordinates(_ page: PsyartPage) -> some View {
    ACCPanel(padding: 12) {
      HStack(spacing: 8) {
        ForEach(page.countries) { country in
          tile(id: country.id, page: page, name: country.name) {
            Text(country.flag).font(.system(size: 46))
          }
        }
        ForEach(page.places) { place in
          tile(id: place.id, page: page, name: place.name) {
            if let image = page.info[place.id]?.image {
              AsyncImage(url: image) { $0.resizable().scaledToFill() } placeholder: { Color.accField }
                .frame(width: 54, height: 54).clipShape(Circle())
                .overlay(Circle().stroke(place.trek ? Color.accLavender : Color.accGreen, lineWidth: 1.5))
            } else {
              Image(systemName: symbol(place.kind)).font(.system(size: 30, weight: .medium))
                .foregroundStyle(place.trek ? Color.accLavender : Color.accGreen).frame(height: 54)
            }
          }
        }
      }
    }
  }
  /// Minimal coordinate tile; clicking opens the place's Wikipedia or Memory Alpha record.
  func tile<Mark: View>(id: String, page: PsyartPage, name: String, @ViewBuilder mark: () -> Mark)
    -> some View
  {
    let link = page.info[id]?.link
    return Button {
      if let link { NSWorkspace.shared.open(link) }
    } label: {
      VStack(spacing: 4) {
        mark().frame(height: 56)
        Text(name).font(.acc(13)).foregroundStyle(Color.accDim).lineLimit(1)
      }.frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(Color.accCard.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }.buttonStyle(.plain).help(link == nil ? name : "Open \(name) record").disabled(link == nil)
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

  func psyche(_ page: PsyartPage) -> some View {
    ACCPanel(title: page.title.uppercased(), subtitle: page.tagline, padding: 16) {
      Text("CULTURAL PSYCHE · generated on device by Apple Intelligence").font(.lcars(16))
        .foregroundStyle(Color.accLavender)
      Text(page.reading).font(.acc(20)).textSelection(.enabled)
      ACCDivider()
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
        ForEach(page.countries.map(\.id) + page.places.map(\.id), id: \.self) { id in
          placeCard(id: id, page: page)
        }
      }
    }
  }
  func placeCard(id: String, page: PsyartPage) -> some View {
    let country = page.countries.first { $0.id == id }
    let place = page.places.first { $0.id == id }
    let info = page.info[id]
    return HStack(alignment: .top, spacing: 12) {
      ZStack {
        Color.accField
        if let image = info?.image {
          AsyncImage(url: image) { $0.resizable().scaledToFill() } placeholder: { Color.accField }
        } else if let country {
          Text(country.flag).font(.system(size: 40))
        } else if let place {
          Image(systemName: symbol(place.kind)).font(.system(size: 30)).foregroundStyle(Color.accLavender)
        }
      }.frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 10))
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(country?.name ?? place?.name ?? "").font(.acc(19, weight: .medium)).lineLimit(1)
          if place?.trek == true { ACCTag(text: "Memory Alpha") }
        }
        Text(info?.summary ?? "No record found.").font(.acc(15)).foregroundStyle(Color.accDim)
          .lineLimit(4)
        if let link = info?.link {
          Link("OPEN RECORD", destination: link).font(.lcars(13)).foregroundStyle(Color.accPeach)
        }
      }
      Spacer(minLength: 0)
    }.padding(10).background(Color.black, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accBorder.opacity(0.7), lineWidth: 1))
  }

  func audio(_ page: PsyartPage) -> some View {
    ACCPanel(title: "AUDIO MANIFEST", subtitle: "Matched against Apple Music", padding: 16) {
      Text("ARTISTS").font(.lcars(18)).foregroundStyle(Color.accLavender)
      HStack(alignment: .top, spacing: 12) {
        ForEach(page.artists) { artist in
          VStack(spacing: 6) {
            artwork(artist.artwork, size: 104, circle: true)
            Text(artist.title).font(.acc(17, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
            if !artist.artist.isEmpty {
              Text(artist.artist).font(.acc(14)).foregroundStyle(Color.accDim)
            }
            if !artist.verified { ACCTag(text: "Unverified", color: .accPeach) }
          }.frame(maxWidth: .infinity).onTapGesture { if let link = artist.link { NSWorkspace.shared.open(link) } }
        }
      }
      ACCDivider()
      Text("SONGS").font(.lcars(18)).foregroundStyle(Color.accLavender)
      ForEach(page.songs) { song in
        HStack(spacing: 12) {
          artwork(song.artwork, size: 48)
          VStack(alignment: .leading, spacing: 1) {
            Text(song.title).font(.acc(18, weight: .medium)).lineLimit(1)
            Text(song.artist).font(.acc(15)).foregroundStyle(Color.accDim).lineLimit(1)
          }
          Spacer()
          if !song.verified { ACCTag(text: "Unverified", color: .accPeach) }
          if song.preview != nil {
            Button {
              psy.togglePreview(song.preview)
            } label: {
              Image(systemName: psy.playing == song.preview ? "stop.fill" : "play.fill")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                .frame(width: 34, height: 34).background(Color.accPeach, in: Circle())
            }.buttonStyle(.plain).help("Play 30-second preview")
          }
          if let link = song.link {
            Button {
              NSWorkspace.shared.open(link)
            } label: {
              Image(systemName: "arrow.up.right.square").font(.system(size: 18))
                .foregroundStyle(Color.accLavender)
            }.buttonStyle(.plain).help("Open in Apple Music")
          }
        }
      }
      ACCDivider()
      Text("ALBUMS").font(.lcars(18)).foregroundStyle(Color.accLavender)
      HStack(alignment: .top, spacing: 12) {
        ForEach(page.albums) { album in
          VStack(alignment: .leading, spacing: 4) {
            artwork(album.artwork, size: 200)
            Text(album.title).font(.acc(17, weight: .medium)).lineLimit(2)
            Text(album.artist).font(.acc(14)).foregroundStyle(Color.accDim)
            if !album.verified { ACCTag(text: "Unverified", color: .accPeach) }
          }.frame(maxWidth: .infinity, alignment: .leading)
            .onTapGesture { if let link = album.link { NSWorkspace.shared.open(link) } }
        }
      }
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
      .clipShape(RoundedRectangle(cornerRadius: circle ? size / 2 : 10))
      .overlay(
        RoundedRectangle(cornerRadius: circle ? size / 2 : 10).stroke(Color.accBorder, lineWidth: 1))
  }

  func videos(_ page: PsyartPage) -> some View {
    ACCPanel(
      title: "VISUAL TRANSMISSIONS",
      subtitle: psy.youtubeKeySaved ? "Resolved on YouTube" : "Opens YouTube searches · add a YouTube key for thumbnails",
      padding: 16
    ) {
      HStack(alignment: .top, spacing: 10) {
        ForEach(page.videos) { video in
          Button {
            NSWorkspace.shared.open(video.link)
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              ZStack {
                LinearGradient(
                  colors: [Color.accLavender.opacity(0.35), Color.accPeach.opacity(0.25)],
                  startPoint: .topLeading, endPoint: .bottomTrailing)
                if let thumb = video.thumbnail {
                  AsyncImage(url: thumb) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                }
                Image(systemName: "play.rectangle.fill").font(.system(size: 30)).foregroundStyle(.white)
                  .shadow(radius: 4)
              }.aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10))
              Text(video.videoTitle ?? video.title).font(.acc(16, weight: .medium)).lineLimit(2)
                .multilineTextAlignment(.leading)
              Text(video.channel ?? "Search: \(video.query)").font(.acc(13)).foregroundStyle(Color.accDim)
                .lineLimit(1)
            }.foregroundStyle(Color.accText).frame(maxWidth: .infinity, alignment: .leading)
          }.buttonStyle(.plain)
        }
      }
    }
  }
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
