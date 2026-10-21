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
    case .comms: "message"
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
  /// Apple Mail automation is active (opt-in per session).
  @Published var mailConnected = false
  @Published var accounts: [MailAccount] = []
  /// Latest per-account result, keyed by account id ("applemail" for Apple Mail).
  @Published var accountStatus: [String: String] = [:]
  @Published var busy = false
  @Published var selectedIdentity: String?
  @Published var selectedEventID: String?
  @Published var settings = false
  @Published var settingsSection = "Spam Filter"
  @Published var modelStatus = Intelligence.availability
  private let calendar = CalendarAdapter()
  private let mail = MailAdapter()
  private var mailTask: Task<Void, Never>?
  private var appleMailEnabled = false
  /// Keychain reads are cached for the session to avoid repeated access prompts.
  private var passwords: [String: String] = [:]
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
    accounts =
      (try? LocalPersistence.load(
        [MailAccount].self, from: folder.appendingPathComponent("accounts.json"))) ?? []
    loadDemo()
  }
  func loadDemo() {
    generation += 1
    mailTask?.cancel()
    mailTask = nil
    mailConnected = false
    appleMailEnabled = false
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
        id: "demo-alex", name: "Alex", address: "alex@example.com", channel: .message,
        body: "Sounds good, see you there.", date: date(9, 18), isDemo: true),
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
        location: "Observatory · Austin",
        notes: "Telescope operations and data collection.\n- Charge batteries\n- Pack new filter",
        calendar: "Personal", attendees: ["Jamie", "Allen"]),
      CalendarEntry(
        id: "demo-review", title: "Project review", start: date(9).addingTimeInterval(86400),
        end: date(10).addingTimeInterval(86400), notes: "Status, findings, and next steps.",
        calendar: "Work"),
      CalendarEntry(
        id: "demo-planning", title: "Planning", start: date(10).addingTimeInterval(2 * 86400),
        end: date(11).addingTimeInterval(2 * 86400), calendar: "Work"),
      CalendarEntry(
        id: "demo-pickup", title: "Equipment pickup", start: date(14).addingTimeInterval(4 * 86400),
        end: date(15).addingTimeInterval(4 * 86400), location: "Austin", calendar: "Personal"),
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
    appleMailEnabled = false
    if accounts.contains(where: \.enabled) {
      startPolling()
      Task { await refreshMail() }
    }
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
  /// Turns on Apple Mail automation and starts polling every connected source.
  func connectMail() async {
    if demo { useLive() }
    appleMailEnabled = true
    await refreshMail()
    guard !demo else { return }
    startPolling()
  }
  private func startPolling() {
    guard mailTask == nil else { return }
    mailTask = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(60)) } catch { break }
        guard !Task.isCancelled else { break }
        await self?.refreshMail()
      }
    }
  }
  func disconnectMail() {
    appleMailEnabled = false
    mailConnected = false
    accountStatus[IntakeLedger.appleMail] = nil
    if !accounts.contains(where: \.enabled) {
      generation += 1
      mailTask?.cancel()
      mailTask = nil
    }
    status = "Apple Mail monitoring disconnected."
  }
  // MARK: Accounts
  func password(for account: MailAccount) -> String? {
    if let cached = passwords[account.id] { return cached }
    let value = MailKeychain.password(for: account.id)
    passwords[account.id] = value
    return value
  }
  func hasPassword(_ account: MailAccount) -> Bool { password(for: account) != nil }
  func testAccount(_ account: MailAccount, password: String) async -> String {
    if let problem = account.validationError { return problem }
    do { return try await IMAPMailSource.test(account, password: password) } catch {
      return error.localizedDescription
    }
  }
  /// Saves settings to accounts.json and the password (when given) to the Keychain.
  func saveAccount(_ account: MailAccount, password: String?) {
    do {
      if let password, !password.isEmpty {
        try MailKeychain.save(password, for: account.id)
        passwords[account.id] = password
      }
      if let index = accounts.firstIndex(where: { $0.id == account.id }) {
        accounts[index] = account
      } else {
        accounts.append(account)
      }
      try persistAccounts()
      status = "\(account.title) saved."
      if demo { useLive() } else if account.enabled {
        startPolling()
        Task { await refreshMail() }
      }
    } catch { status = "Unable to save account: \(error.localizedDescription)" }
  }
  func removeAccount(_ id: String) {
    MailKeychain.delete(for: id)
    passwords[id] = nil
    accounts.removeAll { $0.id == id }
    accountStatus[id] = nil
    communications.removeAll { $0.id.hasPrefix("imap:\(id):") }
    try? persistAccounts()
    status = "Account removed. Its password was deleted from the Keychain."
  }
  /// Apple Mail accounts not already configured here. Nothing is saved until the user adds them.
  func appleMailAccounts() async throws -> [MailAccount] {
    let known = Set(accounts.map { $0.email.lowercased() })
    return try AppleMailAccountImport.accounts().filter { !known.contains($0.email.lowercased()) }
  }
  private func persistAccounts() throws {
    try LocalPersistence.save(accounts, to: folder.appendingPathComponent("accounts.json"))
  }
  private func trash(_ id: String) async throws {
    if id.hasPrefix("imap:") {
      let accountID = id.split(separator: ":").dropFirst().first.map(String.init)
      guard let account = accounts.first(where: { $0.id == accountID }),
        let password = password(for: account)
      else { throw IntegrationError.message("Account for this message is no longer configured.") }
      try await IMAPMailSource.trash(account, password: password, id: id)
    } else {
      try await mail.trash(id: id)
    }
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
    var batches: [(source: String, items: [Communication])] = []
    var failures: [String] = []
    if appleMailEnabled {
      do {
        let items = try await mail.fetch()
        batches.append((IntakeLedger.appleMail, items))
        mailConnected = true
        accountStatus[IntakeLedger.appleMail] = "Checked \(Date.now.accClock()) · \(items.count) recent"
      } catch {
        accountStatus[IntakeLedger.appleMail] = error.localizedDescription
        failures.append("Apple Mail")
      }
    }
    for account in accounts where account.enabled {
      guard let password = password(for: account) else {
        accountStatus[account.id] = "Needs password"
        continue
      }
      do {
        let batch = try await IMAPMailSource.fetch(account, password: password)
        batches.append(batch)
        accountStatus[account.id] = "Checked \(Date.now.accClock()) · \(batch.items.count) recent"
      } catch {
        accountStatus[account.id] = error.localizedDescription
        failures.append(account.title)
      }
      guard token == generation, !demo, !Task.isCancelled else { return }
    }
    guard token == generation, !demo, !Task.isCancelled else { return }
    for (source, fetched) in batches {
      let existing = Set(communications.map(\.id))
      let arrivals = ledger.receive(fetched.map(\.id), source: source)
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
    }
    communications.sort { $0.date > $1.date }
    if selectedIdentity == nil { selectedIdentity = communications.first?.identity }
    let sources = batches.count
    status =
      sources == 0 && failures.isEmpty
      ? "No mail sources connected · add accounts in DEV → Settings → Connections"
      : "Mail checked \(Date.now.accClock()) · \(sources) source\(sources == 1 ? "" : "s")"
        + (failures.isEmpty ? "" : " · failed: \(failures.joined(separator: ", "))")
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
        try await trash(id)
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
