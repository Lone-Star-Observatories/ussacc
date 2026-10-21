import ACCCore
import AppKit
import SwiftUI

/// Developer-only rendering of this app's own view, using demo content and no account access.
@MainActor enum PreviewExporter {
  /// Developer checks run with demo content and must not touch saved session state.
  static var isDevRun: Bool {
    let arguments = ProcessInfo.processInfo.arguments
    return ["--snapshot-dir", "--check-classifier", "--check-terminal", "--probe-imap"].contains(
      where: arguments.contains)
  }
  static func runIfRequested(model: AppModel) async {
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--check-classifier") {
      print(Intelligence.availability)
      for (body, known) in [
        ("Can you confirm our meeting tonight, Allen?", true),
        ("Action required by Friday: your venue contract for the Oct 30 event must be signed or the booking is released.", false),
        ("Receipt for your order #4821: telescope eyepiece, $89.00. Thanks for shopping.", false),
        ("This week's newsletter: 10 stargazing tips and our autumn sale.", false),
        ("CONGRATULATIONS!!! You have been selected for a free cruise. Click here.", false),
        ("Your parcel is delayed. No action needed.", false),
      ] {
        let item = Communication(
          name: "Sample", address: "sample@example.com", channel: .email, body: body, isDemo: true)
        let result = await Intelligence.classify(item, known: known)
        print("CLASSIFIER: \(result.level.map(String.init) ?? "unscored") | \(result.reason)")
      }
      NSApplication.shared.terminate(nil)
      return
    }
    if let index = arguments.firstIndex(of: "--probe-imap"), arguments.indices.contains(index + 1) {
      // Checks TLS, greeting, capabilities and error handling with a deliberately invalid login.
      let host = arguments[index + 1]
      let transport = NetworkIMAPTransport(host: host, port: 993)
      do {
        try await transport.open()
        let session = IMAPSession(transport: transport)
        try await session.greeting()
        print("IMAP: TLS + greeting OK from \(host)")
        print("IMAP: capabilities \(await session.capabilities.sorted().prefix(12).joined(separator: " "))")
        do {
          try await session.login(user: "probe@invalid.example", password: "not-a-password")
          print("IMAP: unexpected login success")
        } catch { print("IMAP: invalid login rejected as expected: \(error.localizedDescription)") }
        await session.logout()
      } catch { print("IMAP: probe failed: \(error.localizedDescription)") }
      NSApplication.shared.terminate(nil)
      return
    }
    if arguments.contains("--check-terminal") {
      let marker = "/private/tmp/ussacc-pty-" + UUID().uuidString
      let session = ShellSession(directory: "/private/tmp")
      session.start()
      try? await Task.sleep(for: .milliseconds(500))
      session.terminal.send(txt: "printf USS_ACC_PTY_OK > " + marker + "\n")
      for _ in 0..<20 {
        if let text = try? String(contentsOfFile: marker, encoding: .utf8), text == "USS_ACC_PTY_OK"
        {
          print("TERMINAL: interactive PTY command passed")
          try? FileManager.default.removeItem(atPath: marker)
          session.stop()
          NSApplication.shared.terminate(nil)
          return
        }
        try? await Task.sleep(for: .milliseconds(250))
      }
      print("TERMINAL: PTY check failed")
      session.stop()
      NSApplication.shared.terminate(nil)
      return
    }
    guard let index = arguments.firstIndex(of: "--snapshot-dir"),
      arguments.indices.contains(index + 1)
    else { return }
    let folder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      model.loadDemo(persist: false)
      guard let window = NSApplication.shared.windows.first(where: { $0.contentView != nil }) else {
        return
      }
      window.setContentSize(NSSize(width: 1450, height: 940))
      for station in Station.allCases {
        model.station = station
        model.settings = false
        try await Task.sleep(for: .milliseconds(650))
        try capture(
          window: window, to: folder.appendingPathComponent(station.rawValue.lowercased() + ".png"))
      }
      model.station = .dev
      model.settings = true
      model.settingsSection = "Spam Filter"
      try await Task.sleep(for: .milliseconds(650))
      try capture(window: window, to: folder.appendingPathComponent("settings.png"))
      model.settingsSection = "Connections"
      try await Task.sleep(for: .milliseconds(650))
      try capture(window: window, to: folder.appendingPathComponent("connections.png"))
      model.settingsSection = "Spam Filter"
      print("Rendered seven USS ACC previews to \(folder.path)")
      NSApplication.shared.terminate(nil)
    } catch {
      fputs("Preview export failed: \(error)\n", stderr)
      NSApplication.shared.terminate(nil)
    }
  }
  private static func capture(window: NSWindow, to url: URL) throws {
    guard let view = window.contentView else { return }
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      throw IntegrationError.message("Cannot render preview bitmap")
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
      throw IntegrationError.message("Cannot encode preview PNG")
    }
    try data.write(to: url, options: .atomic)
  }
}
