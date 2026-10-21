import Foundation

// MARK: - Accounts

public enum MailProvider: String, Codable, CaseIterable, Sendable {
  case gmail, icloud, yahoo, fastmail, imap
  public var title: String {
    switch self {
    case .gmail: "Gmail"
    case .icloud: "iCloud Mail"
    case .yahoo: "Yahoo Mail"
    case .fastmail: "Fastmail"
    case .imap: "Other IMAP"
    }
  }
  public var host: String? {
    switch self {
    case .gmail: "imap.gmail.com"
    case .icloud: "imap.mail.me.com"
    case .yahoo: "imap.mail.yahoo.com"
    case .fastmail: "imap.fastmail.com"
    case .imap: nil
    }
  }
  /// What to put in the password field. Providers with 2-step sign-in reject the normal password.
  public var passwordHelp: String {
    switch self {
    case .gmail:
      "Use a Google app password (Google Account → Security → 2-Step Verification → App passwords). IMAP must be enabled in Gmail settings."
    case .icloud:
      "Use an app-specific password from account.apple.com → Sign-In and Security."
    case .yahoo: "Use an app password from Yahoo Account Security."
    case .fastmail: "Use an app password from Fastmail Settings → Privacy & Security."
    case .imap: "Use your IMAP password or an app password if your provider requires one."
    }
  }
  public var passwordURL: URL? {
    switch self {
    case .gmail: URL(string: "https://myaccount.google.com/apppasswords")
    case .icloud: URL(string: "https://account.apple.com/account/manage")
    case .yahoo: URL(string: "https://login.yahoo.com/account/security")
    case .fastmail: URL(string: "https://app.fastmail.com/settings/security/apppasswords")
    case .imap: nil
    }
  }
  public static func detect(host: String, email: String) -> MailProvider {
    let h = host.lowercased()
    let domain = email.lowercased().split(separator: "@").last.map(String.init) ?? ""
    if h.contains("gmail") || h.contains("googlemail") || ["gmail.com", "googlemail.com"].contains(domain) {
      return .gmail
    }
    if h.contains("mail.me.com") || ["icloud.com", "me.com", "mac.com"].contains(domain) {
      return .icloud
    }
    if h.contains("yahoo") || domain.hasPrefix("yahoo.") { return .yahoo }
    if h.contains("fastmail") || domain == "fastmail.com" { return .fastmail }
    return .imap
  }
}

public struct MailAccount: Codable, Identifiable, Equatable, Hashable, Sendable {
  public var id: String
  public var provider: MailProvider
  public var name: String
  public var email: String
  public var username: String
  public var host: String
  public var port: Int
  public var enabled: Bool
  public var importedFromAppleMail: Bool
  public init(
    id: String = UUID().uuidString, provider: MailProvider, name: String = "", email: String,
    username: String = "", host: String = "", port: Int = 993, enabled: Bool = true,
    importedFromAppleMail: Bool = false
  ) {
    self.id = id
    self.provider = provider
    self.name = name
    self.email = email
    self.username = username.isEmpty ? email : username
    self.host = host.isEmpty ? (provider.host ?? "") : host
    self.port = port
    self.enabled = enabled
    self.importedFromAppleMail = importedFromAppleMail
  }
  public var title: String { name.isEmpty ? email : name }
  /// Only implicit TLS is supported; plaintext IMAP is rejected rather than downgraded.
  public var validationError: String? {
    if email.trimmingCharacters(in: .whitespaces).isEmpty { return "Email address is required." }
    if username.trimmingCharacters(in: .whitespaces).isEmpty { return "Username is required." }
    if host.trimmingCharacters(in: .whitespaces).isEmpty { return "IMAP server is required." }
    if port == 143 { return "Port 143 is plaintext/STARTTLS. Use the provider's TLS port (usually 993)." }
    if !(1...65535).contains(port) { return "Port must be between 1 and 65535." }
    return nil
  }
}

// MARK: - IMAP values and parsing

public indirect enum IMAPValue: Equatable, Sendable {
  case atom(String)
  case string(Data)
  case list([IMAPValue])
  case null
  public var text: String? {
    switch self {
    case .atom(let s): s
    case .string(let d): String(decoding: d, as: UTF8.self)
    default: nil
    }
  }
  public var items: [IMAPValue] {
    if case .list(let values) = self { return values }
    return []
  }
}

public enum IMAPParser {
  /// Tokenizes one logical IMAP response, including any `{n}` literals it carries.
  public static func parse(_ data: Data) -> [IMAPValue] {
    let bytes = [UInt8](data)
    var index = 0
    var values: [IMAPValue] = []
    while index < bytes.count {
      if let value = next(bytes, &index) { values.append(value) } else if index < bytes.count,
        bytes[index] == 0x29
      {
        index += 1  // stray ')'
      }
    }
    return values
  }
  private static func next(_ b: [UInt8], _ i: inout Int) -> IMAPValue? {
    while i < b.count, [0x20, 0x0D, 0x0A].contains(b[i]) { i += 1 }
    guard i < b.count else { return nil }
    switch b[i] {
    case 0x28:  // (
      i += 1
      var items: [IMAPValue] = []
      while i < b.count {
        while i < b.count, [0x20, 0x0D, 0x0A].contains(b[i]) { i += 1 }
        if i < b.count, b[i] == 0x29 {
          i += 1
          break
        }
        guard let value = next(b, &i) else { break }
        items.append(value)
      }
      return .list(items)
    case 0x29:
      return nil
    case 0x22:  // "
      i += 1
      var out: [UInt8] = []
      while i < b.count, b[i] != 0x22 {
        if b[i] == 0x5C, i + 1 < b.count { i += 1 }
        out.append(b[i])
        i += 1
      }
      i += 1
      return .string(Data(out))
    case 0x7B:  // {n} or {n+}
      var j = i + 1
      var digits = ""
      while j < b.count, b[j] >= 0x30, b[j] <= 0x39 {
        digits.append(Character(UnicodeScalar(b[j])))
        j += 1
      }
      if j < b.count, b[j] == 0x2B { j += 1 }
      guard j < b.count, b[j] == 0x7D, let length = Int(digits) else { return atom(b, &i) }
      j += 1
      if j < b.count, b[j] == 0x0D { j += 1 }
      if j < b.count, b[j] == 0x0A { j += 1 }
      let end = min(b.count, j + length)
      i = end
      return .string(Data(b[j..<end]))
    default:
      return atom(b, &i)
    }
  }
  private static func atom(_ b: [UInt8], _ i: inout Int) -> IMAPValue {
    var out: [UInt8] = []
    var depth = 0
    while i < b.count {
      let c = b[i]
      if depth == 0, [0x20, 0x28, 0x29, 0x0D, 0x0A, 0x22].contains(c) { break }
      if c == 0x5B { depth += 1 }
      if c == 0x5D { depth = max(0, depth - 1) }
      out.append(c)
      i += 1
    }
    let text = String(decoding: out, as: UTF8.self)
    return text.uppercased() == "NIL" ? .null : .atom(text)
  }
  /// IMAP quoted string, or nil when the value needs a literal.
  public static func quoted(_ text: String) -> String? {
    guard text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F }) else { return nil }
    return "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }
}

/// Splits a byte stream into logical responses: a line plus any literals announced at line ends.
public struct IMAPFramer: Sendable {
  private var buffer: [UInt8] = []
  public init() {}
  public mutating func append(_ data: Data) { buffer.append(contentsOf: data) }
  public mutating func next() -> Data? {
    var i = 0
    while true {
      guard let lf = buffer[i...].firstIndex(of: 0x0A) else { return nil }
      // Does this line end with {n}\r\n ?
      var end = lf
      if end > 0, buffer[end - 1] == 0x0D { end -= 1 }
      if end > 0, buffer[end - 1] == 0x7D, let open = buffer[i..<end].lastIndex(of: 0x7B) {
        let digits = buffer[(open + 1)..<(end - 1)].filter { $0 != 0x2B }
        if let length = Int(String(decoding: digits, as: UTF8.self)), !digits.isEmpty {
          let literalEnd = lf + 1 + length
          guard buffer.count >= literalEnd else { return nil }
          i = literalEnd
          continue
        }
      }
      let response = Data(buffer[0...lf])
      buffer.removeFirst(lf + 1)
      return response
    }
  }
}

public struct IMAPFetched: Equatable, Sendable {
  public var uid: UInt32
  public var internalDate: Date?
  public var raw: Data
}

public protocol IMAPTransport: Sendable {
  func send(_ data: Data) async throws
  /// Next chunk of bytes; empty when the server closed the connection.
  func receive() async throws -> Data
  func close() async
}

public enum IMAPError: LocalizedError, Equatable {
  case closed
  case server(String)
  case protocolError(String)
  public var errorDescription: String? {
    switch self {
    case .closed: "The mail server closed the connection."
    case .server(let message): message
    case .protocolError(let message): "IMAP protocol error: \(message)"
    }
  }
}

/// Minimal IMAP4rev1 client: login, inbox snapshot, and move-to-Trash. It never expunges.
public actor IMAPSession {
  private let transport: IMAPTransport
  private var framer = IMAPFramer()
  private var tag = 0
  public private(set) var capabilities: Set<String> = []
  public init(transport: IMAPTransport) { self.transport = transport }

  public enum Part: Sendable {
    case text(String)
    case literal(Data)
  }

  private func nextResponse() async throws -> Data {
    while true {
      if let response = framer.next() { return response }
      let chunk = try await transport.receive()
      if chunk.isEmpty { throw IMAPError.closed }
      framer.append(chunk)
    }
  }
  public func greeting() async throws {
    let line = try await nextResponse()
    let tokens = IMAPParser.parse(line)
    guard tokens.first == .atom("*"), let status = tokens.dropFirst().first?.text?.uppercased(),
      status == "OK" || status == "PREAUTH"
    else { throw IMAPError.server(Self.message(line, skip: 2) ?? "Server refused the connection.") }
    absorbCapabilities(tokens)
  }
  /// Sends a command and returns its untagged responses. NO/BAD become `IMAPError.server`.
  @discardableResult public func command(_ parts: [Part]) async throws -> [[IMAPValue]] {
    tag += 1
    let label = "A\(tag)"
    var pending = Data((label + " ").utf8)
    for part in parts {
      switch part {
      case .text(let text): pending.append(Data(text.utf8))
      case .literal(let data):
        pending.append(Data("{\(data.count)}\r\n".utf8))
        try await transport.send(pending)
        pending = Data()
        // Wait for the continuation before sending literal bytes.
        while true {
          let response = try await nextResponse()
          if response.first == 0x2B { break }
          let tokens = IMAPParser.parse(response)
          if tokens.first == .atom(label) {
            throw IMAPError.server(Self.message(response, skip: 2) ?? "Command rejected.")
          }
        }
        pending.append(data)
      }
    }
    pending.append(Data("\r\n".utf8))
    try await transport.send(pending)
    var untagged: [[IMAPValue]] = []
    while true {
      let response = try await nextResponse()
      if response.first == 0x2B { continue }
      let tokens = IMAPParser.parse(response)
      if tokens.first == .atom("*") {
        if tokens.dropFirst().first?.text?.uppercased() == "BYE" {
          throw IMAPError.server(Self.message(response, skip: 2) ?? "Server ended the session.")
        }
        absorbCapabilities(tokens)
        untagged.append(Array(tokens.dropFirst()))
        continue
      }
      guard tokens.first == .atom(label) else { continue }
      let status = tokens.dropFirst().first?.text?.uppercased()
      if status == "OK" {
        absorbCapabilities(tokens)
        return untagged
      }
      throw IMAPError.server(Self.message(response, skip: 2) ?? "\(status ?? "BAD") response.")
    }
  }
  @discardableResult public func command(_ text: String) async throws -> [[IMAPValue]] {
    try await command([.text(text)])
  }
  public func login(user: String, password: String) async throws {
    if capabilities.isEmpty { try await command("CAPABILITY") }
    if capabilities.contains("LOGINDISABLED") {
      throw IMAPError.server("The server does not allow password login on this connection.")
    }
    var parts: [Part] = [.text("LOGIN ")]
    parts += Self.astring(user)
    parts.append(.text(" "))
    parts += Self.astring(password)
    try await command(parts)
    if !capabilities.contains("MOVE") { try await command("CAPABILITY") }
  }
  public func select(_ mailbox: String = "INBOX") async throws -> (exists: Int, uidValidity: UInt32)
  {
    var parts: [Part] = [.text("EXAMINE ")]
    parts += Self.astring(mailbox)
    let responses = try await command(parts)
    var exists = 0
    var validity: UInt32 = 0
    for tokens in responses {
      if tokens.count >= 2, tokens[1].text?.uppercased() == "EXISTS" {
        exists = Int(tokens[0].text ?? "") ?? 0
      }
      if let value = Self.code("UIDVALIDITY", in: tokens).flatMap({ UInt32($0) }) { validity = value }
    }
    return (exists, validity)
  }
  /// The newest `count` messages, read with BODY.PEEK so nothing is marked as read.
  public func fetchLatest(exists: Int, count: Int, maxBytes: Int = 24000) async throws
    -> [IMAPFetched]
  {
    guard exists > 0, count > 0 else { return [] }
    return try await fetch("FETCH \(max(1, exists - count + 1)):\(exists)", maxBytes: maxBytes)
  }
  /// Messages with UID greater than `uid` (new mail since the last sync).
  public func fetchNewer(than uid: UInt32, maxBytes: Int = 24000) async throws -> [IMAPFetched] {
    // `n:*` always returns at least the last message, so filter to genuinely newer UIDs.
    try await fetch("UID FETCH \(uid + 1):*", maxBytes: maxBytes).filter { $0.uid > uid }
  }
  /// Up to `count` messages older than `uid` (backfill), using sequence numbers.
  public func fetchOlder(than uid: UInt32, count: Int, maxBytes: Int = 24000) async throws
    -> [IMAPFetched]
  {
    guard uid > 1, count > 0 else { return [] }
    // SEARCH (not UID SEARCH) returns sequence numbers of messages below `uid`.
    let responses = try await command("SEARCH UID 1:\(uid - 1)")
    let sequences = responses.filter { $0.first?.text?.uppercased() == "SEARCH" }
      .flatMap { $0.dropFirst().compactMap { Int($0.text ?? "") } }
    guard let last = sequences.max() else { return [] }
    let first = max(sequences.min() ?? 1, last - count + 1)
    return try await fetch("FETCH \(first):\(last)", maxBytes: maxBytes).filter { $0.uid < uid }
  }
  private func fetch(_ prefix: String, maxBytes: Int) async throws -> [IMAPFetched] {
    let responses = try await command("\(prefix) (UID INTERNALDATE BODY.PEEK[]<0.\(maxBytes)>)")
    return responses.compactMap { tokens in
      guard tokens.count >= 3, tokens[1].text?.uppercased() == "FETCH" else { return nil }
      let items = tokens[2].items
      var uid: UInt32?
      var date: Date?
      var raw = Data()
      var k = 0
      while k + 1 < items.count {
        let key = items[k].text?.uppercased() ?? ""
        let value = items[k + 1]
        if key == "UID" { uid = UInt32(value.text ?? "") }
        if key == "INTERNALDATE" { date = value.text.flatMap(Self.internalDate) }
        if key.hasPrefix("BODY[") { if case .string(let data) = value { raw = data } }
        k += 2
      }
      return uid.map { IMAPFetched(uid: $0, internalDate: date, raw: raw) }
    }.sorted { $0.uid > $1.uid }
  }
  /// Finds the special-use \Trash mailbox, falling back to common names.
  public func trashMailbox() async throws -> String? {
    let responses = try await command("LIST \"\" \"*\"")
    var names: [String] = []
    for tokens in responses where tokens.first?.text?.uppercased() == "LIST" && tokens.count >= 4 {
      guard let name = tokens[3].text else { continue }
      if tokens[1].items.contains(where: { $0.text?.lowercased() == "\\trash" }) { return name }
      names.append(name)
    }
    for candidate in ["[Gmail]/Trash", "[Google Mail]/Trash", "Trash", "Deleted Messages", "Deleted Items", "INBOX.Trash"] {
      if let match = names.first(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
        return match
      }
    }
    return nil
  }
  /// Moves one message to Trash. Without MOVE it copies and flags \Deleted but never expunges.
  public func moveToTrash(uid: UInt32, uidValidity: UInt32) async throws {
    try await moveToTrash(uids: [uid], uidValidity: uidValidity)
  }
  /// Moves messages to Trash in one command. Without MOVE it copies and flags \Deleted, never expunging.
  public func moveToTrash(uids: [UInt32], uidValidity: UInt32) async throws {
    guard !uids.isEmpty else { return }
    guard let trash = try await trashMailbox() else {
      throw IMAPError.server("No Trash mailbox found on this account; message kept.")
    }
    var select: [Part] = [.text("SELECT ")]
    select += Self.astring("INBOX")
    let responses = try await command(select)
    let validity = responses.compactMap { Self.code("UIDVALIDITY", in: $0).flatMap { UInt32($0) } }
      .first
    if let validity, validity != uidValidity {
      throw IMAPError.server("Mailbox changed since this message was read; message kept.")
    }
    let set = uids.map(String.init).joined(separator: ",")
    var parts: [Part] = [.text(capabilities.contains("MOVE") ? "UID MOVE \(set) " : "UID COPY \(set) ")]
    parts += Self.astring(trash)
    try await command(parts)
    if !capabilities.contains("MOVE") {
      try await command("UID STORE \(set) +FLAGS.SILENT (\\Deleted)")
    }
  }
  public func logout() async {
    _ = try? await command("LOGOUT")
    await transport.close()
  }
  private func absorbCapabilities(_ tokens: [IMAPValue]) {
    let atoms = tokens.compactMap { value -> String? in
      if case .atom(let text) = value { return text }
      return nil
    }
    if atoms.count > 1, atoms[1].uppercased() == "CAPABILITY" {
      capabilities = Set(atoms.dropFirst(2).map { $0.uppercased() })
    } else if let value = Self.code("CAPABILITY", in: tokens) {
      capabilities = Set(value.split(separator: " ").map { $0.uppercased() })
    }
  }
  /// Value of a bracketed response code such as `[UIDVALIDITY 42]`.
  static func code(_ name: String, in tokens: [IMAPValue]) -> String? {
    for case .atom(let text) in tokens where text.uppercased().hasPrefix("[" + name + " ") {
      return text.dropFirst(name.count + 2).trimmingCharacters(in: .init(charactersIn: " ]"))
    }
    return nil
  }
  static func astring(_ text: String) -> [Part] {
    if let quoted = IMAPParser.quoted(text) { return [.text(quoted)] }
    return [.literal(Data(text.utf8))]
  }
  static func message(_ line: Data, skip: Int) -> String? {
    let text = String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = text.split(separator: " ", maxSplits: skip, omittingEmptySubsequences: true)
    guard parts.count > skip else { return nil }
    var message = String(parts[skip])
    if message.hasPrefix("["), let close = message.firstIndex(of: "]") {
      message = String(message[message.index(after: close)...]).trimmingCharacters(in: .whitespaces)
    }
    return message.isEmpty ? nil : message
  }
  static func internalDate(_ text: String) -> Date? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "d-MMM-yyyy HH:mm:ss Z"
    return f.date(from: text.trimmingCharacters(in: .whitespaces))
  }
}

// MARK: - MIME

public struct ParsedMail: Equatable, Sendable {
  public var fromName: String
  public var fromAddress: String
  public var subject: String
  public var body: String
  public var date: Date?
}

/// Best-effort RFC 5322 / MIME reader for classification previews. Input may be truncated.
public enum MailParser {
  public static func parse(_ raw: Data) -> ParsedMail {
    let (headerBytes, bodyBytes) = split(raw)
    let headers = parseHeaders(headerBytes)
    let from = decodeWords(headers["from"] ?? "")
    let (name, address) = splitAddress(from)
    let body = text(headers: headers, body: bodyBytes)
    return ParsedMail(
      fromName: name, fromAddress: address,
      subject: decodeWords(headers["subject"] ?? "").trimmingCharacters(in: .whitespaces),
      body: body.trimmingCharacters(in: .whitespacesAndNewlines),
      date: headers["date"].flatMap(rfc2822Date))
  }
  static func split(_ raw: Data) -> (Data, Data) {
    let b = [UInt8](raw)
    for i in 0..<max(0, b.count - 1) {
      if b[i] == 0x0A, b[i + 1] == 0x0A { return (Data(b[..<i]), Data(b[(i + 2)...])) }
      if i + 3 < b.count, b[i] == 0x0D, b[i + 1] == 0x0A, b[i + 2] == 0x0D, b[i + 3] == 0x0A {
        return (Data(b[..<i]), Data(b[(i + 4)...]))
      }
    }
    return (raw, Data())
  }
  static func parseHeaders(_ data: Data) -> [String: String] {
    let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
    var result: [String: String] = [:]
    var current: (String, String)?
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      if line.first == " " || line.first == "\t", var c = current {
        c.1 += " " + line.trimmingCharacters(in: .whitespaces)
        current = c
        continue
      }
      if let c = current, result[c.0] == nil { result[c.0] = c.1 }
      guard let colon = line.firstIndex(of: ":") else {
        current = nil
        continue
      }
      current = (
        line[..<colon].lowercased().trimmingCharacters(in: .whitespaces),
        line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      )
    }
    if let c = current, result[c.0] == nil { result[c.0] = c.1 }
    return result
  }
  static func parameter(_ name: String, in header: String) -> String? {
    for piece in header.split(separator: ";").dropFirst() {
      let pair = piece.split(separator: "=", maxSplits: 1)
      guard pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces).lowercased() == name else {
        continue
      }
      return pair[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: .init(charactersIn: "\""))
    }
    return nil
  }
  static func text(headers: [String: String], body: Data, depth: Int = 0) -> String {
    let type = (headers["content-type"] ?? "text/plain").lowercased()
    if type.hasPrefix("multipart/"), depth < 5,
      let boundary = parameter("boundary", in: headers["content-type"] ?? "")
    {
      let parts = multipart(body, boundary: boundary)
      var html: String?
      for part in parts {
        let (h, b) = split(part)
        let partHeaders = parseHeaders(h)
        let partType = (partHeaders["content-type"] ?? "text/plain").lowercased()
        if (partHeaders["content-disposition"] ?? "").lowercased().hasPrefix("attachment") { continue }
        if partType.hasPrefix("text/plain") || partType.hasPrefix("multipart/") {
          let value = text(headers: partHeaders, body: b, depth: depth + 1)
          if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
        } else if partType.hasPrefix("text/html"), html == nil {
          html = text(headers: partHeaders, body: b, depth: depth + 1)
        }
      }
      return html ?? ""
    }
    guard type.hasPrefix("text/") else { return "" }
    let decoded = transferDecode(body, encoding: headers["content-transfer-encoding"] ?? "")
    let value = decodeCharset(decoded, charset: parameter("charset", in: headers["content-type"] ?? ""))
    return type.hasPrefix("text/html") ? stripHTML(value) : value
  }
  static func multipart(_ body: Data, boundary: String) -> [Data] {
    let b = [UInt8](body)
    let marker = [UInt8](("--" + boundary).utf8)
    var starts: [Int] = []
    var i = 0
    while i + marker.count <= b.count {
      // A delimiter starts a line.
      if (i == 0 || b[i - 1] == 0x0A), b[i] == marker[0], Array(b[i..<(i + marker.count)]) == marker {
        starts.append(i)
        i += marker.count
      } else {
        i += 1
      }
    }
    var parts: [Data] = []
    for (n, start) in starts.enumerated() {
      var from = start + marker.count
      if from + 1 < b.count, b[from] == 0x2D, b[from + 1] == 0x2D { break }  // closing --
      while from < b.count, b[from] != 0x0A { from += 1 }
      from += 1
      let to = n + 1 < starts.count ? starts[n + 1] : b.count
      if from < to { parts.append(Data(b[from..<to])) }
    }
    return parts
  }
  static func transferDecode(_ data: Data, encoding: String) -> Data {
    switch encoding.lowercased().trimmingCharacters(in: .whitespaces) {
    case "base64":
      var compact = String(decoding: data, as: UTF8.self).filter { !$0.isWhitespace }
      compact = String(compact.prefix(compact.count - compact.count % 4))
      return Data(base64Encoded: compact, options: .ignoreUnknownCharacters) ?? Data()
    case "quoted-printable":
      return quotedPrintable([UInt8](data), underscoreIsSpace: false)
    default:
      return data
    }
  }
  static func quotedPrintable(_ b: [UInt8], underscoreIsSpace: Bool) -> Data {
    var out: [UInt8] = []
    var i = 0
    func hex(_ c: UInt8) -> UInt8? {
      switch c {
      case 0x30...0x39: c - 0x30
      case 0x41...0x46: c - 0x37
      case 0x61...0x66: c - 0x57
      default: nil
      }
    }
    while i < b.count {
      let c = b[i]
      if c == 0x3D {
        if i + 1 < b.count, b[i + 1] == 0x0A {
          i += 2
          continue
        }
        if i + 2 < b.count, b[i + 1] == 0x0D, b[i + 2] == 0x0A {
          i += 3
          continue
        }
        if i + 2 < b.count, let h = hex(b[i + 1]), let l = hex(b[i + 2]) {
          out.append(h << 4 | l)
          i += 3
          continue
        }
      }
      out.append(underscoreIsSpace && c == 0x5F ? 0x20 : c)
      i += 1
    }
    return Data(out)
  }
  static func decodeCharset(_ data: Data, charset: String?) -> String {
    if let charset {
      let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
      if cf != kCFStringEncodingInvalidId {
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        if let value = String(data: data, encoding: encoding) { return value }
      }
    }
    return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
  }
  /// RFC 2047 encoded words, e.g. `=?UTF-8?B?...?=`.
  public static func decodeWords(_ text: String) -> String {
    let pattern = #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
    // Whitespace between adjacent encoded words is not significant.
    let joined = text.replacingOccurrences(
      of: #"\?=\s+=\?"#, with: "?==?", options: .regularExpression)
    var result = ""
    var cursor = joined.startIndex
    for match in regex.matches(in: joined, range: NSRange(joined.startIndex..., in: joined)) {
      guard let range = Range(match.range, in: joined), let cs = Range(match.range(at: 1), in: joined),
        let enc = Range(match.range(at: 2), in: joined), let payload = Range(match.range(at: 3), in: joined)
      else { continue }
      result += joined[cursor..<range.lowerBound]
      let bytes: Data
      if joined[enc].uppercased() == "B" {
        var p = String(joined[payload])
        while p.count % 4 != 0 { p += "=" }
        bytes = Data(base64Encoded: p) ?? Data()
      } else {
        bytes = quotedPrintable([UInt8](joined[payload].utf8), underscoreIsSpace: true)
      }
      result += decodeCharset(bytes, charset: String(joined[cs]))
      cursor = range.upperBound
    }
    result += joined[cursor...]
    return result
  }
  public static func splitAddress(_ from: String) -> (String, String) {
    if let open = from.lastIndex(of: "<"), let close = from.lastIndex(of: ">"), open < close {
      let address = from[from.index(after: open)..<close].trimmingCharacters(in: .whitespaces).lowercased()
      var name = from[..<open].trimmingCharacters(in: .whitespaces)
      name = name.trimmingCharacters(in: .init(charactersIn: "\""))
      return (name.isEmpty ? address : name, address)
    }
    let address = from.trimmingCharacters(in: .whitespaces).lowercased()
    return (address, address)
  }
  static func stripHTML(_ html: String) -> String {
    var text = html.replacingOccurrences(
      of: #"(?is)<(script|style)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
    text = text.replacingOccurrences(of: #"(?i)<br\s*/?>|</p>|</div>"#, with: "\n", options: .regularExpression)
    text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    for (entity, value) in ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"] {
      text = text.replacingOccurrences(of: entity, with: value)
    }
    return text.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #"\n\s*\n+"#, with: "\n\n", options: .regularExpression)
  }
  static func rfc2822Date(_ text: String) -> Date? {
    let cleaned = text.replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespaces)
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z", "EEE, d MMM yy HH:mm:ss Z"] {
      f.dateFormat = format
      if let date = f.date(from: cleaned) { return date }
    }
    return nil
  }
}
