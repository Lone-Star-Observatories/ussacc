import ACCCore
import AppKit
import Foundation
import Network
import Security

/// IMAP over implicit TLS. Certificates are validated by the system; there is no plaintext fallback.
final class NetworkIMAPTransport: IMAPTransport, @unchecked Sendable {
  private let connection: NWConnection
  private let queue = DispatchQueue(label: "ussacc.imap")
  init(host: String, port: Int) {
    connection = NWConnection(
      host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)), using: .tls)
  }
  func open(timeout: Duration = .seconds(20)) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { [connection, queue] in
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
          let once = Once()
          connection.stateUpdateHandler = { state in
            switch state {
            case .ready: once.run { continuation.resume() }
            case .failed(let error), .waiting(let error):
              once.run { continuation.resume(throwing: IMAPError.server(Self.describe(error))) }
            case .cancelled: once.run { continuation.resume(throwing: IMAPError.closed) }
            default: break
            }
          }
          connection.start(queue: queue)
        }
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw IMAPError.server("Timed out connecting to the mail server.")
      }
      defer { group.cancelAll() }
      try await group.next()
    }
  }
  func send(_ data: Data) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.send(
        content: data,
        completion: .contentProcessed { error in
          if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        })
    }
  }
  func receive() async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
        data, _, _, error in
        if let error {
          continuation.resume(throwing: error)
        } else if let data, !data.isEmpty {
          continuation.resume(returning: data)
        } else {
          continuation.resume(returning: Data())  // closed or complete
        }
      }
    }
  }
  func close() async { connection.cancel() }
  static func describe(_ error: NWError) -> String {
    switch error {
    case .tls(let status):
      "TLS failed (\(status)). Check the server name and that it supports TLS on this port."
    case .dns: "Mail server name could not be resolved."
    default: error.localizedDescription
    }
  }
  private final class Once: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func run(_ body: () -> Void) {
      lock.lock()
      defer { lock.unlock() }
      guard !done else { return }
      done = true
      body()
    }
  }
}

/// Passwords live in the login Keychain, never in USS ACC's JSON files.
enum MailKeychain {
  private static let service = "USS ACC Mail"
  static func save(_ password: String, for account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
    var item = query
    item[kSecValueData as String] = Data(password.utf8)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw IntegrationError.message("Keychain save failed (\(status)).")
    }
  }
  static func password(for account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account, kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }
  static func delete(for account: String) {
    SecItemDelete(
      [
        kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
        kSecAttrAccount as String: account,
      ] as CFDictionary)
  }
}

/// One IMAP inbox. Each poll opens a short session, reads the newest messages, and logs out.
enum IMAPMailSource {
  static func session(_ account: MailAccount, password: String) async throws -> IMAPSession {
    let transport = NetworkIMAPTransport(host: account.host, port: account.port)
    try await transport.open()
    let session = IMAPSession(transport: transport)
    do {
      try await session.greeting()
      try await session.login(user: account.username, password: password)
      return session
    } catch {
      await transport.close()
      throw error
    }
  }
  /// Incremental sync. First run (or after a UIDVALIDITY reset) takes the newest `initialCount`
  /// messages; later runs fetch only UIDs above the stored high-water mark.
  static func sync(
    _ account: MailAccount, password: String, state: MessageStore.SyncState?,
    initialCount: Int = 200
  ) async throws -> (source: String, items: [Communication], state: MessageStore.SyncState) {
    let session = try await session(account, password: password)
    do {
      let inbox = try await session.select()
      let fetched: [IMAPFetched]
      var next: MessageStore.SyncState
      if let state, state.uidValidity == inbox.uidValidity, inbox.uidValidity != 0 {
        fetched = inbox.exists == 0 ? [] : try await session.fetchNewer(than: state.highestUID)
        next = state
        next.highestUID = max(state.highestUID, fetched.map(\.uid).max() ?? 0)
      } else {
        fetched = try await session.fetchLatest(exists: inbox.exists, count: initialCount)
        next = .init(
          uidValidity: inbox.uidValidity, highestUID: fetched.map(\.uid).max() ?? 0,
          lowestUID: fetched.map(\.uid).min() ?? 0)
      }
      await session.logout()
      let source = "imap:\(account.id):\(inbox.uidValidity)"
      return (source, fetched.map { communication($0, source: source) }, next)
    } catch {
      await session.logout()
      throw error
    }
  }
  /// Backfills up to `count` messages older than the oldest one stored.
  static func older(
    _ account: MailAccount, password: String, state: MessageStore.SyncState, count: Int = 200
  ) async throws -> (source: String, items: [Communication], state: MessageStore.SyncState) {
    let session = try await session(account, password: password)
    do {
      let inbox = try await session.select()
      guard inbox.uidValidity == state.uidValidity else {
        await session.logout()
        throw IntegrationError.message("Mailbox changed; it will resync on the next check.")
      }
      let fetched = try await session.fetchOlder(than: state.lowestUID, count: count)
      await session.logout()
      var next = state
      if let lowest = fetched.map(\.uid).min() { next.lowestUID = lowest }
      let source = "imap:\(account.id):\(inbox.uidValidity)"
      return (source, fetched.map { communication($0, source: source) }, next)
    } catch {
      await session.logout()
      throw error
    }
  }
  private static func communication(_ message: IMAPFetched, source: String) -> Communication {
    let parsed = MailParser.parse(message.raw)
    return Communication(
      id: "\(source):\(message.uid)",
      name: parsed.fromName.isEmpty ? "Unknown sender" : parsed.fromName,
      address: parsed.fromAddress, channel: .email, subject: parsed.subject,
      body: String(parsed.body.prefix(24000)),
      date: parsed.date ?? message.internalDate ?? .now)
  }
  static func test(_ account: MailAccount, password: String) async throws -> String {
    let session = try await session(account, password: password)
    let inbox = try await session.select()
    let trash = try await session.trashMailbox()
    await session.logout()
    return "Connected · \(inbox.exists) messages in Inbox · "
      + (trash.map { "Trash: \($0)" } ?? "no Trash folder (Delete rules will keep mail)")
  }
  /// Moves messages (ids `imap:<account>:<uidvalidity>:<uid>`) to Trash in one session.
  static func trash(_ account: MailAccount, password: String, ids: [String]) async throws {
    var byValidity: [UInt32: [UInt32]] = [:]
    for id in ids {
      let parts = id.split(separator: ":")
      guard parts.count == 4, let validity = UInt32(parts[2]), let uid = UInt32(parts[3]) else {
        throw IntegrationError.message("Invalid IMAP message identifier.")
      }
      byValidity[validity, default: []].append(uid)
    }
    guard !byValidity.isEmpty else { return }
    let session = try await session(account, password: password)
    do {
      for (validity, uids) in byValidity {
        try await session.moveToTrash(uids: uids, uidValidity: validity)
      }
      await session.logout()
    } catch {
      await session.logout()
      throw error
    }
  }
  static func trash(_ account: MailAccount, password: String, id: String) async throws {
    try await trash(account, password: password, ids: [id])
  }
}

/// One Apple Mail account and whether it can be added here.
struct AppleMailCandidate: Identifiable {
  let id = UUID()
  var account: MailAccount
  /// nil when the account can be imported; otherwise why not.
  var unavailable: String?
}

/// Reads account settings from Apple Mail. Mail does not expose passwords to automation.
enum AppleMailAccountImport {
  // Variable names avoid Mail's scripting terms (e.g. `kind`, `host`), which cannot be assigned.
  static let script = """
    tell application "Mail"
        set out to {}
        repeat with acct in accounts
            set acctName to ""
            set acctType to ""
            set acctServer to ""
            set acctPort to 0
            set acctUser to ""
            set acctEmails to {}
            set acctEnabled to true
            try
                set acctName to name of acct
            end try
            try
                set acctType to (account type of acct) as text
            end try
            try
                set acctServer to server name of acct
            end try
            try
                set acctPort to port of acct
            end try
            try
                set acctUser to user name of acct
            end try
            try
                set acctEmails to email addresses of acct
            end try
            try
                set acctEnabled to enabled of acct
            end try
            set end of out to {acctName, acctType, acctServer, acctPort, acctUser, acctEmails, acctEnabled}
        end repeat
        return out
    end tell
    """
  static func candidates(existing: [MailAccount]) throws -> [AppleMailCandidate] {
    var error: NSDictionary?
    guard let apple = NSAppleScript(source: script) else {
      throw IntegrationError.message("Unable to prepare Apple Mail automation.")
    }
    let list = apple.executeAndReturnError(&error)
    if let error {
      throw IntegrationError.message(
        (error[NSAppleScript.errorMessage] as? String) ?? "Apple Mail automation failed.")
    }
    guard list.numberOfItems > 0 else { return [] }
    var seen = Set(existing.map { key($0.username, $0.host) })
    return (1...list.numberOfItems).compactMap { index -> AppleMailCandidate? in
      guard let row = list.atIndex(index) else { return nil }
      let name = row.atIndex(1)?.stringValue ?? ""
      let kind = (row.atIndex(2)?.stringValue ?? "").lowercased()
      var host = row.atIndex(3)?.stringValue ?? ""
      var port = Int(row.atIndex(4)?.int32Value ?? 0)
      let login = row.atIndex(5)?.stringValue ?? ""
      var emails: [String] = []
      if let list = row.atIndex(6), list.numberOfItems > 0 {
        emails = (1...list.numberOfItems).compactMap { list.atIndex($0)?.stringValue }
      }
      let enabled = row.atIndex(7)?.booleanValue ?? true
      let isICloud = kind.contains("icloud")
      // iCloud lists the Apple ID first, which may be another provider's address.
      let email =
        (isICloud
          ? emails.first { ["@icloud.com", "@me.com", "@mac.com"].contains(where: $0.lowercased().hasSuffix) }
          : nil) ?? emails.first ?? (login.contains("@") ? login : login)
      let provider = isICloud ? .icloud : MailProvider.detect(host: host, email: email)
      if let preset = provider.host, host.isEmpty || provider != .imap { host = preset }
      // Mail reports 143 for STARTTLS accounts; the TLS port is the safe equivalent.
      if port == 143 || port == 0 { port = 993 }
      let username = isICloud ? email : (login.isEmpty ? email : login)
      let account = MailAccount(
        provider: provider, name: name, email: email, username: username, host: host, port: port,
        enabled: true, importedFromAppleMail: true)
      var reason: String?
      if kind.contains("pop") {
        reason = "POP account — not supported"
      } else if kind.contains("ews") || kind.contains("exchange") {
        reason = "Exchange account — not supported"
      } else if email.isEmpty || host.isEmpty {
        reason = "No server settings available from Mail"
      } else if !seen.insert(key(username, host)).inserted {
        reason = existing.contains { key($0.username, $0.host) == key(username, host) }
          ? "Already added" : "Duplicate of an account above"
      } else if !enabled {
        reason = nil  // disabled in Mail, still importable
      }
      return AppleMailCandidate(account: account, unavailable: reason)
    }
  }
  private static func key(_ user: String, _ host: String) -> String {
    user.lowercased() + "@" + host.lowercased()
  }
}
