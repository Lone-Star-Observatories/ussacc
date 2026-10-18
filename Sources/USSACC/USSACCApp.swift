import SwiftUI

@main struct USSACCApp: App {
  @StateObject private var model = AppModel()
  @StateObject private var shells = TerminalSessions()
  var body: some Scene {
    WindowGroup("USS ACC · Allen Control Center") {
      ControlCenter().environmentObject(model).environmentObject(shells).preferredColorScheme(.dark)
        .task { await PreviewExporter.runIfRequested(model: model) }
    }.defaultSize(width: 1450, height: 940)
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
