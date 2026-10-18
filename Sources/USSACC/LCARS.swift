import SwiftUI

extension Color {
  static let accPeach = Color(red: 1, green: 0.68, blue: 0.42)
  static let accLavender = Color(red: 0.61, green: 0.63, blue: 0.94)
  static let accText = Color(red: 0.84, green: 0.86, blue: 0.96)
  static let accBlue = Color(red: 0.54, green: 0.72, blue: 0.94)
  static let accPanel = Color(red: 0.055, green: 0.065, blue: 0.09)
}
extension Font {
  static func lcars(_ size: CGFloat) -> Font {
    .custom("HelveticaNeue-CondensedBold", size: size)
  }
}
struct ACCButton: View {
  let title: String
  var symbol: String? = nil
  var primary = false
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let symbol { Image(systemName: symbol) }
        Text(title).font(.lcars(13))
      }
      .foregroundStyle(.black).padding(.horizontal, 17).padding(.vertical, 12)
      .background(
        primary ? Color.accPeach : Color.accLavender, in: RoundedRectangle(cornerRadius: 15))
    }.buttonStyle(.plain).accessibilityLabel(title)
  }
}
struct ACCPanel<Content: View>: View {
  var title: String? = nil
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if let title { Text(title).font(.lcars(24)).foregroundStyle(Color.accPeach) }
      content
    }.padding(20).frame(maxWidth: .infinity, alignment: .topLeading)
      .background(Color.black, in: RoundedRectangle(cornerRadius: 19))
      .overlay(
        RoundedRectangle(cornerRadius: 19).stroke(Color.accLavender.opacity(0.6), lineWidth: 1))
  }
}
struct ControlCenter: View {
  @EnvironmentObject private var model: AppModel
  var body: some View {
    GeometryReader { geometry in
      let rail: CGFloat = geometry.size.width < 1250 ? 155 : 195
      ZStack(alignment: .topLeading) {
        Color.black
        RoundedRectangle(cornerRadius: 65).fill(Color.accPeach).frame(
          width: geometry.size.width * 0.69, height: 170
        ).offset(x: 12, y: 12)
        RoundedRectangle(cornerRadius: 55).fill(Color.accLavender).frame(
          width: geometry.size.width * 0.67, height: 135
        ).offset(x: 85, y: 52)
        Color.black.frame(width: geometry.size.width - rail - 40, height: 155).offset(
          x: rail + 18, y: 85)
        RoundedRectangle(cornerRadius: 60).fill(Color.accPeach).frame(width: rail + 45, height: 200)
          .offset(x: 12, y: geometry.size.height - 212)
        RoundedRectangle(cornerRadius: 48).fill(Color.accLavender).frame(
          width: rail - 15, height: 205
        ).offset(x: 70, y: geometry.size.height - 250)
        HStack(alignment: .top, spacing: 14) {
          VStack(spacing: 6) {
            Color.clear.frame(height: 120)
            ForEach(Station.allCases) { station in
              Button {
                model.station = station
              } label: {
                HStack(spacing: 15) {
                  Image(systemName: station.symbol).font(.system(size: 23))
                  Text(station.rawValue).font(.lcars(21))
                  Spacer(minLength: 0)
                }
                .foregroundStyle(.black).padding(.leading, 22).frame(maxWidth: .infinity).frame(
                  height: 88
                )
                .background(model.station == station ? Color.accPeach : Color.accLavender)
                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 27, topTrailingRadius: 27))
              }.buttonStyle(.plain).accessibilityAddTraits(
                model.station == station ? .isSelected : [])
            }
            Spacer()
          }.frame(width: rail)
          VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 2) {
                Text(model.station.rawValue).font(.lcars(47)).foregroundStyle(Color.accPeach)
                Text(model.station.subtitle).font(.system(size: 17, weight: .medium))
                  .foregroundStyle(Color.accLavender)
              }.padding(.top, 78)
              Spacer()
              HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .trailing, spacing: 0) {
                  Text("USS ACC").font(.lcars(51)).foregroundStyle(Color.accPeach)
                  Text("ALLEN CONTROL CENTER").font(.lcars(15)).foregroundStyle(Color.accLavender)
                }
                Capsule().fill(Color.accLavender).frame(width: 12, height: 76)
                VStack(alignment: .trailing, spacing: 8) {
                  TimelineView(.periodic(from: .now, by: 1)) { tick in
                    VStack(alignment: .trailing) {
                      Text(
                        tick.date.formatted(
                          .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                      ).font(.system(size: 11, design: .monospaced))
                      Text(tick.date.formatted(date: .omitted, time: .shortened)).font(.lcars(25))
                    }
                  }
                  Button(model.demo ? "DEMO ▾" : "LIVE ▾") {
                    if model.demo { model.useLive() } else { model.loadDemo() }
                  }.font(.lcars(12)).buttonStyle(.bordered)
                }.foregroundStyle(Color.accText)
              }
            }.frame(height: 154)
            Group {
              switch model.station {
              case .bridge: BridgeView()
              case .comms: CommsView()
              case .events: EventsView()
              case .nav: NavView()
              case .dev: DevView()
              }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: 12) {
              Capsule().fill(Color.accLavender).frame(width: 90, height: 18)
              Text(model.status).font(.system(size: 10, design: .monospaced)).foregroundStyle(
                Color.accText
              ).lineLimit(2).textSelection(.enabled)
              Spacer(minLength: 0)
              Text(model.demo ? "SAMPLE DATA" : "LOCAL WORKSPACE").font(.lcars(10)).foregroundStyle(
                Color.accLavender)
            }.frame(minHeight: 22)
          }.padding(.trailing, 16).padding(.bottom, 18)
        }
      }
    }.background(.black).foregroundStyle(Color.accText).tint(.accPeach).frame(
      minWidth: 1100, minHeight: 790)
  }
}
struct EmptyStation: View {
  let symbol: String
  let title: String
  let detail: String
  var body: some View {
    VStack(spacing: 15) {
      Image(systemName: symbol).font(.system(size: 38)).foregroundStyle(Color.accLavender)
      Text(title).font(.lcars(24))
      Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 480)
    }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
