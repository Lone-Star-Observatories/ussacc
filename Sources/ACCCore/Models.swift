import Foundation

public enum Channel: String, Codable, CaseIterable, Sendable { case email, message, call }
public enum Disposition: String, Codable, CaseIterable, Sendable {
  case keep = "Keep"
  case quarantine = "Quarantine"
  case delete = "Delete"
}
public struct LevelRule: Codable, Equatable, Sendable {
  public var level: Int
  /// Allen's definition of this level. It is given to the classifier; blank means unused.
  public var meaning: String
  public var disposition: Disposition
  public var highlight: Bool
  public var push: Bool
  public init(
    level: Int, meaning: String? = nil, disposition: Disposition = .keep, highlight: Bool = false,
    push: Bool = false
  ) {
    self.level = level
    self.meaning = meaning ?? Self.defaultMeaning(level)
    self.disposition = disposition
    self.highlight = highlight
    self.push = push
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    level = try c.decode(Int.self, forKey: .level)
    meaning = try c.decodeIfPresent(String.self, forKey: .meaning) ?? Self.defaultMeaning(level)
    disposition = try c.decodeIfPresent(Disposition.self, forKey: .disposition) ?? .keep
    highlight = try c.decodeIfPresent(Bool.self, forKey: .highlight) ?? false
    push = try c.decodeIfPresent(Bool.self, forKey: .push) ?? false
  }
  public static func defaultMeaning(_ level: Int) -> String {
    switch level {
    case 5: "Direct question or email of personal nature"
    case 4: "Unique notice or invitation from business that has urgency"
    case 3: "General unique but regular items, like receipts"
    case 2: "Eblasts, newsletters, regular emails"
    case 1: "Unactionable garbage"
    default: ""
    }
  }
}
public struct FilterPolicy: Codable, Equatable, Sendable {
  public var enabled = false
  public var knownAddresses: [String] = []
  public var rules: [LevelRule] = (1...5).map { LevelRule(level: $0, highlight: $0 == 5) }
  public init() {}
  public func rule(for level: Int?) -> LevelRule {
    guard let level, (1...5).contains(level) else { return LevelRule(level: 0) }
    var rule = rules.first { $0.level == level } ?? LevelRule(level: level)
    if level == 5 { rule.disposition = .keep }
    return rule
  }
  public func meaning(for level: Int) -> String {
    (rules.first { $0.level == level }?.meaning ?? LevelRule.defaultMeaning(level))
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
  /// Levels with a definition. Undefined levels are never assigned automatically.
  public var definedLevels: Set<Int> { Set((1...5).filter { !meaning(for: $0).isEmpty }) }
  public func isKnown(_ address: String) -> Bool {
    let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return !normalized.isEmpty
      && knownAddresses.contains {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
      }
  }
}
public struct Classification: Codable, Equatable, Sendable {
  public var level: Int?
  public var reason: String
  public var source: String
  public var date: Date
  public init(level: Int?, reason: String, source: String, date: Date = .now) {
    self.level = level
    self.reason = reason
    self.source = source
    self.date = date
  }
  public static func validated(
    level: Int, reason: String, isKnown: Bool, allowed: Set<Int> = [1, 2, 3, 4, 5]
  ) -> Classification {
    guard allowed.contains(level), level != 5 || isKnown else {
      return .init(
        level: nil, reason: "The model returned an unsupported classification. Review manually.",
        source: "Apple Intelligence")
    }
    return .init(level: level, reason: String(reason.prefix(400)), source: "Apple Intelligence")
  }
}
public struct Communication: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var address: String
  public var channel: Channel
  public var subject: String
  public var body: String
  public var date: Date
  public var classification: Classification?
  public var isDemo: Bool
  public var quarantined = false
  public var trashed = false
  public init(
    id: String = UUID().uuidString, name: String, address: String, channel: Channel,
    subject: String = "", body: String, date: Date = .now, classification: Classification? = nil,
    isDemo: Bool = false
  ) {
    self.id = id
    self.name = name
    self.address = address
    self.channel = channel
    self.subject = subject
    self.body = body
    self.date = date
    self.classification = classification
    self.isDemo = isDemo
  }
  public var identity: String { address.lowercased() }
}
public struct PolicyDecision: Equatable, Sendable {
  public var disposition: Disposition
  public var highlight: Bool
  public var notify: Bool
  public static func evaluate(_ item: Communication, policy: FilterPolicy) -> PolicyDecision {
    guard policy.enabled, let score = item.classification?.level, (1...5).contains(score) else {
      return .init(disposition: .keep, highlight: false, notify: false)
    }
    let rule = policy.rule(for: score)
    return .init(disposition: rule.disposition, highlight: rule.highlight, notify: rule.push)
  }
}

public enum Transport: String, Codable, CaseIterable, Sendable {
  case air = "Air"
  case taxi = "Taxi"
  case train = "Train"
  case boat = "Boat"
  case road = "Road"
  case walk = "Walk"
  public var symbol: String {
    switch self {
    case .air: "airplane"
    case .taxi: "car.side"
    case .train: "tram"
    case .boat: "ferry"
    case .road: "car"
    case .walk: "figure.walk"
    }
  }
}
public struct JourneyLeg: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var mode: Transport
  public var origin: String
  public var destination: String
  public var departure: Date
  public var arrival: Date
  public var timeZoneID: String
  public var arrivalTimeZoneID: String
  public var source: String
  public var sourceEventID: String?
  public var reviewed: Bool
  public init(
    id: String = UUID().uuidString, mode: Transport, origin: String, destination: String,
    departure: Date, arrival: Date, timeZoneID: String = TimeZone.current.identifier,
    arrivalTimeZoneID: String? = nil, source: String = "Manual · booking unverified",
    sourceEventID: String? = nil, reviewed: Bool = true
  ) {
    self.id = id
    self.mode = mode
    self.origin = origin
    self.destination = destination
    self.departure = departure
    self.arrival = arrival
    self.timeZoneID = timeZoneID
    self.arrivalTimeZoneID = arrivalTimeZoneID ?? timeZoneID
    self.source = source
    self.sourceEventID = sourceEventID
    self.reviewed = reviewed
  }
}
public struct CalendarEntry: Identifiable, Sendable {
  public var id: String
  public var title: String
  public var start: Date
  public var end: Date
  public var location: String
  public var notes: String
  public var calendar: String
  public var timeZoneID: String
  public var allDay: Bool
  public var attendees: [String]
  public init(
    id: String, title: String, start: Date, end: Date, location: String = "", notes: String = "",
    calendar: String = "", timeZoneID: String = TimeZone.current.identifier, allDay: Bool = false,
    attendees: [String] = []
  ) {
    self.id = id
    self.title = title
    self.start = start
    self.end = end
    self.location = location
    self.notes = notes
    self.calendar = calendar
    self.timeZoneID = timeZoneID
    self.allDay = allDay
    self.attendees = attendees
  }
  /// Note lines that start with "- " or "• " are treated as checklist reminders.
  public var reminders: [String] {
    notes.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
      .compactMap { line in
        ["- ", "• "].first(where: line.hasPrefix).map { String(line.dropFirst($0.count)) }
      }
  }
  /// Notes without reminder lines.
  public var summary: String {
    notes.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.hasPrefix("- ") && !$0.hasPrefix("• ") && !$0.isEmpty }.joined(separator: " ")
  }
}
public enum JourneyImport {
  /// Candidate detection only. Calendar entries never become confirmed reservations.
  public static func candidate(_ event: CalendarEntry) -> JourneyLeg? {
    let text = (event.title + " " + event.notes).lowercased()
    let mode: Transport?
    if matches(text, words: ["flight", "airplane", "airport"]) {
      mode = .air
    } else if matches(text, words: ["ferry", "boat", "cruise"]) {
      mode = .boat
    } else if matches(text, words: ["train", "rail", "amtrak"]) {
      mode = .train
    } else if matches(text, words: ["taxi", "rideshare", "uber", "lyft"]) {
      mode = .taxi
    } else {
      mode = nil
    }
    guard let mode, !event.allDay else { return nil }
    return JourneyLeg(
      id: "calendar:\(event.id)", mode: mode, origin: "Review origin",
      destination: event.location.isEmpty ? event.title : event.location, departure: event.start,
      arrival: event.end, timeZoneID: event.timeZoneID,
      source: "Calendar: \(event.title) · review required", sourceEventID: event.id, reviewed: false
    )
  }
  private static func matches(_ text: String, words: [String]) -> Bool {
    words.contains {
      text.range(
        of: "\\b" + NSRegularExpression.escapedPattern(for: $0) + "\\b", options: .regularExpression
      ) != nil
    }
  }
  public static func merge(existing: [JourneyLeg], candidates: [JourneyLeg]) -> [JourneyLeg] {
    var result = existing
    for candidate in candidates {
      if let index = result.firstIndex(where: { $0.id == candidate.id }) {
        // Preserve explicitly reviewed routes; retain their source-event identity.
        if !result[index].reviewed { result[index] = candidate }
      } else {
        result.append(candidate)
      }
    }
    return result.sorted { $0.departure < $1.departure }
  }
}

public enum LocalPersistence {
  public static func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    try JSONDecoder().decode(type, from: Data(contentsOf: url))
  }
  public static func save<T: Encodable>(_ value: T, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}

/// Durable identifiers prevent reconnecting from reapplying destructive rules to old mail.
/// Each source (Apple Mail, or one IMAP mailbox generation) gets its own first-sight baseline,
/// so adding an account never treats its existing mail as new arrivals.
public struct IntakeLedger: Codable, Equatable, Sendable {
  public static let appleMail = "applemail"
  public var baselineEstablished = false
  public var baselinedSources: Set<String> = []
  public var seenIDs: Set<String> = []
  public var quarantinedIDs: Set<String> = []
  public var classifications: [String: Classification] = [:]
  public init() {}
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    baselineEstablished = try c.decodeIfPresent(Bool.self, forKey: .baselineEstablished) ?? false
    baselinedSources = try c.decodeIfPresent(Set<String>.self, forKey: .baselinedSources) ?? []
    seenIDs = try c.decodeIfPresent(Set<String>.self, forKey: .seenIDs) ?? []
    quarantinedIDs = try c.decodeIfPresent(Set<String>.self, forKey: .quarantinedIDs) ?? []
    classifications =
      try c.decodeIfPresent([String: Classification].self, forKey: .classifications) ?? [:]
    // Ledgers written before multi-account support baselined Apple Mail only.
    if baselineEstablished { baselinedSources.insert(Self.appleMail) }
  }
  public mutating func receive(_ ids: [String], source: String = IntakeLedger.appleMail)
    -> Set<String>
  {
    let incoming = Set(ids)
    let arrivals = baselinedSources.contains(source) ? incoming.subtracting(seenIDs) : []
    seenIDs.formUnion(incoming)
    baselinedSources.insert(source)
    if source == Self.appleMail { baselineEstablished = true }
    return arrivals
  }
}

/// Workspace state restored on launch. Account access is only resumed for sources the user
/// previously connected; the first connection still goes through the system permission prompts.
public struct SessionPreferences: Codable, Equatable, Sendable {
  public var live = false
  public var appleMail = false
  public var calendar = false
  public init() {}
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    live = try c.decodeIfPresent(Bool.self, forKey: .live) ?? false
    appleMail = try c.decodeIfPresent(Bool.self, forKey: .appleMail) ?? false
    calendar = try c.decodeIfPresent(Bool.self, forKey: .calendar) ?? false
  }
}
