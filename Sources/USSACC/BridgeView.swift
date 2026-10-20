import ACCCore
import SwiftUI

struct BridgeView: View {
  @EnvironmentObject private var model: AppModel
  var priorities: [Communication] {
    var seen: Set<String> = []
    return model.communications.filter {
      !$0.quarantined && !$0.trashed && ($0.classification?.level == 5 || $0.channel == .call)
    }.sorted { $0.date > $1.date }.filter { seen.insert($0.identity).inserted }
  }
  var upcoming: [CalendarEntry] { Array(model.events.filter { $0.end > .now }.prefix(2)) }
  var nextLeg: JourneyLeg? {
    model.journeys.filter { $0.arrival > .now }.sorted { $0.departure < $1.departure }.first
  }
  var body: some View {
    GeometryReader { geometry in
      let top = max(330, geometry.size.height * 0.58)
      VStack(spacing: 12) {
        HStack(alignment: .top, spacing: 12) {
          comms.frame(maxHeight: .infinity, alignment: .top)
          events.frame(maxHeight: .infinity, alignment: .top)
        }.frame(height: top)
        movements.frame(maxHeight: .infinity)
      }
    }
  }
  var comms: some View {
    ACCPanel(title: "PRIORITY COMMS", subtitle: "Pinned + time-sensitive.") {
      ACCButton(title: "VIEW COMMS", symbol: "message", primary: true) { model.station = .comms }
    } content: {
      if priorities.isEmpty {
        Text("No priority communications. Connect Mail and enable classification in DEV → Settings.")
          .font(.acc(18)).foregroundStyle(Color.accDim).padding(.vertical, 28)
      }
      VStack(spacing: 0) {
        ForEach(Array(priorities.prefix(3).enumerated()), id: \.element.id) { index, item in
          if index > 0 { ACCDivider() }
          Button {
            model.selectedIdentity = item.identity
            model.station = .comms
          } label: {
            HStack(spacing: 22) {
              Avatar(name: item.name, size: 70)
              VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.acc(24, weight: .medium))
                Text(item.preview).font(.acc(19)).foregroundStyle(Color.accDim).lineLimit(1)
              }
              Spacer(minLength: 8)
              ChannelTag(item: item)
              Text(item.date.accRelative).font(.acc(19)).frame(minWidth: 70, alignment: .trailing)
            }.foregroundStyle(Color.accText).padding(.vertical, 10).contentShape(Rectangle())
          }.buttonStyle(.plain)
        }
      }
      Spacer(minLength: 0)
    }
  }
  var events: some View {
    ACCPanel(title: "MAJOR EVENTS", subtitle: "Next up on the timeline.") {
      ACCButton(title: "VIEW EVENTS", symbol: "calendar") { model.station = .events }
    } content: {
      if upcoming.isEmpty {
        Text("No calendar connected.").font(.acc(18)).foregroundStyle(Color.accDim)
          .padding(.vertical, 28)
      }
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, event in
          Button {
            model.selectedEventID = event.id
            model.station = .events
          } label: {
            HStack(alignment: .top, spacing: 28) {
              VStack(spacing: 0) {
                Image(systemName: "calendar").font(.system(size: 22, weight: .semibold))
                  .foregroundStyle(.black).frame(width: 60, height: 60)
                  .background(Color.accLavender, in: Circle())
                if index < upcoming.count - 1 {
                  Rectangle().fill(Color.accLavender.opacity(0.7)).frame(width: 2, height: 72)
                }
              }
              VStack(alignment: .leading, spacing: 4) {
                Text(event.start.accDayName).font(.lcars(18)).foregroundStyle(Color.accLavender)
                Text(event.allDay ? "ALL DAY" : event.start.accClock()).font(.acc(26, weight: .medium))
              }.frame(width: 90, alignment: .leading).padding(.top, 2)
              VStack(alignment: .leading, spacing: 6) {
                Text(event.title).font(.acc(25, weight: .medium))
                let detail = event.summary.isEmpty ? event.location : event.summary
                if !detail.isEmpty {
                  Text(detail).font(.acc(19)).foregroundStyle(Color.accDim).lineLimit(2)
                }
              }.padding(.top, 26)
              Spacer(minLength: 0)
            }.foregroundStyle(Color.accText).contentShape(Rectangle())
          }.buttonStyle(.plain)
        }
      }.padding(.top, 12).padding(.leading, 6)
      Spacer(minLength: 0)
    }
  }
  var movements: some View {
    ACCPanel {
      if let next = nextLeg {
        HStack(alignment: .center, spacing: 24) {
          VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 2) {
              Text("MOVEMENTS").font(.lcars(40)).foregroundStyle(Color.accPeach)
              Text("Next destination and travel details.").font(.acc(21, weight: .medium))
                .foregroundStyle(Color.accLavender)
            }
            HStack(spacing: 20) {
              Image(systemName: next.mode.symbol).font(.system(size: 40, weight: .medium))
                .foregroundStyle(Color.accLavender).frame(width: 100, height: 100)
                .background(Color.accCard, in: Circle())
                .overlay(Circle().stroke(Color.accBorder, lineWidth: 2))
              VStack(alignment: .leading, spacing: 2) {
                Text("NEXT DESTINATION").font(.lcars(18)).foregroundStyle(Color.accLavender)
                Text(next.destination).font(.acc(34, weight: .medium)).lineLimit(1)
                Text("From \(next.origin) · \(next.mode.rawValue)").font(.acc(20))
                  .foregroundStyle(Color.accLavender)
              }
            }
          }.frame(minWidth: 300, alignment: .leading)
          RouteSchematic(origin: next.origin, destination: next.destination, symbol: next.mode.symbol)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          Rectangle().fill(Color.accBorder).frame(width: 1.5).padding(.vertical, 14)
          VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 30) {
              Stat(label: "TRAVEL TIME", value: duration(next))
              Rectangle().fill(Color.accBorder).frame(width: 1.5, height: 70)
              Stat(
                label: "ARRIVAL GOAL",
                value: next.arrival.accClock(in: TimeZone(identifier: next.arrivalTimeZoneID) ?? .current))
            }
            Text("Leave by \(next.departure.accClock(in: TimeZone(identifier: next.timeZoneID) ?? .current)) · \(next.departure.accDayName.capitalized)")
              .font(.acc(20)).foregroundStyle(Color.accLavender)
            Text(next.reviewed ? "Itinerary · status unverified" : "Review this leg in NAV")
              .font(.acc(15)).foregroundStyle(Color.accDim)
            ACCButton(title: "OPEN NAV", symbol: "location.fill", primary: true, height: 54) {
              model.station = .nav
            }.frame(maxWidth: .infinity, alignment: .trailing)
          }.frame(width: 300)
        }.frame(maxHeight: .infinity)
      } else {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("MOVEMENTS").font(.lcars(40)).foregroundStyle(Color.accPeach)
            Text("No upcoming journeys. Import travel invitations or add a leg in NAV.")
              .font(.acc(21, weight: .medium)).foregroundStyle(Color.accLavender)
          }
          Spacer()
          ACCButton(title: "OPEN NAV", symbol: "location.fill", primary: true) {
            model.station = .nav
          }
        }.frame(maxHeight: .infinity)
      }
    }
  }
  func duration(_ leg: JourneyLeg) -> String {
    let minutes = Int(leg.arrival.timeIntervalSince(leg.departure) / 60)
    return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
  }
}
private struct Stat: View {
  let label: String
  let value: String
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.lcars(18)).foregroundStyle(Color.accLavender)
      Text(value).font(.acc(36, weight: .medium)).monospacedDigit()
    }
  }
}
/// Abstract origin → destination schematic. It is not a map and makes no geographic claim.
struct RouteSchematic: View {
  let origin: String
  let destination: String
  let symbol: String
  var body: some View {
    GeometryReader { g in
      let a = CGPoint(x: g.size.width * 0.13, y: g.size.height * 0.62)
      let b = CGPoint(x: g.size.width * 0.84, y: g.size.height * 0.28)
      ZStack(alignment: .topLeading) {
        Path { p in
          let step: CGFloat = 34
          stride(from: 0, through: g.size.width, by: step).forEach {
            p.move(to: CGPoint(x: $0, y: 0))
            p.addLine(to: CGPoint(x: $0, y: g.size.height))
          }
          stride(from: 0, through: g.size.height, by: step).forEach {
            p.move(to: CGPoint(x: 0, y: $0))
            p.addLine(to: CGPoint(x: g.size.width, y: $0))
          }
        }.stroke(Color.accLine.opacity(0.35), lineWidth: 0.6)
        Path { p in
          p.move(to: a)
          p.addCurve(
            to: b, control1: CGPoint(x: a.x + (b.x - a.x) * 0.35, y: a.y + 40),
            control2: CGPoint(x: a.x + (b.x - a.x) * 0.6, y: b.y - 30))
        }.stroke(Color.accPeach, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        Circle().fill(Color.accPeach).frame(width: 16, height: 16).position(a)
        Text(origin).font(.acc(17, weight: .medium)).position(x: a.x + 8, y: a.y + 26)
        Image(systemName: "mappin").font(.system(size: 26, weight: .bold))
          .foregroundStyle(Color.accPeach).position(x: b.x, y: b.y - 14)
        Text(destination).font(.acc(17, weight: .medium)).fixedSize()
          .position(x: min(b.x, g.size.width - 60), y: b.y + 22)
      }
    }
    .background(Color.accGrid, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accBorder, lineWidth: 1.2))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .accessibilityLabel("Route from \(origin) to \(destination)")
  }
}
struct Avatar: View {
  let name: String
  var size: CGFloat = 56
  var body: some View {
    Text(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined())
      .font(.lcars(size * 0.4)).foregroundStyle(Color.accLavender)
      .frame(width: size, height: size)
      .background(Color.accCard, in: Circle())
      .overlay(Circle().stroke(Color.accLavender.opacity(0.75), lineWidth: 2))
      .accessibilityHidden(true)
  }
}
struct ChannelTag: View {
  let item: Communication
  var body: some View { ACCTag(text: item.channelLabel) }
}
struct OPBadge: View {
  let level: Int?
  var body: some View {
    Text(level.map { "OP\($0)" } ?? "UNSCORED").font(.lcars(level == nil ? 13 : 16))
      .foregroundStyle(level == nil ? Color.accText : .black)
      .padding(.horizontal, level == nil ? 9 : 14).padding(.vertical, 4)
      .background(
        level == 5 ? Color.accPeach : level == nil ? Color.accField : Color.accLavender,
        in: Capsule()
      ).overlay(Capsule().stroke(level == nil ? Color.accBorder : .clear))
  }
}
extension Communication {
  var preview: String { subject.isEmpty ? body : subject }
  var channelLabel: String {
    switch channel {
    case .email: "Email"
    case .message: "Message"
    case .call: body.localizedCaseInsensitiveContains("missed") ? "Missed call" : "Call"
    }
  }
  var channelSymbol: String {
    switch channel {
    case .email: "envelope"
    case .message: "message"
    case .call: "phone.fill"
    }
  }
}
extension Date {
  /// "TODAY", "TOMORROW", or "MON 19 OCT".
  var accDayName: String {
    let calendar = Calendar.current
    if calendar.isDateInToday(self) { return "TODAY" }
    if calendar.isDateInTomorrow(self) { return "TOMORROW" }
    return formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased()
  }
  /// "17:35" today, otherwise "Oct 16".
  var accRelative: String {
    Calendar.current.isDateInToday(self)
      ? accClock() : formatted(.dateTime.month(.abbreviated).day())
  }
}
