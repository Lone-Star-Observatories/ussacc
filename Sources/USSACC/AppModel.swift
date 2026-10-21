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
  /// Progress of a retroactive filter run, shown in its sheet.
  @Published var retroProgress: (phase: String, done: Int, total: Int)?
  @Published var modelStatus = Intelligence.availability
  private let calendar = CalendarAdapter()
  private let mail = MailAdapter()
  private var mailTask: Task<Void, Never>?
  private var appleMailEnabled = false
  private var prefs = SessionPreferences()
  /// Local copy of downloaded mail; nil only if the database could not be opened.
  private var store: MessageStore?
  @Published var storedCount = 0
  @Published var archivedCount = 0
  /// Mail older than this stays indexed but its body moves to compressed archive packs.
  static let hotWindow: TimeInterval = 14 * 86400
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
    do {
      store = try MessageStore(url: folder.appendingPathComponent("messages.sqlite"))
    } catch { status = "Message store unavailable: \(error.localizedDescription)" }
    prefs =
      (try? LocalPersistence.load(
        SessionPreferences.self, from: folder.appendingPathComponent("preferences.json")))
      ?? SessionPreferences()
    loadDemo(persist: false)
  }
  /// Reopens the workspace the user last used, reconnecting only sources they had connected.
  func restoreSession() {
    if prefs.live { useLive() }
  }
  private func savePrefs() {
    try? LocalPersistence.save(prefs, to: folder.appendingPathComponent("preferences.json"))
  }
  func loadDemo(persist: Bool = true) {
    if persist {
      prefs.live = false
      savePrefs()
    }
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
  func useLive(restoreCalendar: Bool = true) {
    prefs.live = true
    savePrefs()
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
    communications = (try? store?.recent()) ?? []
    selectedIdentity = communications.first?.identity
    runArchival()
    appleMailEnabled = prefs.appleMail
    if appleMailEnabled || accounts.contains(where: \.enabled) {
      startPolling()
      Task { await refreshMail() }
    }
    if restoreCalendar && prefs.calendar { Task { await connectCalendar() } }
  }
  func connectCalendar() async {
    if demo { useLive(restoreCalendar: false) }
    let token = generation
    do {
      let result = try await calendar.fetch()
      guard token == generation, !demo else { return }
      events = result
      calendarStatus = "Calendar connected · \(events.count) events / 60 days"
      if !prefs.calendar {
        prefs.calendar = true
        savePrefs()
      }
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
    prefs.appleMail = true
    savePrefs()
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
    prefs.appleMail = false
    savePrefs()
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
    try? store?.delete(sourcePrefix: "imap:\(id):")
    try? store?.setSyncState(nil, account: id)
    store?.deleteArchive(key: id)
    storedCount = (try? store?.count()) ?? 0
    archivedCount = (try? store?.archivedCount()) ?? 0
    try? persistAccounts()
    status = "Account removed. Its password and stored mail were deleted."
  }
  /// Every Apple Mail account, marked when it can't be added. Nothing is saved here.
  func appleMailCandidates() async throws -> [AppleMailCandidate] {
    try AppleMailAccountImport.candidates(existing: accounts)
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
        let state = try? store?.syncState(account: account.id)
        let batch = try await IMAPMailSource.sync(account, password: password, state: state)
        guard token == generation, !demo else { return }
        try? store?.setSyncState(batch.state, account: account.id)
        batches.append((batch.source, batch.items))
        accountStatus[account.id] =
          "Checked \(Date.now.accClock()) · \(batch.items.count) new"
          + (state == nil || state?.uidValidity != batch.state.uidValidity ? " (initial sync)" : "")
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
      do { try store?.insert(fetched, source: source) } catch {
        status = "Couldn't save mail locally: \(error.localizedDescription)"
      }
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
    runArchival()
    let sources = batches.count
    status =
      sources == 0 && failures.isEmpty
      ? "No mail sources connected · add accounts in DEV → Settings → Connections"
      : "Mail checked \(Date.now.accClock()) · \(sources) source\(sources == 1 ? "" : "s")"
        + (failures.isEmpty ? "" : " · failed: \(failures.joined(separator: ", "))")
  }
  func classify(id: String, applyActions: Bool = false, token: Int? = nil) async {
    guard var item = communications.first(where: { $0.id == id }) else { return }
    if item.archived, let body = try? store?.body(id: id, restore: false) { item.body = body }
    let context = token ?? generation
    let savedPolicy = policy
    let result = await Intelligence.classify(
      item, known: policy.isKnown(item.address) || (item.isDemo && item.name == "Jamie"),
      policy: savedPolicy)
    guard context == generation, let index = communications.firstIndex(where: { $0.id == id })
    else { return }
    if applyActions && communications[index].classification?.source == "Manual override" { return }
    communications[index].classification = result
    if !item.isDemo {
      ledger.classifications[id] = result
      persistLedger()
      try? store?.updateState(id: id, classification: .some(result))
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
        try? store?.updateState(id: id, quarantined: true)
      case .delete:
        try await trash(id)
        try? store?.updateState(id: id, trashed: true)
        guard context == generation, let fresh = communications.firstIndex(where: { $0.id == id })
        else { return }
        communications[fresh].trashed = true
      }
      if decision.notify { notify(communications.first { $0.id == id } ?? item) }
    } catch { status = "Filter action failed; message retained: \(error.localizedDescription)" }
  }
  // MARK: Local store
  /// Rolls mail outside the hot window into archive packs and updates the loaded list.
  func runArchival() {
    guard !demo, let store else { return }
    let cutoff = Date.now.addingTimeInterval(-Self.hotWindow)
    var archived: Set<String> = []
    do {
      for _ in 0..<50 {
        let batch = try store.archive(olderThan: cutoff)
        if batch.isEmpty { break }
        archived.formUnion(batch)
      }
    } catch { status = "Archiving failed; mail kept in the database: \(error.localizedDescription)" }
    if !archived.isEmpty {
      for index in communications.indices where archived.contains(communications[index].id) {
        communications[index].archived = true
        communications[index].body = ""
      }
    }
    storedCount = (try? store.count()) ?? storedCount
    archivedCount = (try? store.archivedCount()) ?? archivedCount
  }
  /// Takes an archived body out of its pack and back into the database (hot for another window).
  func retrieve(_ id: String) {
    guard let store, let body = try? store.body(id: id, restore: true) else { return }
    if let index = communications.firstIndex(where: { $0.id == id }) {
      communications[index].body = body
      communications[index].archived = false
    } else if var item = try? store.message(id: id) {
      item.body = body
      item.archived = false
      communications.append(item)
    }
    archivedCount = (try? store.archivedCount()) ?? archivedCount
  }
  var archiveSize: Int64 { store?.archiveSize ?? 0 }
  /// Full-text search across all stored mail (live workspace only).
  func searchStored(_ text: String) -> [Communication]? {
    guard !demo, let store else { return nil }
    return try? store.search(text)
  }
  var storeSize: Int64 { store?.fileSize ?? 0 }
  /// Downloads up to 200 older messages per IMAP account. Backfill never triggers filter rules.
  func loadOlder() async {
    guard !demo, !refreshBusy, let store else { return }
    refreshBusy = true
    busy = true
    defer {
      refreshBusy = false
      busy = false
    }
    let token = generation
    var added = 0
    var failures: [String] = []
    for account in accounts where account.enabled {
      guard let password = password(for: account),
        let state = try? store.syncState(account: account.id), state.lowestUID > 1
      else { continue }
      do {
        let batch = try await IMAPMailSource.older(account, password: password, state: state)
        guard token == generation, !demo else { return }
        try store.insert(batch.items, source: batch.source)
        try store.setSyncState(batch.state, account: account.id)
        ledger.markSeen(batch.items.map(\.id))
        let existing = Set(communications.map(\.id))
        communications += batch.items.filter { !existing.contains($0.id) }.map { item in
          var item = item
          item.classification = ledger.classifications[item.id]
          item.quarantined = ledger.quarantinedIDs.contains(item.id)
          return item
        }
        added += batch.items.count
      } catch { failures.append("\(account.title): \(error.localizedDescription)") }
    }
    persistLedger()
    communications.sort { $0.date > $1.date }
    runArchival()
    status =
      added == 0 && failures.isEmpty
      ? "No older mail to load."
      : "Loaded \(added) older messages"
        + (failures.isEmpty ? "" : " · failed: \(failures.joined(separator: "; "))")
  }
  // MARK: Retroactive filtering
  /// Live messages a retroactive run would score; manual corrections are never re-scored.
  func retroactiveTargets(rescore: Bool) -> [Communication] {
    communications.filter {
      !$0.isDemo && !$0.trashed && $0.classification?.source != "Manual override"
        && (rescore || $0.classification?.level == nil)
    }
  }
  /// Step 1: scores loaded mail with the saved definitions. Changes no mail.
  func previewRetroactive(rescore: Bool) async -> RetroactivePlan? {
    guard !demo else { return nil }
    let token = generation
    let targets = retroactiveTargets(rescore: rescore)
    retroProgress = ("Classifying", 0, targets.count)
    defer { retroProgress = nil }
    for (index, item) in targets.enumerated() {
      guard token == generation, !demo else { return nil }
      await classify(id: item.id)
      retroProgress = ("Classifying", index + 1, targets.count)
    }
    return RetroactivePlan.make(communications, policy: policy)
  }
  /// Step 2: applies a previewed plan. Entries whose score changed since the preview are skipped.
  func applyRetroactive(_ plan: RetroactivePlan) async -> String {
    guard !demo else { return "Switch to the live workspace first." }
    let token = generation
    func current(_ entry: RetroactivePlan.Entry) -> Int? {
      guard let item = communications.first(where: { $0.id == entry.id }), !item.trashed,
        item.classification?.level == entry.level
      else { return nil }
      return communications.firstIndex { $0.id == entry.id }
    }
    let actions = plan.actions
    retroProgress = ("Applying", 0, actions.count)
    defer { retroProgress = nil }
    var quarantined = 0
    var trashed = 0
    var failures: [String] = []
    for entry in actions where entry.disposition == .quarantine {
      guard let index = current(entry) else { continue }
      communications[index].quarantined = true
      ledger.quarantinedIDs.insert(entry.id)
      try? store?.updateState(id: entry.id, quarantined: true)
      quarantined += 1
    }
    persistLedger()
    retroProgress = ("Applying", quarantined, actions.count)
    // OP5 can never be deleted, whatever a stored rule says.
    let deletes = actions.filter { $0.disposition == .delete && $0.level != 5 && current($0) != nil }
      .map(\.id)
    var groups: [String: [String]] = [:]
    for id in deletes {
      let key = id.hasPrefix("imap:") ? String(id.split(separator: ":")[1]) : IntakeLedger.appleMail
      groups[key, default: []].append(id)
    }
    for (key, ids) in groups {
      guard token == generation, !demo else { break }
      do {
        if key == IntakeLedger.appleMail {
          for id in ids { try await mail.trash(id: id) }
        } else {
          guard let account = accounts.first(where: { $0.id == key }),
            let password = password(for: account)
          else { throw IntegrationError.message("account is no longer configured") }
          try await IMAPMailSource.trash(account, password: password, ids: ids)
        }
        for id in ids {
          try? store?.updateState(id: id, trashed: true)
          if let index = communications.firstIndex(where: { $0.id == id }) {
            communications[index].trashed = true
          }
        }
        trashed += ids.count
      } catch {
        let name = accounts.first { $0.id == key }?.title ?? "Apple Mail"
        failures.append("\(name): \(error.localizedDescription)")
      }
      retroProgress = ("Applying", quarantined + trashed, actions.count)
    }
    let summary =
      "Applied rules to existing mail · \(quarantined) quarantined · \(trashed) moved to Trash"
      + (failures.isEmpty ? "" : " · kept after errors: \(failures.joined(separator: "; "))")
    status = summary
    return summary
  }
  func correctScore(_ id: String, level: Int) {
    guard let index = communications.firstIndex(where: { $0.id == id }) else { return }
    let result = Classification(
      level: level, reason: "Manual correction by Allen.", source: "Manual override")
    communications[index].classification = result
    if !communications[index].isDemo {
      ledger.classifications[id] = result
      persistLedger()
      try? store?.updateState(id: id, classification: .some(result))
    }
  }
  func restore(_ id: String) {
    if let i = communications.firstIndex(where: { $0.id == id }) {
      communications[i].quarantined = false
    }
    ledger.quarantinedIDs.remove(id)
    persistLedger()
    try? store?.updateState(id: id, quarantined: false)
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
