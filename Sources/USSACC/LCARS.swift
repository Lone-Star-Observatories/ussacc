import SwiftUI

// Palette sampled from the approved mockups in docs/design.
extension Color {
  static let accPeach = Color(red: 0.992, green: 0.686, blue: 0.388)  // #FDAF63
  static let accLavender = Color(red: 0.529, green: 0.620, blue: 0.988)  // #879EFC
  static let accText = Color(red: 0.90, green: 0.92, blue: 0.98)
  static let accDim = Color(red: 0.62, green: 0.66, blue: 0.80)
  static let accGreen = Color(red: 0.263, green: 0.953, blue: 0.588)  // #43F396
  static let accCard = Color(red: 0.118, green: 0.141, blue: 0.227)  // #1E243A
  static let accField = Color(red: 0.086, green: 0.102, blue: 0.176)  // #161A2D
  static let accGrid = Color(red: 0.043, green: 0.055, blue: 0.075)  // #0B0E13
  static let accLine = Color(red: 0.212, green: 0.294, blue: 0.420)  // #364B6B
  static let accBorder = Color.accLavender.opacity(0.55)
  /// Kept for older call sites: the card fill used for nested surfaces.
  static let accPanel = accCard
}
extension Font {
  /// LCARS display face: SF Pro Compressed, matching the mockups' tall condensed titling.
  static func lcars(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
    .system(size: size, weight: weight).width(.compressed)
  }
  /// Body copy: SF Pro Condensed, so running text keeps the same narrow rhythm as titles.
  static func acc(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight).width(.condensed)
  }
}

enum ACCButtonStyleKind { case primary, secondary, outline }

struct ACCButton: View {
  let title: String
  var symbol: String? = nil
  var kind: ACCButtonStyleKind = .secondary
  var size: CGFloat = 19
  var height: CGFloat = 46
  var action: () -> Void
  init(
    title: String, symbol: String? = nil, primary: Bool = false,
    kind: ACCButtonStyleKind? = nil, size: CGFloat = 19, height: CGFloat = 46,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.symbol = symbol
    self.kind = kind ?? (primary ? .primary : .secondary)
    self.size = size
    self.height = height
    self.action = action
  }
  @Environment(\.isEnabled) private var enabled
  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        if let symbol { Image(systemName: symbol).font(.system(size: size * 0.95, weight: .semibold)) }
        Text(title).font(.lcars(size)).lineLimit(1)
      }
      .foregroundStyle(kind == .outline ? Color.accText : .black)
      .padding(.horizontal, 20).frame(height: height)
      .background(fill, in: RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12).stroke(
          kind == .outline ? Color.accBorder : .clear, lineWidth: 1.2)
      )
      .opacity(enabled ? 1 : 0.45).contentShape(RoundedRectangle(cornerRadius: 12))
    }.buttonStyle(.plain).accessibilityLabel(title)
  }
  var fill: Color {
    switch kind {
    case .primary: .accPeach
    case .secondary: .accLavender
    case .outline: .accField
    }
  }
}

/// Small square icon button used for +, chevrons and close affordances.
struct ACCIconButton: View {
  let symbol: String
  var help: String = ""
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
        .foregroundStyle(Color.accText).frame(width: 44, height: 44)
        .background(Color.accField, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.accBorder, lineWidth: 1.2))
    }.buttonStyle(.plain).help(help).accessibilityLabel(help)
  }
}

struct ACCPanel<Content: View, Accessory: View>: View {
  var title: String? = nil
  var subtitle: String? = nil
  var padding: CGFloat = 22
  @ViewBuilder var accessory: Accessory
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if title != nil || subtitle != nil {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 2) {
            if let title { Text(title).font(.lcars(40)).foregroundStyle(Color.accPeach) }
            if let subtitle {
              Text(subtitle).font(.acc(21, weight: .medium)).foregroundStyle(Color.accLavender)
            }
          }
          Spacer(minLength: 12)
          accessory
        }
      }
      content
    }.padding(padding).frame(maxWidth: .infinity, alignment: .topLeading)
      .background(Color.black, in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accBorder, lineWidth: 1.4))
  }
}
extension ACCPanel where Accessory == EmptyView {
  init(
    title: String? = nil, subtitle: String? = nil, padding: CGFloat = 22,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.subtitle = subtitle
    self.padding = padding
    self.accessory = EmptyView()
    self.content = content()
  }
}

/// Capsule label for a channel or category ("MESSAGE", "EMAIL", "MISSED CALL").
struct ACCTag: View {
  let text: String
  var color: Color = .accLavender
  var body: some View {
    Text(text.uppercased()).font(.lcars(14)).foregroundStyle(.black).lineLimit(1)
      .padding(.horizontal, 12).padding(.vertical, 4).background(color, in: Capsule())
  }
}

/// Search / text field styled as an LCARS inset.
struct ACCField: View {
  let placeholder: String
  @Binding var text: String
  var symbol: String? = nil
  var onSubmit: () -> Void = {}
  var body: some View {
    HStack(spacing: 12) {
      if let symbol {
        Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(
          Color.accText)
      }
      TextField(placeholder, text: $text).textFieldStyle(.plain).font(.acc(18)).onSubmit(onSubmit)
    }.padding(.horizontal, 16).frame(height: 46)
      .background(Color.accField, in: RoundedRectangle(cornerRadius: 11))
      .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.accBorder, lineWidth: 1.2))
  }
}

/// Joined pill segments (DAY / WEEK / MONTH, LOCAL / SERVER).
struct ACCSegmented<Value: Hashable>: View {
  let options: [(String, Value)]
  @Binding var selection: Value
  var height: CGFloat = 44
  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(options.enumerated()), id: \.offset) { _, option in
        Button {
          selection = option.1
        } label: {
          Text(option.0).font(.lcars(18)).foregroundStyle(.black).padding(.horizontal, 22)
            .frame(height: height - 6)
            .background(
              selection == option.1 ? Color.accPeach : .clear, in: RoundedRectangle(cornerRadius: 9)
            ).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selection == option.1 ? .isSelected : [])
      }
    }.padding(3).background(Color.accLavender, in: RoundedRectangle(cornerRadius: 12))
  }
}

struct ACCDivider: View {
  var body: some View { Rectangle().fill(Color.accBorder.opacity(0.7)).frame(height: 1) }
}

/// Starfleet-style delta used for the BRIDGE station.
struct DeltaShape: Shape {
  func path(in r: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: r.midX, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
    p.addQuadCurve(
      to: CGPoint(x: r.minX, y: r.maxY), control: CGPoint(x: r.midX, y: r.minY + r.height * 0.45))
    p.closeSubpath()
    return p
  }
}
struct StationIcon: View {
  let station: Station
  var body: some View {
    switch station {
    case .bridge:
      ZStack {
        DeltaShape().fill(.black).frame(width: 26, height: 30)
        Image(systemName: "star.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(
          Color.accLavender
        ).offset(y: 3)
      }
    case .dev:
      Text(">_").font(.system(size: 26, weight: .bold, design: .monospaced))
    default:
      Image(systemName: station.symbol).font(.system(size: 27, weight: .semibold))
    }
  }
}

struct ControlCenter: View {
  @EnvironmentObject private var model: AppModel
  var body: some View {
    GeometryReader { geometry in
      let w = geometry.size.width
      let h = geometry.size.height
      let m: CGFloat = 12  // outer margin
      let rail: CGFloat = w < 1250 ? 200 : 233
      let topEnd = max(rail + 220, w - 640)  // where the top bands stop
      let sideTop: CGFloat = 138
      let bottomBand: CGFloat = 40
      let buttonGap: CGFloat = 8
      let buttonHeight = min(100, max(64, (h - sideTop - 250) / 5 - buttonGap))
      let sideBottom = sideTop + CGFloat(Station.allCases.count) * (buttonHeight + buttonGap)
      let contentX = m + rail + 10
      ZStack(alignment: .topLeading) {
        Color.black
        // Upper elbow: peach outer band, lavender inner band, black content cut-out.
        UnevenRoundedRectangle(topLeadingRadius: 95).fill(Color.accPeach)
          .frame(width: topEnd - m, height: sideTop - 8 - 10).offset(x: m, y: 10)
        UnevenRoundedRectangle(topLeadingRadius: 70).fill(Color.black)
          .frame(width: topEnd - m - 168, height: sideTop).offset(x: m + 168, y: 40)
        UnevenRoundedRectangle(topLeadingRadius: 66).fill(Color.accLavender)
          .frame(width: topEnd - m - 173, height: sideTop - 8 - 45).offset(x: m + 173, y: 45)
        UnevenRoundedRectangle(
          bottomTrailingRadius: 24, topTrailingRadius: 24
        ).fill(Color.accLavender).frame(width: 140, height: 68).offset(x: topEnd + 12, y: 10)
        // Lower elbow and bottom bar.
        UnevenRoundedRectangle(bottomLeadingRadius: 95).fill(Color.accPeach)
          .frame(width: rail + 10, height: h - 10 - sideBottom).offset(x: m, y: sideBottom)
        UnevenRoundedRectangle(bottomLeadingRadius: 62).fill(Color.black)
          .frame(width: w, height: h - 10 - bottomBand - sideBottom - 5 + 5)
          .offset(x: m + 113, y: sideBottom)
        UnevenRoundedRectangle(bottomLeadingRadius: 56).fill(Color.accLavender)
          .frame(width: rail - 118, height: h - 10 - bottomBand - 5 - sideBottom)
          .offset(x: m + 118, y: sideBottom)
        // Content field.
        UnevenRoundedRectangle(topLeadingRadius: 62, bottomLeadingRadius: 40).fill(Color.black)
          .frame(width: w - m - rail, height: h - 78 - bottomBand - 10 - 5)
          .offset(x: m + rail, y: 78)
        Capsule().fill(Color.accLavender)
          .frame(width: max(200, w * 0.676 - contentX - 8), height: bottomBand)
          .offset(x: contentX + 8, y: h - 10 - bottomBand)
        Text(model.status).font(.acc(14, weight: .medium)).foregroundStyle(.black)
          .lineLimit(1).truncationMode(.tail)
          .frame(width: max(160, w * 0.676 - contentX - 56), height: bottomBand, alignment: .leading)
          .offset(x: contentX + 30, y: h - 10 - bottomBand)
        UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20)
          .fill(Color.accLavender).frame(width: 26, height: bottomBand)
          .offset(x: w - 14 - 26, y: h - 10 - bottomBand)
        Text(model.demo ? "DEMO WORKSPACE  /  SAMPLE DATA" : "LIVE WORKSPACE  /  LOCAL DATA")
          .font(.lcars(16, weight: .medium)).foregroundStyle(Color.accLavender)
          .frame(width: w - 14 - 26 - 30, height: bottomBand, alignment: .trailing)
          .offset(y: h - 10 - bottomBand)
        // Station rail.
        VStack(spacing: buttonGap) {
          ForEach(Station.allCases) { station in
            Button {
              model.station = station
            } label: {
              HStack(spacing: 0) {
                StationIcon(station: station).frame(width: 82)
                Rectangle().fill(.black).frame(width: 1.5, height: buttonHeight * 0.62)
                Text(station.rawValue).font(.lcars(27)).padding(.leading, 16)
                Spacer(minLength: 0)
              }
              .foregroundStyle(.black).frame(width: rail, height: buttonHeight)
              .background(model.station == station ? Color.accPeach : Color.accLavender)
              .clipShape(
                UnevenRoundedRectangle(
                  topLeadingRadius: 6, bottomLeadingRadius: 6, bottomTrailingRadius: 26,
                  topTrailingRadius: 26)
              ).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(station.rawValue)
              .accessibilityAddTraits(model.station == station ? .isSelected : [])
          }
        }.offset(x: m, y: sideTop)
        // Masthead.
        header.frame(width: w - 14 - 12, alignment: .trailing).offset(y: 6)
        // Station title + workspace.
        VStack(alignment: .leading, spacing: 14) {
          if model.station != .dev && model.station != .nav {
            StationTitle(station: model.station)
          }
          Group {
            switch model.station {
            case .bridge: BridgeView()
            case .comms: CommsView()
            case .events: EventsView()
            case .nav: NavView()
            case .dev: DevView()
            }
          }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: w - contentX - 14, height: h - 100 - bottomBand - 10 - 22, alignment: .topLeading)
        .offset(x: contentX, y: model.station == .nav || model.station == .dev ? 100 : 104)
      }
    }.ignoresSafeArea().background(.black).foregroundStyle(Color.accText).tint(.accPeach)
      .frame(minWidth: 1100, minHeight: 790)
  }
  var header: some View {
    HStack(alignment: .top, spacing: 26) {
      VStack(alignment: .trailing, spacing: -6) {
        Text("USS ACC").font(.lcars(84, weight: .bold)).foregroundStyle(Color.accPeach)
        Text("ALLEN CONTROL CENTER").font(.lcars(27, weight: .medium)).foregroundStyle(
          Color.accLavender)
      }
      Capsule().fill(Color.accLavender.opacity(0.85)).frame(width: 20, height: 110).padding(.top, 4)
      TimelineView(.periodic(from: .now, by: 1)) { tick in
        VStack(alignment: .leading, spacing: 2) {
          Text(
            tick.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
              .uppercased()
          ).font(.acc(17, weight: .medium))
          Text(tick.date, format: .accClock)
            .font(.acc(38, weight: .medium)).monospacedDigit()
          Button {
            if model.demo { model.useLive() } else { model.loadDemo() }
          } label: {
            Text(
              "\(TimeZone.current.abbreviation() ?? "LOCAL") · \(model.demo ? "DEMO" : "LIVE") ▾"
            ).font(.acc(16, weight: .medium))
          }.buttonStyle(.plain).help("Switch between demo and live workspaces")
        }.foregroundStyle(Color.accText).frame(minWidth: 140, alignment: .leading)
      }.padding(.top, 10)
    }
  }
}
struct StationTitle: View {
  let station: Station
  var showSubtitle = true
  var body: some View {
    VStack(alignment: .leading, spacing: -4) {
      Text(station.rawValue).font(.lcars(66)).foregroundStyle(Color.accPeach)
      if showSubtitle {
        Text(station.subtitle).font(.acc(30, weight: .medium)).foregroundStyle(Color.accLavender)
      }
    }.padding(.leading, 23)
  }
}
struct EmptyStation: View {
  let symbol: String
  let title: String
  let detail: String
  var body: some View {
    VStack(spacing: 15) {
      Image(systemName: symbol).font(.system(size: 38)).foregroundStyle(Color.accLavender)
      Text(title).font(.lcars(30))
      Text(detail).font(.acc(17)).foregroundStyle(Color.accDim).multilineTextAlignment(.center)
        .frame(maxWidth: 480)
    }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

extension FormatStyle where Self == Date.VerbatimFormatStyle {
  /// 24-hour "18:30" clock used throughout the mockups.
  static var accClock: Date.VerbatimFormatStyle {
    Date.VerbatimFormatStyle(
      format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
      timeZone: .current, calendar: .current)
  }
}
extension Date {
  func accClock(in zone: TimeZone = .current) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    f.timeZone = zone
    return f.string(from: self)
  }
}
