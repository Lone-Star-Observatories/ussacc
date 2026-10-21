import Foundation
import Testing

@testable import ACCCore

@Suite struct StoreTests {
  func temporaryStore() throws -> (MessageStore, URL) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let url = folder.appendingPathComponent("messages.sqlite")
    return (try MessageStore(url: url), folder)
  }
  func message(_ id: String, _ subject: String, body: String = "", minutesAgo: Double = 0)
    -> Communication
  {
    Communication(
      id: id, name: "Jamie Rivera", address: "jamie@example.com", channel: .email,
      subject: subject, body: body, date: .now.addingTimeInterval(-minutesAgo * 60))
  }

  @Test func storesSurvivesReopenAndKeepsLocalStateOnReinsert() throws {
    let (store, folder) = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: folder) }
    try store.insert(
      [message("imap:a:1:2", "Second", minutesAgo: 1), message("imap:a:1:1", "First", minutesAgo: 5)],
      source: "imap:a:1")
    try store.updateState(
      id: "imap:a:1:2",
      classification: .some(.init(level: 2, reason: "Newsletter", source: "Apple Intelligence")),
      quarantined: true)
    // A later poll returning the same message must not wipe local state.
    try store.insert([message("imap:a:1:2", "Second")], source: "imap:a:1")
    let reopened = try MessageStore(url: store.url)
    let rows = try reopened.recent()
    #expect(rows.map(\.id) == ["imap:a:1:2", "imap:a:1:1"])
    #expect(rows[0].classification?.level == 2 && rows[0].quarantined)
    #expect(try reopened.count() == 2)
    #expect(try reopened.message(id: "imap:a:1:1")?.subject == "First")
    #expect(try reopened.message(id: "missing") == nil)
    let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
    #expect((attributes[.posixPermissions] as? Int) == 0o600)
  }

  @Test func fullTextSearchAndTrashAndDemoExclusion() throws {
    let (store, folder) = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: folder) }
    var demo = message("demo-1", "Telescope demo")
    demo.isDemo = true
    try store.insert(
      [message("m1", "Observatory session", body: "Bring the narrowband filter"),
       message("m2", "Invoice", body: "Payment received"), demo], source: "applemail")
    #expect(try store.search("narrow").map(\.id) == ["m1"])
    #expect(try store.search("jamie observ").map(\.id) == ["m1"])
    #expect(try store.search("telescope").isEmpty)
    try store.updateState(id: "m2", trashed: true)
    #expect(try store.recent().map(\.id) == ["m1"])
    #expect(try store.search("payment").isEmpty)
    #expect(try store.search("\" OR 1=1 --").isEmpty)
  }

  @Test func syncStateAndAccountRemoval() throws {
    let (store, folder) = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(try store.syncState(account: "a") == nil)
    let state = MessageStore.SyncState(uidValidity: 7, highestUID: 120, lowestUID: 80)
    try store.setSyncState(state, account: "a")
    #expect(try store.syncState(account: "a") == state)
    try store.insert([message("imap:a:7:1", "x")], source: "imap:a:7")
    try store.insert([message("imap:ab:7:1", "y")], source: "imap:ab:7")
    try store.delete(sourcePrefix: "imap:a:")
    #expect(try store.recent().map(\.id) == ["imap:ab:7:1"])
    try store.setSyncState(nil, account: "a")
    #expect(try store.syncState(account: "a") == nil)
  }

  @Test func rollingArchiveKeepsSearchAndRestoresOnRetrieval() throws {
    let (store, folder) = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: folder) }
    let longBody = String(repeating: "Equatorial mount alignment notes. ", count: 200)
    try store.insert(
      [message("imap:acct:7:1", "Old mount notes", body: longBody, minutesAgo: 60 * 24 * 20),
       message("imap:acct:7:2", "Fresh", body: "Tonight", minutesAgo: 60)], source: "imap:acct:7")
    let cutoff = Date.now.addingTimeInterval(-14 * 86400)
    #expect(try store.archive(olderThan: cutoff) == ["imap:acct:7:1"])
    #expect(try store.archive(olderThan: cutoff).isEmpty)
    let rows = try store.recent()
    let old = try #require(rows.first { $0.id == "imap:acct:7:1" })
    #expect(old.archived && old.body.isEmpty && old.subject == "Old mount notes")
    // Still found by body text via the index.
    #expect(try store.search("equatorial").map(\.id) == ["imap:acct:7:1"])
    let pack = store.archiveRoot.appendingPathComponent("acct")
    #expect(FileManager.default.fileExists(atPath: pack.path))
    #expect(store.archiveSize > 0 && store.archiveSize < Int64(longBody.utf8.count))
    // Peek without restoring, then retrieve.
    #expect(try store.body(id: "imap:acct:7:1", restore: false) == longBody)
    #expect(try store.recent().first { $0.id == "imap:acct:7:1" }?.archived == true)
    #expect(try store.body(id: "imap:acct:7:1", restore: true) == longBody)
    let restored = try #require(try store.recent().first { $0.id == "imap:acct:7:1" })
    #expect(!restored.archived && restored.body == longBody)
    // Retrieved mail stays hot for a new window, then re-archives without rewriting the pack.
    #expect(try store.archive(olderThan: cutoff).isEmpty)
    let size = store.archiveSize
    #expect(try store.archive(olderThan: .now.addingTimeInterval(60)).count == 2)
    #expect(try store.body(id: "imap:acct:7:1", restore: false) == longBody)
    #expect(try store.body(id: "imap:acct:7:2", restore: false) == "Tonight")
    #expect(store.archiveSize > size)
    store.deleteArchive(key: "acct")
    #expect(!FileManager.default.fileExists(atPath: pack.path))
    #expect(MessageStore.archiveKey(source: "applemail") == "applemail")
  }

  @Test func backfillIsSeenButNotArrival() {
    var ledger = IntakeLedger()
    _ = ledger.receive(["imap:a:7:100"], source: "imap:a:7")
    ledger.markSeen(["imap:a:7:50", "imap:a:7:51"])
    #expect(ledger.receive(["imap:a:7:51", "imap:a:7:101"], source: "imap:a:7") == ["imap:a:7:101"])
  }
}
