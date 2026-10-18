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
  var legs: [JourneyLeg] {
    model.journeys.filter { filter == nil || $0.mode == filter }.sorted {
      $0.departure < $1.departure
    }
  }
  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      ACCPanel {
        HStack {
          TextField("Destination or place", text: $query).textFieldStyle(.roundedBorder).onSubmit(
            search)
          Button("SEARCH", action: search).font(.lcars(13)).disabled(searchBusy)
        }
        Map(position: $position) {
          ForEach(Array(results.enumerated()), id: \.offset) { _, item in
            Marker(item.name ?? "Place", coordinate: item.placemark.coordinate).tint(Color.accPeach)
          }
        }.mapStyle(.standard(elevation: .flat)).mapControls {
          MapCompass()
          MapZoomStepper()
        }.clipShape(RoundedRectangle(cornerRadius: 16))
        Text(searchStatus).font(.caption).foregroundStyle(Color.accLavender)
        if !results.isEmpty {
          ScrollView {
            VStack(spacing: 10) {
              ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                HStack {
                  Text(item.name ?? "Place").font(.callout)
                  Spacer()
                  Button("DIRECTIONS") {
                    item.openInMaps(launchOptions: [
                      MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                    ])
                  }.font(.lcars(11))
                }
              }
            }
          }.frame(maxHeight: 100)
        }
        ScrollView(.horizontal, showsIndicators: false) {
          HStack {
            Button("ALL") { filter = nil }.buttonStyle(.bordered).tint(
              filter == nil ? .accPeach : .accLavender)
            ForEach(Transport.allCases, id: \.self) { mode in
              Button {
                filter = mode
              } label: {
                Label(mode.rawValue.uppercased(), systemImage: mode.symbol).font(.lcars(11))
              }.buttonStyle(.bordered).tint(filter == mode ? .accPeach : .accLavender)
            }
          }
        }
      }
      ACCPanel {
        HStack {
          Text("JOURNEY LEGS").font(.lcars(24)).foregroundStyle(Color.accPeach)
          Spacer()
          Button {
            add = true
          } label: {
            Image(systemName: "plus")
          }.help("Add travel leg")
        }
        ACCButton(title: "IMPORT CALENDAR TRAVEL", symbol: "calendar") { model.importJourneys() }
        Text("Air · taxi · train · boat · road · walk\nLocal time zone shown for each endpoint.")
          .font(.caption).foregroundStyle(Color.accLavender)
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(legs) { leg in
              VStack(alignment: .leading, spacing: 10) {
                HStack {
                  Image(systemName: leg.mode.symbol).font(.title2).foregroundStyle(Color.accPeach)
                  Text(leg.mode.rawValue.uppercased()).font(.lcars(15))
                  Spacer()
                  Button("EDIT") { editing = leg }.font(.lcars(11))
                }
                Text("\(leg.origin) → \(leg.destination)").font(.headline)
                Text(
                  "Departs \(time(leg.departure, zone: leg.timeZoneID))\nArrives \(time(leg.arrival, zone: leg.arrivalTimeZoneID))"
                ).font(.system(size: 12, design: .monospaced))
                Text(leg.source).font(.caption).foregroundStyle(Color.accLavender)
                if !leg.reviewed {
                  Label("Review details", systemImage: "exclamationmark.circle").font(.caption)
                    .foregroundStyle(Color.accPeach)
                }
                HStack {
                  Button("LOCATE DESTINATION") {
                    query = leg.destination
                    search()
                  }.font(.lcars(10))
                  Spacer()
                  Button("REMOVE", role: .destructive) { model.removeLeg(leg.id) }.font(.lcars(10))
                }
              }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(
                Color.accPanel, in: RoundedRectangle(cornerRadius: 13))
            }
          }
        }
        if legs.isEmpty {
          Text("No travel legs. Connect Calendar in Settings, then import, or add a leg manually.")
            .foregroundStyle(.secondary).font(.callout)
        }
        Text(
          "Invites are itinerary sources, not verified tickets. Live flight status and bookings are not connected."
        ).font(.caption2).foregroundStyle(.secondary)
      }.frame(width: 360)
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
