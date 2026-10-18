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
  var body: some View {
    ScrollView {
      VStack(spacing: 15) {
        HStack(alignment: .top, spacing: 15) {
          ACCPanel(title: "PRIORITY COMMS") {
            HStack {
              Text("Direct conversations + calls").font(.caption).foregroundStyle(Color.accLavender)
              Spacer()
              Button("VIEW COMMS") { model.station = .comms }.font(.lcars(12))
            }
            if priorities.isEmpty {
              Text(
                "No priority communications. Connect Mail and enable classification in DEV → Settings."
              ).foregroundStyle(.secondary).padding(.vertical, 28)
            }
            ForEach(Array(priorities.prefix(3))) { item in
              Button {
                model.selectedIdentity = item.identity
                model.station = .comms
              } label: {
                HStack(spacing: 14) {
                  Avatar(name: item.name)
                  VStack(alignment: .leading, spacing: 6) {
                    Text(item.name).font(.headline)
                    Text(item.subject.isEmpty ? item.body : item.subject).font(.callout).lineLimit(
                      1)
                  }
                  Spacer()
                  OPBadge(level: item.classification?.level)
                  Image(systemName: item.channel == .call ? "phone" : "bubble.left")
                }.foregroundStyle(Color.accText).padding(.vertical, 7)
              }.buttonStyle(.plain)
              Divider().overlay(Color.accLavender.opacity(0.3))
            }
          }
          ACCPanel(title: "MAJOR EVENTS") {
            HStack {
              Text("Next on your timeline").font(.caption).foregroundStyle(Color.accLavender)
              Spacer()
              Button("VIEW EVENTS") { model.station = .events }.font(.lcars(12))
            }
            if model.events.isEmpty {
              Text("No calendar connected.").foregroundStyle(.secondary).padding(.vertical, 28)
            }
            ForEach(Array(model.events.filter { $0.end > .now }.prefix(3))) { event in
              Button {
                model.selectedEventID = event.id
                model.station = .events
              } label: {
                HStack(alignment: .top, spacing: 15) {
                  Image(systemName: "calendar").foregroundStyle(Color.accLavender)
                  VStack(alignment: .leading, spacing: 7) {
                    Text(event.start.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                      .foregroundStyle(Color.accPeach)
                    Text(event.title).font(.headline)
                    Text(event.location).font(.caption).foregroundStyle(.secondary)
                  }
                  Spacer()
                }.padding(.vertical, 9)
              }.buttonStyle(.plain)
            }
          }
        }
        ACCPanel(title: "MOVEMENTS") {
          if let next = model.journeys.filter({ $0.arrival > .now }).sorted(by: {
            $0.departure < $1.departure
          }).first {
            HStack(spacing: 25) {
              Image(systemName: next.mode.symbol).font(.system(size: 45)).foregroundStyle(
                Color.accLavender
              ).frame(width: 75)
              VStack(alignment: .leading, spacing: 10) {
                Text("NEXT LEG / \(next.mode.rawValue.uppercased())").font(.lcars(13))
                  .foregroundStyle(Color.accLavender)
                Text("\(next.origin) → \(next.destination)").font(.lcars(29))
                Text(next.source).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              VStack(alignment: .trailing, spacing: 14) {
                Text(next.departure.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                  .foregroundStyle(Color.accPeach)
                Text(next.reviewed ? "Itinerary · status unverified" : "Review this leg").font(
                  .caption)
                ACCButton(title: "OPEN NAV", symbol: "location.fill", primary: true) {
                  model.station = .nav
                }
              }
            }.padding(.vertical, 20)
          } else {
            Text("No upcoming journeys. Import travel invitations or add a leg in NAV.").padding(
              .vertical, 30
            ).foregroundStyle(.secondary)
            ACCButton(title: "OPEN NAV", symbol: "location.fill") { model.station = .nav }
          }
        }
      }
    }
  }
}
struct Avatar: View {
  let name: String
  var body: some View {
    Text(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()).font(
      .lcars(17)
    ).foregroundStyle(.black).frame(width: 42, height: 42).background(
      Color.accLavender, in: Circle()
    ).accessibilityHidden(true)
  }
}
struct OPBadge: View {
  let level: Int?
  var body: some View {
    Text(level.map { "OP\($0)" } ?? "UNSCORED").font(.lcars(11)).foregroundStyle(
      level == 5 ? Color.black : Color.accText
    ).padding(.horizontal, 9).padding(.vertical, 5).background(
      level == 5 ? Color.accPeach : Color.accPanel, in: Capsule()
    ).overlay(Capsule().stroke(Color.accLavender.opacity(0.5)))
  }
}
