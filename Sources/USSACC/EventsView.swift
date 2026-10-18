import ACCCore
import AppKit
import SwiftUI

struct EventsView: View {
  @EnvironmentObject private var model: AppModel
  @State private var weekOffset = 0
  @State private var reminders = [false, false]
  var firstDay: Date {
    Calendar.current.date(
      byAdding: .day, value: weekOffset * 7, to: Calendar.current.startOfDay(for: .now))!
  }
  var selected: CalendarEntry? { model.events.first { $0.id == model.selectedEventID } }
  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      ACCPanel {
        HStack {
          Button {
            weekOffset -= 1
          } label: {
            Image(systemName: "chevron.left")
          }
          Text(firstDay.formatted(date: .abbreviated, time: .omitted)).font(.lcars(17))
          Button {
            weekOffset += 1
          } label: {
            Image(systemName: "chevron.right")
          }
          Spacer()
          Button("TODAY") { weekOffset = 0 }.font(.lcars(12))
          ACCButton(title: "CONNECT / REFRESH", symbol: "calendar") {
            Task { await model.connectCalendar() }
          }
        }
        Text(model.calendarStatus).font(.caption).foregroundStyle(Color.accLavender)
        ScrollView(.vertical) {
          HStack(alignment: .top, spacing: 1) {
            ForEach(0..<7) { index in
              let date = Calendar.current.date(byAdding: .day, value: index, to: firstDay)!
              VStack(spacing: 12) {
                Text(date.formatted(.dateTime.weekday(.abbreviated).day())).font(.lcars(15))
                  .foregroundStyle(Color.accLavender).frame(maxWidth: .infinity).padding(
                    .vertical, 15
                  ).background(Color.accPanel)
                ForEach(
                  model.events.filter { Calendar.current.isDate($0.start, inSameDayAs: date) }
                ) { event in
                  Button {
                    model.selectedEventID = event.id
                  } label: {
                    VStack(alignment: .leading, spacing: 8) {
                      Text(
                        event.allDay
                          ? "ALL DAY" : event.start.formatted(date: .omitted, time: .shortened)
                      ).font(.lcars(11))
                      Text(event.title).font(.system(size: 12, weight: .semibold))
                        .multilineTextAlignment(.leading)
                    }.foregroundStyle(.black).padding(10).frame(
                      maxWidth: .infinity, alignment: .leading
                    ).background(
                      model.selectedEventID == event.id ? Color.accPeach : Color.accLavender,
                      in: RoundedRectangle(cornerRadius: 9))
                  }.buttonStyle(.plain)
                }
                Spacer(minLength: 320)
              }.frame(maxWidth: .infinity).background(Color.accPanel.opacity(0.4))
            }
          }
        }
      }
      ACCPanel {
        if let selected {
          Text(selected.title).font(.lcars(25)).foregroundStyle(Color.accText)
          Divider()
          Label(
            selected.start.formatted(date: .complete, time: .shortened), systemImage: "calendar"
          ).font(.callout)
          Text(
            "Until \(selected.end.formatted(date: .omitted, time: .shortened)) · \(selected.timeZoneID)"
          ).font(.caption).foregroundStyle(Color.accLavender)
          if !selected.location.isEmpty {
            Label(selected.location, systemImage: "mappin.and.ellipse").font(.callout)
          }
          Text(selected.calendar).font(.caption).foregroundStyle(.secondary)
          ScrollView {
            Text(selected.notes.isEmpty ? "No event notes." : selected.notes).font(.callout)
              .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
          }.frame(maxHeight: 180)
          ACCButton(title: "OPEN IN NAV", symbol: "location.fill") { model.station = .nav }
          ACCButton(title: "OPEN CALENDAR", symbol: "calendar") {
            NSWorkspace.shared.open(URL(string: "ical://")!)
          }
          Spacer()
          Text("Travel invitations can be imported in NAV. Dates and places require review.").font(
            .caption
          ).foregroundStyle(.secondary)
        } else {
          EmptyStation(
            symbol: "calendar", title: "SELECT AN EVENT",
            detail: "Connect your system calendars or browse the demo week.")
        }
      }.frame(width: 290)
    }
  }
}
