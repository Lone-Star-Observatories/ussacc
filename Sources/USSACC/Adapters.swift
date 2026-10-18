import ACCCore
import AppKit
import EventKit

@MainActor final class CalendarAdapter {
  private let store = EKEventStore()
  func fetch() async throws -> [CalendarEntry] {
    guard try await store.requestFullAccessToEvents() else {
      throw IntegrationError.message(
        "Calendar access was declined. Enable USS ACC in System Settings → Privacy & Security → Calendars."
      )
    }
    let start = Calendar.current.startOfDay(for: .now)
    let end = Calendar.current.date(byAdding: .day, value: 60, to: start)!
    return store.events(
      matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)
    ).map {
      CalendarEntry(
        id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "Untitled event",
        start: $0.startDate, end: $0.endDate, location: $0.location ?? "", notes: $0.notes ?? "",
        calendar: $0.calendar.title,
        timeZoneID: $0.timeZone?.identifier ?? TimeZone.current.identifier, allDay: $0.isAllDay)
    }.sorted { $0.start < $1.start }
  }
}
enum IntegrationError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    switch self {
    case .message(let text): text
    }
  }
}

/// Apple Mail automation is opt-in. No message text is persisted to disk.
actor MailAdapter {
  func fetch() throws -> [Communication] {
    let script = """
      tell application "Mail"
          set collected to {}
          set inboxMessages to messages of inbox
          set n to count of inboxMessages
          if n > 40 then set n to 40
          repeat with i from 1 to n
              set m to item i of inboxMessages
              set end of collected to {(id of m) as text, sender of m, subject of m, content of m, (date received of m) as date}
          end repeat
          return collected
      end tell
      """
    let list = try execute(script)
    guard list.numberOfItems > 0 else { return [] }
    return (1...list.numberOfItems).compactMap { index in
      guard let record = list.atIndex(index), let id = record.atIndex(1)?.stringValue else {
        return nil
      }
      let sender = record.atIndex(2)?.stringValue ?? "Unknown sender"
      let address = Self.address(sender)
      return Communication(
        id: "mail:\(id)",
        name: sender.components(separatedBy: "<").first?.trimmingCharacters(
          in: .whitespacesAndNewlines) ?? sender, address: address, channel: .email,
        subject: record.atIndex(3)?.stringValue ?? "",
        body: String((record.atIndex(4)?.stringValue ?? "").prefix(24000)),
        date: record.atIndex(5)?.dateValue ?? .now)
    }
  }
  func trash(id: String) throws {
    let value = id.replacingOccurrences(of: "mail:", with: "")
    guard let numericID = Int(value) else {
      throw IntegrationError.message("Invalid Mail message identifier.")
    }
    _ = try execute(
      """
      tell application "Mail"
          set targets to (messages of inbox whose id is \(numericID))
          if (count of targets) is not 1 then error "Message no longer uniquely available in inbox."
          delete (item 1 of targets)
      end tell
      """)
  }
  private func execute(_ source: String) throws -> NSAppleEventDescriptor {
    var error: NSDictionary?
    guard let script = NSAppleScript(source: source) else {
      throw IntegrationError.message("Unable to prepare Apple Mail automation.")
    }
    let result = script.executeAndReturnError(&error)
    if let error {
      throw IntegrationError.message(
        (error[NSAppleScript.errorMessage] as? String) ?? "Mail automation failed.")
    }
    return result
  }
  static func address(_ sender: String) -> String {
    if let a = sender.firstIndex(of: "<"), let b = sender.lastIndex(of: ">"), a < b {
      return String(sender[sender.index(after: a)..<b]).lowercased()
    }
    return sender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}

@MainActor enum Handoff {
  @discardableResult static func open(
    _ scheme: String, to address: String, subject: String? = nil, body: String? = nil
  ) -> Bool {
    var components = URLComponents()
    components.scheme = scheme
    components.path = address
    var query: [URLQueryItem] = []
    if let subject, !subject.isEmpty { query.append(.init(name: "subject", value: subject)) }
    if let body, !body.isEmpty { query.append(.init(name: "body", value: body)) }
    if !query.isEmpty { components.queryItems = query }
    guard let url = components.url else { return false }
    return NSWorkspace.shared.open(url)
  }
}
