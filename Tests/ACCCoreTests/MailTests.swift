import Foundation
import Testing

@testable import ACCCore

/// Replays a scripted server. Each client send consumes one step and queues its reply.
actor ScriptedTransport: IMAPTransport {
  private var steps: [(expect: String, reply: String)]
  private var outbox: [Data]
  private var tag = ""
  private(set) var sent: [String] = []
  init(greeting: String, steps: [(String, String)]) {
    self.outbox = [Data(greeting.utf8)]
    self.steps = steps
  }
  func send(_ data: Data) async throws {
    let text = String(decoding: data, as: UTF8.self)
    sent.append(text)
    if text.hasPrefix("A"), let space = text.firstIndex(of: " ") { tag = String(text[..<space]) }
    guard !steps.isEmpty else { return }
    let step = steps.removeFirst()
    #expect(text.contains(step.expect), "expected \(step.expect) in \(text)")
    outbox.append(Data(step.reply.replacingOccurrences(of: "TAG", with: tag).utf8))
  }
  func receive() async throws -> Data { outbox.isEmpty ? Data() : outbox.removeFirst() }
  func close() async {}
  var remaining: Int { steps.count }
}

let sampleMessage = """
  From: =?UTF-8?B?SmFtaWUgUml2ZXJh?= <Jamie@Example.com>\r
  To: allen@example.com\r
  Subject: =?UTF-8?Q?Tonight_at_the_observatory_=F0=9F=94=AD?=\r
  Date: Sat, 17 Oct 2026 14:10:00 -0500 (CDT)\r
  MIME-Version: 1.0\r
  Content-Type: multipart/alternative; boundary="b1"\r
  \r
  --b1\r
  Content-Type: text/plain; charset=utf-8\r
  Content-Transfer-Encoding: quoted-printable\r
  \r
  Shall we meet at eight? Can you con=\r
  firm? Caf=C3=A9 after.\r
  --b1\r
  Content-Type: text/html; charset=utf-8\r
  \r
  <p>HTML version</p>\r
  --b1--\r

  """

@Suite struct MailTests {
  @Test func parserHandlesListsQuotedLiteralsAndBracketCodes() {
    let line = Data(
      "* 2 FETCH (UID 41 FLAGS (\\Seen) INTERNALDATE \"17-Oct-2026 14:10:00 -0500\" BODY[]<0> {5}\r\nhello X-GM NIL)\r\n"
        .utf8)
    let tokens = IMAPParser.parse(line)
    #expect(tokens[0] == .atom("*"))
    #expect(tokens[2] == .atom("FETCH"))
    let items = tokens[3].items
    #expect(items[1] == .atom("41"))
    #expect(items[3].items == [.atom("\\Seen")])
    #expect(items[5].text == "17-Oct-2026 14:10:00 -0500")
    #expect(items[6] == .atom("BODY[]<0>"))
    #expect(items[7] == .string(Data("hello".utf8)))
    #expect(items[9] == .null)
    let ok = IMAPParser.parse(Data("* OK [UIDVALIDITY 3857529045] UIDs valid\r\n".utf8))
    #expect(ok[2] == .atom("[UIDVALIDITY 3857529045]"))
    #expect(IMAPParser.quoted("a\"b\\c") == "\"a\\\"b\\\\c\"")
    #expect(IMAPParser.quoted("pässword") == nil)
  }

  @Test func framerWaitsForCompleteLiterals() {
    var framer = IMAPFramer()
    framer.append(Data("* 1 FETCH (BODY[] {10}\r\n12345".utf8))
    #expect(framer.next() == nil)
    framer.append(Data("67890)\r\nA1 OK done\r\n".utf8))
    #expect(framer.next() == Data("* 1 FETCH (BODY[] {10}\r\n1234567890)\r\n".utf8))
    #expect(framer.next() == Data("A1 OK done\r\n".utf8))
    #expect(framer.next() == nil)
  }

  @Test func gmailStyleSessionReadsInboxAndMovesToTrashWithoutExpunge() async throws {
    let body = sampleMessage
    let transport = ScriptedTransport(
      greeting: "* OK [CAPABILITY IMAP4rev1 LITERAL+ AUTH=PLAIN] Gimap ready\r\n",
      steps: [
        (
          "LOGIN \"allen@gmail.com\" \"abcd efgh\"",
          "* CAPABILITY IMAP4rev1 UIDPLUS MOVE SPECIAL-USE\r\nTAG OK allen@gmail.com authenticated (Success)\r\n"
        ),
        (
          "EXAMINE \"INBOX\"",
          "* 3 EXISTS\r\n* OK [UIDVALIDITY 7] UIDs valid.\r\nTAG OK [READ-ONLY] INBOX selected.\r\n"
        ),
        (
          "FETCH 2:3 (UID INTERNALDATE BODY.PEEK[]<0.24000>)",
          "* 2 FETCH (UID 40 INTERNALDATE \"16-Oct-2026 09:00:00 +0000\" BODY[]<0> {12}\r\nSubject: hi\n)\r\n"
            + "* 3 FETCH (UID 41 INTERNALDATE \"17-Oct-2026 19:10:00 +0000\" BODY[]<0> {\(body.utf8.count)}\r\n\(body))\r\n"
            + "TAG OK Success\r\n"
        ),
        (
          "LIST \"\" \"*\"",
          "* LIST (\\HasNoChildren) \"/\" \"INBOX\"\r\n* LIST (\\HasNoChildren \\Trash) \"/\" \"[Gmail]/Trash\"\r\nTAG OK Success\r\n"
        ),
        ("SELECT \"INBOX\"", "* 3 EXISTS\r\n* OK [UIDVALIDITY 7] UIDs valid.\r\nTAG OK [READ-WRITE] INBOX selected.\r\n"),
        ("UID MOVE 41 \"[Gmail]/Trash\"", "TAG OK [COPYUID 9 41 12] (Success)\r\n"),
      ])
    let session = IMAPSession(transport: transport)
    try await session.greeting()
    try await session.login(user: "allen@gmail.com", password: "abcd efgh")
    #expect(await session.capabilities.contains("MOVE"))
    let inbox = try await session.select()
    #expect(inbox.exists == 3 && inbox.uidValidity == 7)
    let messages = try await session.fetchLatest(exists: inbox.exists, count: 2)
    #expect(messages.map(\.uid) == [41, 40])
    #expect(messages[0].internalDate != nil)
    let parsed = MailParser.parse(messages[0].raw)
    #expect(parsed.fromName == "Jamie Rivera")
    #expect(parsed.fromAddress == "jamie@example.com")
    #expect(parsed.subject == "Tonight at the observatory 🔭")
    #expect(parsed.body.hasPrefix("Shall we meet at eight? Can you confirm? Café after."))
    #expect(parsed.date != nil)
    try await session.moveToTrash(uid: 41, uidValidity: 7)
    #expect(await transport.remaining == 0)
    #expect(await transport.sent.allSatisfy { !$0.uppercased().contains("EXPUNGE") })
  }

  @Test func nonASCIIPasswordUsesLiteralAndRejectionsSurfaceServerText() async throws {
    let transport = ScriptedTransport(
      greeting: "* OK [CAPABILITY IMAP4rev1] ready\r\n",
      steps: [
        ("LOGIN \"u\" {9}\r\n", "+ go ahead\r\n"),
        ("pässword\r\n", "TAG NO [AUTHENTICATIONFAILED] Invalid credentials\r\n"),
      ])
    let session = IMAPSession(transport: transport)
    try await session.greeting()
    await #expect(throws: IMAPError.server("Invalid credentials")) {
      try await session.login(user: "u", password: "pässword")
    }
  }

  @Test func withoutMoveCopiesAndFlagsButNeverExpunges() async throws {
    let transport = ScriptedTransport(
      greeting: "* OK [CAPABILITY IMAP4rev1] ready\r\n",
      steps: [
        ("LIST", "* LIST () \".\" \"INBOX\"\r\n* LIST () \".\" \"INBOX.Trash\"\r\nTAG OK\r\n"),
        ("SELECT", "* OK [UIDVALIDITY 5] ok\r\nTAG OK\r\n"),
        ("UID COPY 9 \"INBOX.Trash\"", "TAG OK\r\n"),
        ("UID STORE 9 +FLAGS.SILENT (\\Deleted)", "TAG OK\r\n"),
      ])
    let session = IMAPSession(transport: transport)
    try await session.greeting()
    try await session.moveToTrash(uid: 9, uidValidity: 5)
    #expect(await transport.remaining == 0)
  }

  @Test func batchMoveUsesOneUIDSet() async throws {
    let transport = ScriptedTransport(
      greeting: "* OK [CAPABILITY IMAP4rev1 MOVE] ready\r\n",
      steps: [
        ("LIST", "* LIST (\\Trash) \"/\" \"Trash\"\r\nTAG OK\r\n"),
        ("SELECT", "* OK [UIDVALIDITY 3] ok\r\nTAG OK\r\n"),
        ("UID MOVE 4,7,9 \"Trash\"", "TAG OK\r\n"),
      ])
    let session = IMAPSession(transport: transport)
    try await session.greeting()
    try await session.moveToTrash(uids: [4, 7, 9], uidValidity: 3)
    #expect(await transport.remaining == 0)
  }

  @Test func changedUIDValidityKeepsMessage() async throws {
    let transport = ScriptedTransport(
      greeting: "* OK ready\r\n",
      steps: [
        ("LIST", "* LIST (\\Trash) \"/\" \"Trash\"\r\nTAG OK\r\n"),
        ("SELECT", "* OK [UIDVALIDITY 99] ok\r\nTAG OK\r\n"),
      ])
    let session = IMAPSession(transport: transport)
    try await session.greeting()
    await #expect(throws: IMAPError.self) { try await session.moveToTrash(uid: 1, uidValidity: 5) }
  }

  @Test func htmlOnlyAndLatin1BodiesDecode() {
    let html = Data(
      "From: shop@example.com\r\nContent-Type: text/html; charset=iso-8859-1\r\n\r\n<p>Order&nbsp;shipped</p><style>x{}</style>"
        .utf8)
    #expect(MailParser.parse(html).body == "Order shipped")
    var latin = Data("From: a@b.c\r\nContent-Type: text/plain; charset=iso-8859-1\r\n\r\nCaf".utf8)
    latin.append(0xE9)
    #expect(MailParser.parse(latin).body == "Café")
    #expect(MailParser.splitAddress("plain@example.com") == ("plain@example.com", "plain@example.com"))
  }

  @Test func providersAndValidation() {
    #expect(MailProvider.detect(host: "imap.gmail.com", email: "x@company.com") == .gmail)
    #expect(MailProvider.detect(host: "", email: "x@icloud.com") == .icloud)
    #expect(MailProvider.detect(host: "mail.example.org", email: "x@example.org") == .imap)
    let gmail = MailAccount(provider: .gmail, email: "allen@gmail.com")
    #expect(gmail.host == "imap.gmail.com" && gmail.username == "allen@gmail.com")
    #expect(gmail.validationError == nil)
    #expect(MailAccount(provider: .imap, email: "a@b.c", host: "h", port: 143).validationError != nil)
  }

  @Test func eachSourceGetsItsOwnBaseline() throws {
    var ledger = IntakeLedger()
    #expect(ledger.receive(["mail:1"]).isEmpty)
    #expect(ledger.receive(["mail:1", "mail:2"]) == ["mail:2"])
    // A newly added account's existing mail is baseline, not arrivals.
    #expect(ledger.receive(["imap:a:7:1", "imap:a:7:2"], source: "imap:a:7").isEmpty)
    #expect(ledger.receive(["imap:a:7:3"], source: "imap:a:7") == ["imap:a:7:3"])
    // A UIDVALIDITY reset is a new source generation and re-baselines.
    #expect(ledger.receive(["imap:a:8:1"], source: "imap:a:8").isEmpty)
    // Older ledgers without baselinedSources still treat Apple Mail as baselined.
    let legacy = Data(#"{"baselineEstablished":true,"seenIDs":["mail:1"],"quarantinedIDs":[],"classifications":{}}"#.utf8)
    var restored = try JSONDecoder().decode(IntakeLedger.self, from: legacy)
    #expect(restored.receive(["mail:1", "mail:9"]) == ["mail:9"])
  }
}
