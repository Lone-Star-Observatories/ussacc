import ACCCore
import AppKit
import SwiftUI

/// Developer-only rendering of this app's own view, using demo content and no account access.
@MainActor enum PreviewExporter {
  static func runIfRequested(model: AppModel) async {
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--check-classifier") {
      print(Intelligence.availability)
      for (body, known) in [
        ("Can you confirm our meeting tonight, Allen?", true),
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
      model.loadDemo()
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
      try await Task.sleep(for: .milliseconds(650))
      try capture(window: window, to: folder.appendingPathComponent("settings.png"))
      print("Rendered six USS ACC previews to \(folder.path)")
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
