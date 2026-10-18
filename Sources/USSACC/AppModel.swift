import ACCCore
import SwiftUI
import UserNotifications

enum Station: String, CaseIterable, Identifiable {
  case bridge = "BRIDGE"
  case comms = "COMMS"
  case events = "EVENTS"
  case nav = "NAV"
  case dev = "DEV"
  var id: Self { self }
  var symbol: String {
    switch self {
    case .bridge: "sparkle"
    case .comms: "bubble.left.and.bubble.right"
    case .events: "calendar"
    case .nav: "location.fill"
    case .dev: "terminal"
    }
  }
  var subtitle: String {
    switch self {
    case .bridge: "What matters now."
    case .comms: "Conversations across every channel."
    case .events: "Your time, in view."
    case .nav: "Every leg of the journey."
    case .dev: "Tools for building."
    }
  }
}

@MainActor final class AppModel: ObservableObject {
  @Published var station: Station = .bridge
  @Published var demo = true
  @Published var communications: [Communication] = []
  @Published var events: [CalendarEntry] = []
  @Published var journeys: [JourneyLeg] = []
  @Published var policy = FilterPolicy()
  @Published var status = "Demo workspace · no accounts connected"
  @Published var calendarStatus = "Calendar not connected"
  @Published var mailConnected = false
  @Published var busy = false
  @Published var selectedIdentity: String?
  @Published var selectedEventID: String?
  @Published var settings = false
  @Published var modelStatus = Intelligence.availability
  private let calendar = CalendarAdapter()
  private let mail = MailAdapter()
  private var mailTask: Task<Void, Never>?
  private var refreshBusy = false
  private var ledger = IntakeLedger()
  private var generation = 0
  private let folder: URL
  init() {
    folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("USSACC")
    if let data = try? LocalPersistence.load(
      FilterPolicy.self, from: folder.appendingPathComponent("policy.json"))
    {
      policy = data
    }
    if let saved = try? LocalPersistence.load(
      IntakeLedger.self, from: folder.appendingPathComponent("intake.json"))
    {
      ledger = saved
    }
    loadDemo()
  }
  func loadDemo() {
    generation += 1
    mailTask?.cancel()
    mailTask = nil
    mailConnected = false
    demo = true
    let now = Date()
    let day = Calendar.current.startOfDay(for: now)
    func date(_ hour: Int, _ minute: Int = 0) -> Date {
      Calendar.current.date(byAdding: .minute, value: hour * 60 + minute, to: day)!
    }
    communications = [
      Communication(
        id: "demo-jamie-email", name: "Jamie", address: "jamie@example.com", channel: .email,
        subject: "Tonight at the observatory", body: "Shall we meet at eight? Can you confirm?",
        date: date(14, 10),
        classification: .init(
          level: 5, reason: "Known person asking you directly.", source: "Sample data"),
        isDemo: true),
      Communication(
        id: "demo-jamie-call", name: "Jamie", address: "jamie@example.com", channel: .call,
        body: "Voice call · 4 minutes", date: date(15, 2), isDemo: true),
      Communication(
        id: "demo-jamie-message", name: "Jamie", address: "jamie@example.com", channel: .message,
        body: "I'll bring the new filter. See you at eight?", date: date(17, 35),
        classification: .init(
          level: 5, reason: "Direct personal message from a known contact.", source: "Sample data"),
        isDemo: true),
      Communication(
        id: "demo-team", name: "Observatory Team", address: "team@example.com", channel: .email,
        subject: "Weather window confirmed",
        body: "Clear skies expected tonight. Please check the equipment list.", date: date(16),
        classification: .init(level: 2, reason: "General team update.", source: "Sample data"),
        isDemo: true),
      Communication(
        id: "demo-morgan", name: "Morgan", address: "morgan@example.com", channel: .call,
        body: "Missed call", date: date(17, 10), isDemo: true),
      Communication(
        id: "demo-delivery", name: "Delivery update", address: "delivery@example.com",
        channel: .email, subject: "Parcel delayed",
        body: "Your parcel is running late. No action is needed.", date: date(12),
        classification: .init(
          level: 1, reason: "Routine informational notice.", source: "Sample data"), isDemo: true),
    ]
    events = [
      CalendarEntry(
        id: "demo-session", title: "Observatory session", start: date(20), end: date(22),
        location: "Observatory · Austin", notes: "Charge batteries. Pack new filter.",
        calendar: "Personal"),
      CalendarEntry(
        id: "demo-review", title: "Project review", start: date(9).addingTimeInterval(86400),
        end: date(10).addingTimeInterval(86400), calendar: "Work"),
    ]
    let tomorrow = day.addingTimeInterval(86400)
    journeys = [
      JourneyLeg(
        mode: .taxi, origin: "Home", destination: "AUS terminal",
        departure: tomorrow.addingTimeInterval(6.5 * 3600),
        arrival: tomorrow.addingTimeInterval(7 * 3600), source: "Suggested · not booked"),
      JourneyLeg(
        mode: .air, origin: "AUS", destination: "SEA",
        departure: tomorrow.addingTimeInterval(8 * 3600 + 600),
        arrival: tomorrow.addingTimeInterval(12.5 * 3600), arrivalTimeZoneID: "America/Los_Angeles",
        source: "Sample calendar invite · status unverified", reviewed: false),
      JourneyLeg(
        mode: .train, origin: "SEA airport", destination: "Downtown",
        departure: tomorrow.addingTimeInterval(13.2 * 3600),
        arrival: tomorrow.addingTimeInterval(14 * 3600), timeZoneID: "America/Los_Angeles",
        source: "Suggested · not booked"),
      JourneyLeg(
        mode: .boat, origin: "Waterfront", destination: "Island",
        departure: tomorrow.addingTimeInterval(14.5 * 3600),
        arrival: tomorrow.addingTimeInterval(15.25 * 3600), timeZoneID: "America/Los_Angeles",
        source: "Suggested · not booked"),
    ]
    selectedIdentity = "jamie@example.com"
    selectedEventID = events.first?.id
    status = "Demo workspace · fictional sample data"
    calendarStatus = "Sample calendar"
  }
  func useLive() {
    generation += 1
    mailTask?.cancel()
    mailTask = nil
    demo = false
    mailConnected = false
    communications = []
    events = []
    selectedIdentity = nil
    selectedEventID = nil
    journeys =
      (try? LocalPersistence.load(
        [JourneyLeg].self, from: folder.appendingPathComponent("journeys.json"))) ?? []
    status = "Live workspace · connect accounts in DEV → Settings"
    calendarStatus = "Calendar not connected"
  }
  func connectCalendar() async {
    if demo { useLive() }
    let token = generation
    do {
      let result = try await calendar.fetch()
      guard token == generation, !demo else { return }
      events = result
      calendarStatus = "Calendar connected · \(events.count) events / 60 days"
      selectedEventID = events.first?.id
    } catch { calendarStatus = error.localizedDescription }
  }
  func importJourneys() {
    journeys = JourneyImport.merge(
      existing: journeys, candidates: events.compactMap(JourneyImport.candidate))
    persistJourneys()
    status = "Calendar travel candidates imported. Review times, locations, and bookings."
  }
  func saveLeg(_ leg: JourneyLeg) {
    if let index = journeys.firstIndex(where: { $0.id == leg.id }) {
      journeys[index] = leg
    } else {
      journeys.append(leg)
    }
    journeys.sort { $0.departure < $1.departure }
    persistJourneys()
  }
  func removeLeg(_ id: String) {
    journeys.removeAll { $0.id == id }
    persistJourneys()
  }
  private func persistJourneys() {
    guard !demo else { return }
    do {
      try LocalPersistence.save(journeys, to: folder.appendingPathComponent("journeys.json"))
    } catch { status = "Unable to save journey: \(error.localizedDescription)" }
  }
  func savePolicy(_ value: FilterPolicy) {
    do {
      try LocalPersistence.save(value, to: folder.appendingPathComponent("policy.json"))
      policy = value
      status = "Filter rules saved. New arrivals use the saved rules."
      if value.rules.contains(where: \.push) {
        Task {
          do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [
              .alert, .sound, .badge,
            ])
          } catch {
            status = "Rules saved; notifications unavailable: \(error.localizedDescription)"
          }
        }
      }
    } catch { status = "Unable to save rules: \(error.localizedDescription)" }
  }
  func connectMail() async {
    if demo { useLive() }
    await refreshMail()
    guard !demo, mailConnected else { return }
    mailTask?.cancel()
    mailTask = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(60)) } catch { break }
        guard !Task.isCancelled else { break }
        await self?.refreshMail()
      }
    }
  }
  func disconnectMail() {
    generation += 1
    mailTask?.cancel()
    mailTask = nil
    mailConnected = false
    status = "Mail monitoring disconnected."
  }
  func refreshMail() async {
    guard !demo, !refreshBusy else { return }
    refreshBusy = true
    busy = true
    defer {
      refreshBusy = false
      busy = false
    }
    let token = generation
    do {
      let fetched = try await mail.fetch()
      guard token == generation, !demo, !Task.isCancelled else { return }
      mailConnected = true
      let existing = Set(communications.map(\.id))
      let arrivals = ledger.receive(fetched.map(\.id))
      persistLedger()
      communications += fetched.filter { !existing.contains($0.id) }.map { item in
        var item = item
        item.quarantined = ledger.quarantinedIDs.contains(item.id)
        item.classification = ledger.classifications[item.id]
        return item
      }
      for item in fetched where arrivals.contains(item.id) {
        guard token == generation, !demo, !Task.isCancelled else { return }
        // Apply only after a successful model classification using the current saved policy.
        if policy.enabled { await classify(id: item.id, applyActions: true, token: token) }
        guard token == generation else { return }
      }
      communications.sort { $0.date > $1.date }
      if selectedIdentity == nil { selectedIdentity = communications.first?.identity }
      status =
        "Mail connected · checked \(Date.now.formatted(date: .omitted, time: .shortened)) · latest 40 inbox items"
    } catch { status = error.localizedDescription }
  }
  func classify(id: String, applyActions: Bool = false, token: Int? = nil) async {
    guard let item = communications.first(where: { $0.id == id }) else { return }
    let context = token ?? generation
    let savedPolicy = policy
    let result = await Intelligence.classify(
      item, known: policy.isKnown(item.address) || (item.isDemo && item.name == "Jamie"))
    guard context == generation, let index = communications.firstIndex(where: { $0.id == id })
    else { return }
    if applyActions && communications[index].classification?.source == "Manual override" { return }
    communications[index].classification = result
    if !item.isDemo {
      ledger.classifications[id] = result
      persistLedger()
    }
    guard applyActions, !item.isDemo, !demo, savedPolicy == policy else { return }
    let decision = PolicyDecision.evaluate(communications[index], policy: policy)
    do {
      switch decision.disposition {
      case .keep: break
      case .quarantine:
        communications[index].quarantined = true
        ledger.quarantinedIDs.insert(id)
        persistLedger()
      case .delete:
        try await mail.trash(id: id)
        guard context == generation, let fresh = communications.firstIndex(where: { $0.id == id })
        else { return }
        communications[fresh].trashed = true
      }
      if decision.notify { notify(communications.first { $0.id == id } ?? item) }
    } catch { status = "Filter action failed; message retained: \(error.localizedDescription)" }
  }
  func correctScore(_ id: String, level: Int) {
    guard let index = communications.firstIndex(where: { $0.id == id }) else { return }
    let result = Classification(
      level: level, reason: "Manual correction by Allen.", source: "Manual override")
    communications[index].classification = result
    if !communications[index].isDemo {
      ledger.classifications[id] = result
      persistLedger()
    }
  }
  func restore(_ id: String) {
    if let i = communications.firstIndex(where: { $0.id == id }) {
      communications[i].quarantined = false
    }
    ledger.quarantinedIDs.remove(id)
    persistLedger()
  }
  private func persistLedger() {
    do { try LocalPersistence.save(ledger, to: folder.appendingPathComponent("intake.json")) } catch
    {
      status = "Unable to save intake state; automatic filter paused: \(error.localizedDescription)"
      policy.enabled = false
    }
  }
  private func notify(_ item: Communication) {
    let content = UNMutableNotificationContent()
    content.title = "USS ACC · OP\(item.classification?.level ?? 0)"
    content.body = "New communication from \(item.name)"
    content.sound = .default
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: item.id, content: content, trigger: nil)
    ) { _ in }
  }
}
