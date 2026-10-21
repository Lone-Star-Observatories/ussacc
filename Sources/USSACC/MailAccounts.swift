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
  /// Returns the source key (account + UIDVALIDITY) and the newest inbox messages.
  static func fetch(_ account: MailAccount, password: String, limit: Int = 40) async throws
    -> (source: String, items: [Communication])
  {
    let session = try await session(account, password: password)
    do {
      let inbox = try await session.select()
      let fetched = try await session.fetchLatest(exists: inbox.exists, count: limit)
      await session.logout()
      let source = "imap:\(account.id):\(inbox.uidValidity)"
      return (
        source,
        fetched.map { message in
          let parsed = MailParser.parse(message.raw)
          return Communication(
            id: "\(source):\(message.uid)",
            name: parsed.fromName.isEmpty ? "Unknown sender" : parsed.fromName,
            address: parsed.fromAddress, channel: .email, subject: parsed.subject,
            body: String(parsed.body.prefix(24000)),
            date: parsed.date ?? message.internalDate ?? .now)
        }
      )
    } catch {
      await session.logout()
      throw error
    }
  }
  static func test(_ account: MailAccount, password: String) async throws -> String {
    let session = try await session(account, password: password)
    let inbox = try await session.select()
    let trash = try await session.trashMailbox()
    await session.logout()
    return "Connected · \(inbox.exists) messages in Inbox · "
      + (trash.map { "Trash: \($0)" } ?? "no Trash folder (Delete rules will keep mail)")
  }
  /// `id` is `imap:<account>:<uidvalidity>:<uid>`.
  static func trash(_ account: MailAccount, password: String, id: String) async throws {
    let parts = id.split(separator: ":")
    guard parts.count == 4, let validity = UInt32(parts[2]), let uid = UInt32(parts[3]) else {
      throw IntegrationError.message("Invalid IMAP message identifier.")
    }
    let session = try await session(account, password: password)
    do {
      try await session.moveToTrash(uid: uid, uidValidity: validity)
      await session.logout()
    } catch {
      await session.logout()
      throw error
    }
  }
}

/// Reads account settings from Apple Mail. Mail does not expose passwords to automation.
enum AppleMailAccountImport {
  static func accounts() throws -> [MailAccount] {
    let script = """
      tell application "Mail"
          set out to {}
          repeat with a in accounts
              try
                  set kind to (account type of a) as text
                  set host to ""
                  set portNumber to 993
                  set login to ""
                  try
                      set host to server name of a
                  end try
                  try
                      set portNumber to port of a
                  end try
                  try
                      set login to user name of a
                  end try
                  set end of out to {name of a, kind, host, portNumber, login, (email addresses of a), (enabled of a)}
              end try
          end repeat
          return out
      end tell
      """
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
    return (1...list.numberOfItems).compactMap { index in
      guard let row = list.atIndex(index) else { return nil }
      let name = row.atIndex(1)?.stringValue ?? ""
      let kind = (row.atIndex(2)?.stringValue ?? "").lowercased()
      var host = row.atIndex(3)?.stringValue ?? ""
      var port = Int(row.atIndex(4)?.int32Value ?? 993)
      let login = row.atIndex(5)?.stringValue ?? ""
      var emails: [String] = []
      if let list = row.atIndex(6), list.numberOfItems > 0 {
        emails = (1...list.numberOfItems).compactMap { list.atIndex($0)?.stringValue }
      }
      let email = emails.first ?? (login.contains("@") ? login : "")
      // POP and Exchange accounts have no compatible IMAP inbox to read.
      guard !email.isEmpty, !["pop", "ews", "exchange"].contains(where: kind.contains) else {
        return nil
      }
      let provider =
        kind.contains("icloud") ? .icloud : MailProvider.detect(host: host, email: email)
      if let preset = provider.host, host.isEmpty || provider != .imap { host = preset }
      // Mail reports 143 for STARTTLS accounts; the TLS port is the safe equivalent.
      if port == 143 || port == 0 { port = 993 }
      let username = provider == .icloud || provider == .gmail || login.isEmpty ? email : login
      return MailAccount(
        provider: provider, name: name, email: email, username: username, host: host, port: port,
        enabled: true, importedFromAppleMail: true)
    }
  }
}
