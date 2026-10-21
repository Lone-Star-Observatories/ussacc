import Foundation
import SQLite3

/// Local copy of downloaded communications (SQLite with full-text search).
/// The file is created user-readable only. Demo items are never stored.
public final class MessageStore: @unchecked Sendable {
  public struct SyncState: Equatable, Sendable {
    public var uidValidity: UInt32
    public var highestUID: UInt32
    public var lowestUID: UInt32
    public init(uidValidity: UInt32, highestUID: UInt32, lowestUID: UInt32) {
      self.uidValidity = uidValidity
      self.highestUID = highestUID
      self.lowestUID = lowestUID
    }
  }
  public enum StoreError: LocalizedError {
    case sqlite(String)
    public var errorDescription: String? {
      if case .sqlite(let message) = self { return "Message store: \(message)" }
      return nil
    }
  }
  private var db: OpaquePointer?
  private let lock = NSLock()
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  public let url: URL

  public init(url: URL) throws {
    self.url = url
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
      == SQLITE_OK
    else {
      let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
      sqlite3_close(db)
      throw StoreError.sqlite(message)
    }
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    try exec(
      """
      PRAGMA journal_mode=WAL;
      PRAGMA foreign_keys=ON;
      CREATE TABLE IF NOT EXISTS messages(
        id TEXT PRIMARY KEY, source TEXT NOT NULL, date REAL NOT NULL, name TEXT NOT NULL,
        address TEXT NOT NULL, channel TEXT NOT NULL, subject TEXT NOT NULL, body TEXT NOT NULL,
        classification BLOB, quarantined INTEGER NOT NULL DEFAULT 0,
        trashed INTEGER NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0,
        restored_at REAL NOT NULL DEFAULT 0, archive_file TEXT, archive_offset INTEGER,
        archive_length INTEGER);
      CREATE INDEX IF NOT EXISTS messages_date ON messages(date DESC);
      CREATE INDEX IF NOT EXISTS messages_source ON messages(source);
      CREATE INDEX IF NOT EXISTS messages_hot ON messages(archived, date);
      -- Contentless index: archived text stays searchable without a second plain-text copy.
      CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
        name, address, subject, body, content='', contentless_delete=1);
      CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
        INSERT INTO messages_fts(rowid, name, address, subject, body)
        VALUES (new.rowid, new.name, new.address, new.subject, new.body); END;
      CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
        DELETE FROM messages_fts WHERE rowid = old.rowid; END;
      CREATE TABLE IF NOT EXISTS sync_state(
        account TEXT PRIMARY KEY, uid_validity INTEGER NOT NULL, highest_uid INTEGER NOT NULL,
        lowest_uid INTEGER NOT NULL);
      """)
  }
  deinit { sqlite3_close(db) }

  // MARK: Messages

  /// Inserts new messages. Existing rows keep their local state (score, quarantine, trash).
  public func insert(_ items: [Communication], source: String) throws {
    try locked {
      try exec("BEGIN")
      do {
        let statement = try prepare(
          """
          INSERT INTO messages(id, source, date, name, address, channel, subject, body, classification, quarantined, trashed)
          VALUES (?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO NOTHING
          """)
        defer { sqlite3_finalize(statement) }
        for item in items where !item.isDemo {
          sqlite3_reset(statement)
          bind(statement, 1, item.id)
          bind(statement, 2, source)
          sqlite3_bind_double(statement, 3, item.date.timeIntervalSince1970)
          bind(statement, 4, item.name)
          bind(statement, 5, item.address)
          bind(statement, 6, item.channel.rawValue)
          bind(statement, 7, item.subject)
          bind(statement, 8, item.body)
          bindClassification(statement, 9, item.classification)
          sqlite3_bind_int(statement, 10, item.quarantined ? 1 : 0)
          sqlite3_bind_int(statement, 11, item.trashed ? 1 : 0)
          guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
        }
        try exec("COMMIT")
      } catch {
        try? exec("ROLLBACK")
        throw error
      }
    }
  }
  public func updateState(
    id: String, classification: Classification?? = nil, quarantined: Bool? = nil,
    trashed: Bool? = nil
  ) throws {
    try locked {
      if let classification {
        let s = try prepare("UPDATE messages SET classification=? WHERE id=?")
        defer { sqlite3_finalize(s) }
        bindClassification(s, 1, classification)
        bind(s, 2, id)
        guard sqlite3_step(s) == SQLITE_DONE else { throw error() }
      }
      for (column, value) in [("quarantined", quarantined), ("trashed", trashed)] {
        guard let value else { continue }
        let s = try prepare("UPDATE messages SET \(column)=? WHERE id=?")
        defer { sqlite3_finalize(s) }
        sqlite3_bind_int(s, 1, value ? 1 : 0)
        bind(s, 2, id)
        guard sqlite3_step(s) == SQLITE_DONE else { throw error() }
      }
    }
  }
  /// Newest messages first.
  public func recent(limit: Int = 2000, includeTrashed: Bool = false) throws -> [Communication] {
    try query(
      "SELECT \(Self.columns) FROM messages \(includeTrashed ? "" : "WHERE trashed=0") ORDER BY date DESC LIMIT ?"
    ) { sqlite3_bind_int($0, 1, Int32(limit)) }
  }
  public func message(id: String) throws -> Communication? {
    try query("SELECT \(Self.columns) FROM messages WHERE id=?") { self.bind($0, 1, id) }.first
  }
  /// Full-text search over sender, subject and body.
  public func search(_ text: String, limit: Int = 500) throws -> [Communication] {
    let terms = text.split(whereSeparator: \.isWhitespace).map {
      "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*"
    }
    guard !terms.isEmpty else { return [] }
    return try query(
      """
      SELECT \(Self.columns.split(separator: ",").map { "m." + $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", "))
      FROM messages_fts f JOIN messages m ON m.rowid = f.rowid
      WHERE messages_fts MATCH ? AND m.trashed = 0 ORDER BY m.date DESC LIMIT ?
      """
    ) {
      self.bind($0, 1, terms.joined(separator: " "))
      sqlite3_bind_int($0, 2, Int32(limit))
    }
  }
  public func delete(sourcePrefix: String) throws {
    try locked {
      let s = try prepare("DELETE FROM messages WHERE source LIKE ? ESCAPE '\\'")
      defer { sqlite3_finalize(s) }
      let escaped = sourcePrefix.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
      bind(s, 1, escaped + "%")
      guard sqlite3_step(s) == SQLITE_DONE else { throw error() }
    }
  }
  public func count() throws -> Int {
    try locked {
      let s = try prepare("SELECT COUNT(*) FROM messages")
      defer { sqlite3_finalize(s) }
      return sqlite3_step(s) == SQLITE_ROW ? Int(sqlite3_column_int64(s, 0)) : 0
    }
  }
  /// Bytes on disk including the write-ahead log.
  public var fileSize: Int64 {
    [url.path, url.path + "-wal"].reduce(0) {
      $0 + ((try? FileManager.default.attributesOfItem(atPath: $1)[.size] as? Int64) ?? 0)
    }
  }

  // MARK: Archive

  /// Folder holding per-account `YYYY-MM.pack` files of LZFSE-compressed bodies.
  public var archiveRoot: URL { url.deletingLastPathComponent().appendingPathComponent("archive") }
  /// Archive folder key for a message source: the IMAP account id, or `applemail`.
  public static func archiveKey(source: String) -> String {
    let parts = source.split(separator: ":")
    return parts.first == "imap" && parts.count > 1 ? String(parts[1]) : String(parts.first ?? "other")
  }
  /// Moves bodies of messages older than `cutoff` (and not retrieved since) into archive packs.
  /// Returns the archived ids. Metadata, scores and the search index stay in the database.
  @discardableResult public func archive(olderThan cutoff: Date) throws -> [String] {
    try locked {
      let select = try prepare(
        """
        SELECT rowid, id, source, date, body, archive_file FROM messages
        WHERE archived = 0 AND MAX(date, restored_at) < ? LIMIT 2000
        """)
      defer { sqlite3_finalize(select) }
      sqlite3_bind_double(select, 1, cutoff.timeIntervalSince1970)
      struct Row { var rowid: Int64; var id, source, body: String; var date: Date; var packed: Bool }
      var rows: [Row] = []
      while sqlite3_step(select) == SQLITE_ROW {
        rows.append(
          Row(
            rowid: sqlite3_column_int64(select, 0), id: text(select, 1), source: text(select, 2),
            body: text(select, 4), date: Date(timeIntervalSince1970: sqlite3_column_double(select, 3)),
            packed: sqlite3_column_type(select, 5) != SQLITE_NULL))
      }
      guard !rows.isEmpty else { return [] }
      let month = DateFormatter()
      month.locale = Locale(identifier: "en_US_POSIX")
      month.dateFormat = "yyyy-MM"
      var handles: [String: FileHandle] = [:]
      defer { handles.values.forEach { try? $0.close() } }
      try exec("BEGIN")
      do {
        let pointer = try prepare(
          """
          UPDATE messages SET body='', archived=1, archive_file=?, archive_offset=?, archive_length=?
          WHERE rowid=?
          """)
        defer { sqlite3_finalize(pointer) }
        let clear = try prepare("UPDATE messages SET body='', archived=1 WHERE rowid=?")
        defer { sqlite3_finalize(clear) }
        for row in rows {
          if row.packed {
            // Already in a pack from an earlier archive; retrieval only copied it back.
            sqlite3_reset(clear)
            sqlite3_bind_int64(clear, 1, row.rowid)
            guard sqlite3_step(clear) == SQLITE_DONE else { throw error() }
            continue
          }
          let relative = "\(Self.archiveKey(source: row.source))/\(month.string(from: row.date)).pack"
          let handle = try handles[relative] ?? openPack(relative)
          handles[relative] = handle
          let compressed = try (Data(row.body.utf8) as NSData).compressed(using: .lzfse) as Data
          let offset = try handle.seekToEnd()
          try handle.write(contentsOf: compressed)
          sqlite3_reset(pointer)
          bind(pointer, 1, relative)
          sqlite3_bind_int64(pointer, 2, Int64(offset))
          sqlite3_bind_int64(pointer, 3, Int64(compressed.count))
          sqlite3_bind_int64(pointer, 4, row.rowid)
          guard sqlite3_step(pointer) == SQLITE_DONE else { throw error() }
        }
        try handles.values.forEach { try $0.synchronize() }
        try exec("COMMIT")
      } catch {
        try? exec("ROLLBACK")
        throw error
      }
      return rows.map(\.id)
    }
  }
  /// Body for a message, reading archived ones from their pack. With `restore`, the body is
  /// written back to the database and stays hot for another window.
  public func body(id: String, restore: Bool) throws -> String? {
    try locked {
      let s = try prepare(
        "SELECT body, archived, archive_file, archive_offset, archive_length FROM messages WHERE id=?")
      defer { sqlite3_finalize(s) }
      bind(s, 1, id)
      guard sqlite3_step(s) == SQLITE_ROW else { return nil }
      guard sqlite3_column_int(s, 1) != 0 else { return text(s, 0) }
      guard sqlite3_column_type(s, 2) != SQLITE_NULL else { return "" }
      let file = archiveRoot.appendingPathComponent(text(s, 2))
      let handle = try FileHandle(forReadingFrom: file)
      defer { try? handle.close() }
      try handle.seek(toOffset: UInt64(sqlite3_column_int64(s, 3)))
      let compressed = try handle.read(upToCount: Int(sqlite3_column_int64(s, 4))) ?? Data()
      let data = try (compressed as NSData).decompressed(using: .lzfse) as Data
      let body = String(decoding: data, as: UTF8.self)
      if restore {
        let update = try prepare("UPDATE messages SET body=?, archived=0, restored_at=? WHERE id=?")
        defer { sqlite3_finalize(update) }
        bind(update, 1, body)
        sqlite3_bind_double(update, 2, Date.now.timeIntervalSince1970)
        bind(update, 3, id)
        guard sqlite3_step(update) == SQLITE_DONE else { throw error() }
      }
      return body
    }
  }
  public func archivedCount() throws -> Int {
    try locked {
      let s = try prepare("SELECT COUNT(*) FROM messages WHERE archived=1")
      defer { sqlite3_finalize(s) }
      return sqlite3_step(s) == SQLITE_ROW ? Int(sqlite3_column_int64(s, 0)) : 0
    }
  }
  /// Removes an account's archive packs (used when the account is removed).
  public func deleteArchive(key: String) {
    try? FileManager.default.removeItem(at: archiveRoot.appendingPathComponent(key))
  }
  public var archiveSize: Int64 {
    guard let files = FileManager.default.enumerator(at: archiveRoot, includingPropertiesForKeys: [.fileSizeKey])
    else { return 0 }
    return files.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }
      .reduce(0) { $0 + Int64($1) }
  }
  private func openPack(_ relative: String) throws -> FileHandle {
    let file = archiveRoot.appendingPathComponent(relative)
    let manager = FileManager.default
    try manager.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    if !manager.fileExists(atPath: file.path) {
      guard manager.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
      else { throw StoreError.sqlite("cannot create archive \(relative)") }
    }
    return try FileHandle(forWritingTo: file)
  }

  // MARK: IMAP sync state

  public func syncState(account: String) throws -> SyncState? {
    try locked {
      let s = try prepare("SELECT uid_validity, highest_uid, lowest_uid FROM sync_state WHERE account=?")
      defer { sqlite3_finalize(s) }
      bind(s, 1, account)
      guard sqlite3_step(s) == SQLITE_ROW else { return nil }
      return SyncState(
        uidValidity: UInt32(sqlite3_column_int64(s, 0)), highestUID: UInt32(sqlite3_column_int64(s, 1)),
        lowestUID: UInt32(sqlite3_column_int64(s, 2)))
    }
  }
  public func setSyncState(_ state: SyncState?, account: String) throws {
    try locked {
      guard let state else {
        let s = try prepare("DELETE FROM sync_state WHERE account=?")
        defer { sqlite3_finalize(s) }
        bind(s, 1, account)
        guard sqlite3_step(s) == SQLITE_DONE else { throw error() }
        return
      }
      let s = try prepare(
        """
        INSERT INTO sync_state(account, uid_validity, highest_uid, lowest_uid) VALUES (?,?,?,?)
        ON CONFLICT(account) DO UPDATE SET uid_validity=excluded.uid_validity,
          highest_uid=excluded.highest_uid, lowest_uid=excluded.lowest_uid
        """)
      defer { sqlite3_finalize(s) }
      bind(s, 1, account)
      sqlite3_bind_int64(s, 2, Int64(state.uidValidity))
      sqlite3_bind_int64(s, 3, Int64(state.highestUID))
      sqlite3_bind_int64(s, 4, Int64(state.lowestUID))
      guard sqlite3_step(s) == SQLITE_DONE else { throw error() }
    }
  }

  // MARK: SQLite helpers

  private static let columns =
    "id, date, name, address, channel, subject, body, classification, quarantined, trashed, archived"
  private func query(_ sql: String, bind binder: (OpaquePointer) -> Void) throws -> [Communication] {
    try locked {
      let s = try prepare(sql)
      defer { sqlite3_finalize(s) }
      binder(s)
      var rows: [Communication] = []
      while sqlite3_step(s) == SQLITE_ROW {
        var item = Communication(
          id: text(s, 0), name: text(s, 2), address: text(s, 3),
          channel: Channel(rawValue: text(s, 4)) ?? .email, subject: text(s, 5), body: text(s, 6),
          date: Date(timeIntervalSince1970: sqlite3_column_double(s, 1)))
        if let blob = sqlite3_column_blob(s, 7) {
          let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(s, 7)))
          item.classification = try? decoder.decode(Classification.self, from: data)
        }
        item.quarantined = sqlite3_column_int(s, 8) != 0
        item.trashed = sqlite3_column_int(s, 9) != 0
        item.archived = sqlite3_column_int(s, 10) != 0
        rows.append(item)
      }
      return rows
    }
  }
  private func locked<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
  private func exec(_ sql: String) throws {
    var message: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
      let text = message.map { String(cString: $0) } ?? "exec failed"
      sqlite3_free(message)
      throw StoreError.sqlite(text)
    }
  }
  private func prepare(_ sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw error()
    }
    return statement
  }
  private func bind(_ s: OpaquePointer, _ index: Int32, _ value: String) {
    sqlite3_bind_text(s, index, value, -1, Self.transient)
  }
  private func bindClassification(_ s: OpaquePointer, _ index: Int32, _ value: Classification?) {
    guard let value, let data = try? encoder.encode(value) else {
      sqlite3_bind_null(s, index)
      return
    }
    _ = data.withUnsafeBytes { sqlite3_bind_blob(s, index, $0.baseAddress, Int32(data.count), Self.transient) }
  }
  private func text(_ s: OpaquePointer, _ column: Int32) -> String {
    sqlite3_column_text(s, column).map { String(cString: $0) } ?? ""
  }
  private func error() -> StoreError { .sqlite(String(cString: sqlite3_errmsg(db))) }
}
