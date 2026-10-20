import ACCCore
import MapKit
import SwiftUI

struct NavView: View {
  @EnvironmentObject private var model: AppModel
  @State private var query = ""
  @State private var results: [MKMapItem] = []
  @State private var position: MapCameraPosition = .region(
    MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: 39, longitude: -99),
      span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 60)))
  @State private var searchStatus = "Search a location or import your calendar travel."
  @State private var searchBusy = false
  @State private var filter: Transport?
  @State private var editing: JourneyLeg?
  @State private var add = false
  @State private var day: Date?
  @State private var editMode = false
  var legs: [JourneyLeg] {
    model.journeys.filter { filter == nil || $0.mode == filter }.sorted {
      $0.departure < $1.departure
    }
  }
  /// Travel days that have at least one leg.
  var days: [Date] {
    Array(Set(model.journeys.map { Calendar.current.startOfDay(for: $0.departure) })).sorted()
  }
  var activeDay: Date? {
    day.flatMap { d in days.first { $0 == d } }
      ?? days.first { $0 >= Calendar.current.startOfDay(for: .now) } ?? days.last
  }
  var dayLegs: [JourneyLeg] {
    guard let activeDay else { return [] }
    return legs.filter { Calendar.current.isDate($0.departure, inSameDayAs: activeDay) }
  }
  var unreviewed: [JourneyLeg] { dayLegs.filter { !$0.reviewed } }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top) {
        StationTitle(station: .nav)
        Spacer(minLength: 20)
        tripControls.frame(width: 634).padding(.top, 34)
      }
      HStack(alignment: .top, spacing: 12) {
        mapPanel.frame(maxHeight: .infinity)
        timeline.frame(width: 572).frame(maxHeight: .infinity)
      }
    }.sheet(item: $editing) { leg in LegEditor(leg: leg) { model.saveLeg($0) } }.sheet(
      isPresented: $add
    ) {
      LegEditor(
        leg: JourneyLeg(
          mode: .road, origin: "", destination: "", departure: .now,
          arrival: .now.addingTimeInterval(3600))
      ) { model.saveLeg($0) }
    }
  }
  var tripControls: some View {
    VStack(spacing: 8) {
      HStack(spacing: 10) {
        Menu {
          ForEach(days, id: \.self) { d in
            let count = model.journeys.filter { Calendar.current.isDate($0.departure, inSameDayAs: d) }.count
            Button("\(d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(count) legs") {
              day = d
            }
          }
        } label: {
          HStack(spacing: 16) {
            Image(systemName: "calendar").font(.system(size: 19, weight: .medium))
            Text(tripLabel).font(.acc(21)).lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold))
          }.foregroundStyle(Color.accText).padding(.horizontal, 20).frame(height: 48)
            .background(Color.accField, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.accBorder, lineWidth: 1.2))
        }.menuStyle(.button).buttonStyle(.plain).disabled(days.isEmpty)
        ACCButton(title: "CALENDAR IMPORT", symbol: "calendar", kind: .outline, height: 48) {
          model.importJourneys()
        }.fixedSize()
      }
      Button {
        if let first = unreviewed.first { editing = first }
      } label: {
        HStack(spacing: 14) {
          Image(systemName: "doc.text").font(.system(size: 17))
          if unreviewed.isEmpty {
            Text(dayLegs.isEmpty ? "No legs for this day" : "Legs reviewed · bookings and flight status unverified")
              .font(.acc(19))
          } else {
            Text("\(unreviewed.count) leg\(unreviewed.count == 1 ? "" : "s") from calendar invites ·").font(.acc(19))
            Text("Review details  ›").font(.acc(19)).foregroundStyle(Color.accLavender)
          }
          Spacer()
        }.foregroundStyle(Color.accText).padding(.horizontal, 20).frame(height: 36)
          .background(Color.accField.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
          .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accBorder.opacity(0.7), lineWidth: 1))
      }.buttonStyle(.plain).disabled(unreviewed.isEmpty)
    }
  }
  var tripLabel: String {
    guard let activeDay else { return "No journeys" }
    let names = dayLegs.last.map { " · \($0.destination)" } ?? ""
    return activeDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased() + names
  }
  var mapPanel: some View {
    ACCPanel(padding: 12) {
      ZStack(alignment: .top) {
        Map(position: $position) {
          ForEach(Array(results.enumerated()), id: \.offset) { _, item in
            Marker(item.name ?? "Place", coordinate: item.placemark.coordinate).tint(Color.accPeach)
          }
        }.mapStyle(.hybrid(elevation: .flat)).mapControls {
          MapCompass()
          MapZoomStepper()
        }.clipShape(RoundedRectangle(cornerRadius: 12))
          .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accBorder, lineWidth: 1.2))
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 10) {
            ACCField(placeholder: "Destination or place", text: $query, symbol: "magnifyingglass", onSubmit: search)
            ACCButton(title: "SEARCH", kind: .primary, action: search).disabled(searchBusy)
          }
          Text(searchStatus).font(.acc(15)).foregroundStyle(Color.accText).padding(.horizontal, 10)
            .padding(.vertical, 4).background(.black.opacity(0.65), in: Capsule())
          if !results.isEmpty {
            VStack(spacing: 6) {
              ForEach(Array(results.prefix(4).enumerated()), id: \.offset) { _, item in
                HStack {
                  Text(item.name ?? "Place").font(.acc(17)).lineLimit(1)
                  Spacer()
                  Button("DIRECTIONS") {
                    item.openInMaps(launchOptions: [
                      MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                    ])
                  }.font(.lcars(15)).foregroundStyle(Color.accPeach).buttonStyle(.plain)
                }
              }
            }.padding(12).frame(maxWidth: 420)
              .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
          }
        }.padding(14)
      }
      HStack(spacing: 8) {
        filterButton("ALL", symbol: nil, active: filter == nil) { filter = nil }
        ForEach(Transport.allCases, id: \.self) { mode in
          filterButton(mode.rawValue.uppercased(), symbol: mode.symbol, active: filter == mode) {
            filter = mode
          }
        }
      }
    }
  }
  func filterButton(_ title: String, symbol: String?, active: Bool, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      HStack(spacing: 8) {
        if let symbol { Image(systemName: symbol).font(.system(size: 17, weight: .semibold)) }
        Text(title).font(.lcars(18))
      }.foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 50)
        .background(active ? Color.accPeach : Color.accLavender, in: RoundedRectangle(cornerRadius: 11))
        .contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityAddTraits(active ? .isSelected : [])
  }
  var timeline: some View {
    ACCPanel(padding: 18) {
      HStack(alignment: .firstTextBaseline) {
        Text(activeDay.map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased() } ?? "JOURNEY")
          .font(.lcars(34, weight: .medium))
        Spacer()
        Text("All times local").font(.acc(18))
        ACCIconButton(symbol: "plus", help: "Add travel leg") { add = true }.scaleEffect(0.85)
      }
      ACCDivider()
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(dayLegs.enumerated()), id: \.element.id) { index, leg in
            legRow(leg)
            if index < dayLegs.count - 1 {
              transfer(Int(dayLegs[index + 1].departure.timeIntervalSince(leg.arrival) / 60))
            }
          }
          if dayLegs.isEmpty {
            Text(
              model.journeys.isEmpty
                ? "No travel legs. Connect Calendar in Settings, then import, or add a leg manually."
                : "No \(filter?.rawValue.lowercased() ?? "") legs on this day."
            ).font(.acc(18)).foregroundStyle(Color.accDim).padding(.vertical, 20)
          }
        }
      }
      Text("Invites are itinerary sources, not verified tickets. Live flight status and bookings are not connected.")
        .font(.acc(14)).foregroundStyle(Color.accDim)
      HStack(spacing: 10) {
        if let first = unreviewed.first {
          ACCButton(title: "REVIEW JOURNEY", symbol: "play.fill", primary: true, size: 22, height: 56) {
            editing = first
          }.frame(maxWidth: .infinity)
        } else {
          ACCButton(title: "LOCATE DESTINATION", symbol: "location.fill", primary: true, size: 22, height: 56) {
            if let last = dayLegs.last {
              query = last.destination
              search()
            }
          }.disabled(dayLegs.isEmpty)
        }
        ACCButton(title: editMode ? "DONE" : "EDIT LEGS", symbol: editMode ? "checkmark" : "pencil", kind: .outline, size: 22, height: 56) {
          editMode.toggle()
        }
      }
    }
  }
  func legRow(_ leg: JourneyLeg) -> some View {
    let fromZone = TimeZone(identifier: leg.timeZoneID) ?? .current
    let toZone = TimeZone(identifier: leg.arrivalTimeZoneID) ?? .current
    let crossesZones = leg.timeZoneID != leg.arrivalTimeZoneID
    let minutes = Int(leg.arrival.timeIntervalSince(leg.departure) / 60)
    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 14) {
        Text(leg.departure.accClock(in: fromZone)).font(.acc(23, weight: .medium)).frame(width: 60, alignment: .leading)
        Circle().fill(leg.reviewed ? Color.accLavender : Color.accPeach).frame(width: 18, height: 18).padding(.top, 5)
        Image(systemName: leg.mode.symbol).font(.system(size: 22, weight: .semibold))
          .foregroundStyle(leg.reviewed ? Color.accLavender : Color.accPeach).frame(width: 46, height: 46)
          .overlay(RoundedRectangle(cornerRadius: 9).stroke(leg.reviewed ? Color.accLavender : Color.accPeach, lineWidth: 1.6))
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 10) {
            Text(leg.mode.rawValue).font(.acc(23, weight: .semibold))
            Text("\(leg.origin) → \(leg.destination)").font(.acc(21)).lineLimit(1)
          }
          Text(crossesZones
            ? "\(zoneLabel(fromZone, at: leg.departure)) → \(zoneLabel(toZone, at: leg.arrival))"
            : zoneLabel(fromZone, at: leg.departure)).font(.acc(17)).foregroundStyle(Color.accLavender)
          Text(leg.source).font(.acc(17)).foregroundStyle(Color.accLavender.opacity(0.85)).lineLimit(1)
        }
        Spacer(minLength: 4)
        VStack(alignment: .trailing, spacing: 6) {
          if !leg.reviewed { ACCTag(text: "Review") }
          VStack(alignment: .leading, spacing: 0) {
            Text(crossesZones ? "Arrives" : "Allow").font(.acc(16))
            Text(crossesZones
              ? "\(leg.arrival.accClock(in: toZone)) \(toZone.abbreviation(for: leg.arrival) ?? "")"
              : "\(minutes) min").font(.acc(16))
          }.padding(.leading, 12).overlay(alignment: .leading) {
            Rectangle().fill(Color.accBorder).frame(width: 1)
          }
        }
      }
      if editMode {
        HStack(spacing: 14) {
          Button("EDIT") { editing = leg }
          Button("LOCATE DESTINATION") {
            query = leg.destination
            search()
          }
          Spacer()
          Button("REMOVE") { model.removeLeg(leg.id) }.foregroundStyle(Color.accPeach)
        }.font(.lcars(16)).foregroundStyle(Color.accLavender).buttonStyle(.plain).padding(.leading, 152)
      }
    }.padding(.vertical, 6).contentShape(Rectangle()).onTapGesture(count: 2) { editing = leg }
  }
  func transfer(_ minutes: Int) -> some View {
    HStack(spacing: 14) {
      Color.clear.frame(width: 60, height: 1)
      Circle().fill(Color.accLavender).frame(width: 12, height: 12).padding(.horizontal, 3)
      Text(minutes >= 0 ? "\(minutes) min transfer" : "Overlaps previous leg by \(-minutes) min")
        .font(.acc(18)).foregroundStyle(minutes >= 0 ? Color.accText : Color.accPeach)
      Rectangle().fill(Color.accBorder.opacity(0.6)).frame(height: 1)
    }.padding(.vertical, 6)
  }
  func zoneLabel(_ zone: TimeZone, at date: Date) -> String {
    let city = zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
    return "\(city) (\(zone.abbreviation(for: date) ?? ""))"
  }
  func time(_ date: Date, zone: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d HH:mm z"
    formatter.timeZone = TimeZone(identifier: zone) ?? .current
    return formatter.string(from: date)
  }
  func search() {
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !searchBusy else {
      return
    }
    searchBusy = true
    Task {
      defer { searchBusy = false }
      do {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let response = try await MKLocalSearch(request: request).start()
        results = response.mapItems
        position = .region(response.boundingRegion)
        searchStatus = "\(results.count) places found. Directions open Apple Maps."
      } catch { searchStatus = error.localizedDescription }
    }
  }
}
struct LegEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State var leg: JourneyLeg
  let save: (JourneyLeg) -> Void
  var zonesValid: Bool {
    TimeZone(identifier: leg.timeZoneID) != nil
      && TimeZone(identifier: leg.arrivalTimeZoneID) != nil
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("TRAVEL LEG").font(.lcars(28)).foregroundStyle(Color.accPeach)
      Form {
        Picker("Transport", selection: $leg.mode) {
          ForEach(Transport.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        TextField("From", text: $leg.origin)
        TextField("To", text: $leg.destination)
        TextField("Departure time zone", text: $leg.timeZoneID)
        DatePicker("Departure", selection: $leg.departure).environment(
          \.timeZone, TimeZone(identifier: leg.timeZoneID) ?? .current)
        TextField("Arrival time zone", text: $leg.arrivalTimeZoneID)
        DatePicker("Arrival", selection: $leg.arrival).environment(
          \.timeZone, TimeZone(identifier: leg.arrivalTimeZoneID) ?? .current)
        TextField("Source / notes", text: $leg.source)
        Toggle("I have reviewed the itinerary details", isOn: $leg.reviewed)
      }.textFieldStyle(.roundedBorder)
      Text(
        "Use IANA time zones, e.g. America/Chicago or America/Los_Angeles. Editing does not book or verify transport."
      ).font(.caption).foregroundStyle(.secondary)
      HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        ACCButton(title: "SAVE LEG", primary: true) {
          save(leg)
          dismiss()
        }.disabled(
          !zonesValid || leg.arrival < leg.departure
            || leg.origin.trimmingCharacters(in: .whitespaces).isEmpty
            || leg.destination.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }.padding(28).frame(width: 590).background(Color.black).preferredColorScheme(.dark)
  }
}
