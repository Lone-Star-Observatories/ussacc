import ACCCore
import AppKit
import SwiftUI

struct EventsView: View {
  @EnvironmentObject private var model: AppModel
  @State private var weekOffset = 0
  @State private var span = 7
  @State private var checked: Set<String> = []
  private let startHour = 7
  private let endHour = 23
  var firstDay: Date {
    let today = Calendar.current.startOfDay(for: .now)
    return Calendar.current.date(byAdding: .day, value: weekOffset * span, to: today)!
  }
  var days: [Date] {
    (0..<span).map { Calendar.current.date(byAdding: .day, value: $0, to: firstDay)! }
  }
  var selected: CalendarEntry? { model.events.first { $0.id == model.selectedEventID } }
  var rangeLabel: String {
    let last = days.last ?? firstDay
    let day = Date.FormatStyle().day()
    let full = Date.FormatStyle().day().month(.abbreviated).year()
    return span == 1
      ? firstDay.formatted(full).uppercased()
      : "\(firstDay.formatted(day))–\(last.formatted(full))".uppercased()
  }
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ACCPanel(padding: 16) {
        toolbar
        Text(model.calendarStatus).font(.acc(15)).foregroundStyle(Color.accLavender)
        grid
      }.frame(maxHeight: .infinity)
      detail.frame(width: 390).frame(maxHeight: .infinity)
    }
  }
  var toolbar: some View {
    HStack(spacing: 14) {
      HStack(spacing: 0) {
        Button {
          weekOffset -= 1
        } label: {
          Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).help("Previous")
        Text(rangeLabel).font(.lcars(22, weight: .medium)).lineLimit(1).fixedSize()
        Button {
          weekOffset += 1
        } label: {
          Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).help("Next")
      }.font(.system(size: 16, weight: .semibold)).padding(.horizontal, 6)
        .background(Color.accField, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.accBorder, lineWidth: 1.2))
      ACCButton(title: "TODAY", kind: .outline) { weekOffset = 0 }.fixedSize()
      Rectangle().fill(Color.accBorder).frame(width: 1.5, height: 40)
      ACCSegmented(
        options: [("DAY", 1), ("3 DAY", 3), ("WEEK", 7)],
        selection: Binding(get: { span }, set: { span = $0; weekOffset = 0 })
      ).fixedSize()
      Spacer(minLength: 0)
      ACCButton(
        title: model.demo ? "CONNECT" : "REFRESH", symbol: "calendar.badge.plus",
        primary: true
      ) { Task { await model.connectCalendar() } }.fixedSize()
        .help("Read your system calendars (next 60 days)")
    }
  }
  var grid: some View {
    GeometryReader { g in
      let gutter: CGFloat = 68
      let header: CGFloat = 76
      let columnWidth = (g.size.width - gutter) / CGFloat(span)
      let hourHeight = max(28, (g.size.height - header) / CGFloat(endHour - startHour))
      ZStack(alignment: .topLeading) {
        Color.accGrid
        // Day columns and header.
        ForEach(Array(days.enumerated()), id: \.offset) { index, date in
          let isToday = Calendar.current.isDateInToday(date)
          VStack(spacing: 2) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(.lcars(19, weight: .medium))
            Text(date.formatted(.dateTime.day().month(.abbreviated)).uppercased()).font(.lcars(25, weight: .medium))
          }.foregroundStyle(Color.accText).frame(width: columnWidth, height: header)
            .background(isToday ? Color.accLavender.opacity(0.16) : Color(red: 0.06, green: 0.075, blue: 0.106))
            .offset(x: gutter + CGFloat(index) * columnWidth)
          if isToday {
            Color.accLavender.opacity(0.06).frame(width: columnWidth, height: g.size.height - header)
              .offset(x: gutter + CGFloat(index) * columnWidth, y: header)
          }
        }
        Path { p in
          for index in 0...span {
            let x = gutter + CGFloat(index) * columnWidth
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: g.size.height))
          }
          p.move(to: CGPoint(x: 0, y: header))
          p.addLine(to: CGPoint(x: g.size.width, y: header))
        }.stroke(Color.accLine, lineWidth: 1)
        Path { p in
          for hour in startHour...endHour {
            let y = header + CGFloat(hour - startHour) * hourHeight
            p.move(to: CGPoint(x: gutter, y: y))
            p.addLine(to: CGPoint(x: g.size.width, y: y))
          }
        }.stroke(Color.accLine.opacity(0.45), style: StrokeStyle(lineWidth: 0.7, dash: [3, 4]))
        ForEach(Array(stride(from: startHour + 1, to: endHour, by: 4)), id: \.self) { hour in
          Text(String(format: "%02d:00", hour)).font(.acc(18)).foregroundStyle(Color.accText)
            .frame(width: gutter, alignment: .center)
            .offset(y: header + CGFloat(hour - startHour) * hourHeight - 11)
        }
        // Events.
        ForEach(Array(days.enumerated()), id: \.offset) { index, date in
          ForEach(model.events.filter { Calendar.current.isDate($0.start, inSameDayAs: date) }) { event in
            let startComponents = Calendar.current.dateComponents([.hour, .minute], from: event.start)
            let startValue = event.allDay
              ? Double(startHour) : Double(startComponents.hour ?? 0) + Double(startComponents.minute ?? 0) / 60
            let length = event.allDay ? 1 : max(0.9, event.end.timeIntervalSince(event.start) / 3600)
            let y = header + CGFloat(max(0, startValue - Double(startHour))) * hourHeight
            let isSelected = model.selectedEventID == event.id
            Button {
              model.selectedEventID = event.id
            } label: {
              VStack(alignment: .leading, spacing: 1) {
                Text(event.allDay ? "ALL DAY" : event.start.accClock()).font(.acc(16, weight: .semibold))
                Text(event.title).font(.acc(16)).lineLimit(3).multilineTextAlignment(.leading)
              }.foregroundStyle(.black).padding(.horizontal, 11).padding(.vertical, 7)
                .frame(
                  width: columnWidth - 8,
                  height: min(max(64, CGFloat(length) * hourHeight - 4), g.size.height - y - 4),
                  alignment: .topLeading
                )
                .background(isSelected ? Color.accPeach : Color.accLavender, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                  RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accPeach.opacity(0.6) : .clear, lineWidth: 3)
                    .padding(-2))
            }.buttonStyle(.plain).offset(x: gutter + CGFloat(index) * columnWidth + 4, y: y + 2)
          }
        }
      }.clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accBorder, lineWidth: 1.2))
    }
  }
  var detail: some View {
    ACCPanel {
      ScrollView { detailContent }
    }
  }
  @ViewBuilder var detailContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let selected {
        Text(selected.title).font(.acc(34, weight: .medium)).lineLimit(2)
        ACCDivider()
        VStack(alignment: .leading, spacing: 12) {
          row("calendar", selected.start.formatted(.dateTime.weekday(.wide).month(.wide).day()))
          row(
            "clock",
            selected.allDay
              ? "All day"
              : "\(selected.start.accClock()) – \(selected.end.accClock())  ·  \(TimeZone(identifier: selected.timeZoneID)?.abbreviation() ?? selected.timeZoneID)")
          if !selected.location.isEmpty { row("mappin.and.ellipse", selected.location) }
          if !selected.summary.isEmpty {
            Text(selected.summary).font(.acc(17)).foregroundStyle(Color.accDim).textSelection(.enabled)
          }
        }
        if !selected.attendees.isEmpty {
          ACCDivider()
          Text("ATTENDEES").font(.lcars(20)).foregroundStyle(Color.accLavender)
          ForEach(selected.attendees, id: \.self) { name in
            HStack(spacing: 18) {
              Avatar(name: name, size: 46)
              Text(name).font(.acc(22, weight: .medium))
            }
          }
        }
        ACCDivider()
        if let leg = travel(for: selected) {
          row(leg.mode.symbol, "Leave at \(leg.departure.accClock())  ·  \(Int(leg.arrival.timeIntervalSince(leg.departure) / 60)) min \(leg.mode.rawValue.lowercased())")
        } else {
          row("car", "No travel leg planned").foregroundStyle(Color.accDim)
        }
        HStack(spacing: 10) {
          ACCButton(title: "OPEN IN NAV", symbol: "location.fill", size: 18) { model.station = .nav }
          if let contact = contact(for: selected) {
            ACCButton(title: "MESSAGE \(contact.name.uppercased())", symbol: "message", size: 18) {
              model.selectedIdentity = contact.identity
              model.station = .comms
            }
          } else {
            ACCButton(title: "CALENDAR", symbol: "calendar", size: 18) {
              NSWorkspace.shared.open(URL(string: "ical://")!)
            }
          }
        }
        if !selected.reminders.isEmpty {
          ACCDivider()
          Text("REMINDERS").font(.lcars(20)).foregroundStyle(Color.accLavender)
          ForEach(selected.reminders, id: \.self) { reminder in
            let key = selected.id + reminder
            Button {
              if checked.contains(key) { checked.remove(key) } else { checked.insert(key) }
            } label: {
              HStack(spacing: 16) {
                Image(systemName: checked.contains(key) ? "checkmark.square.fill" : "square")
                  .font(.system(size: 24)).foregroundStyle(
                    checked.contains(key) ? Color.accPeach : Color.accText)
                Text(reminder).font(.acc(20)).strikethrough(checked.contains(key))
              }
            }.buttonStyle(.plain)
          }
        }
      } else {
        EmptyStation(
          symbol: "calendar", title: "SELECT AN EVENT",
          detail: "Connect your system calendars or browse the demo week.")
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  func row(_ symbol: String, _ text: String) -> some View {
    HStack(spacing: 16) {
      Image(systemName: symbol).font(.system(size: 21, weight: .medium)).foregroundStyle(
        Color.accLavender
      ).frame(width: 28)
      Text(text).font(.acc(20))
    }
  }
  /// A journey leg that arrives within three hours before the event.
  func travel(for event: CalendarEntry) -> JourneyLeg? {
    model.journeys.filter {
      $0.arrival <= event.start && event.start.timeIntervalSince($0.arrival) < 3 * 3600
    }.max { $0.arrival < $1.arrival }
  }
  func contact(for event: CalendarEntry) -> Communication? {
    let names = Set(event.attendees.map { $0.lowercased() })
    return model.communications.first { names.contains($0.name.lowercased()) }
  }
}
