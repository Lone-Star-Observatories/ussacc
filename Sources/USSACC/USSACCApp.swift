import AppKit
import SwiftUI

/// Closing the window quits the app; nothing lingers in the Dock.
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct USSACCApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var model = AppModel()
  @StateObject private var shells = TerminalSessions()
  @StateObject private var psyart = PsyartModel()
  @StateObject private var sdr = SDRController()
  var body: some Scene {
    Window("USS ACC · Allen Control Center", id: "main") {
      ControlCenter().environmentObject(model).environmentObject(shells).environmentObject(psyart)
        .environmentObject(sdr).preferredColorScheme(.dark)
        .task {
          if !PreviewExporter.isDevRun {
            model.restoreSession()
            sdr.start()
          }
          await PreviewExporter.runIfRequested(model: model, psyart: psyart)
        }
    }.windowStyle(.hiddenTitleBar).defaultSize(width: 1450, height: 940)
      .commands {
        CommandMenu("Stations") {
          ForEach(Array(Station.allCases.enumerated()), id: \.element) { index, station in
            Button(station.rawValue) { model.station = station }.keyboardShortcut(
              KeyEquivalent(Character(String(index + 1))), modifiers: .command)
          }
        }
        CommandGroup(replacing: .appSettings) {
          Button("Settings…") {
            model.station = .dev
            model.settings = true
          }.keyboardShortcut(",", modifiers: .command)
        }
      }
  }
}
