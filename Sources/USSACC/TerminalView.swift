import AppKit
import SwiftTerm
import SwiftUI

@MainActor final class ShellSession: ObservableObject, Identifiable {
  let id = UUID()
  let directory: String
  @Published var title = "Local / zsh"
  let terminal: LocalProcessTerminalView
  private var started = false
  init(directory: String) {
    self.directory = directory
    terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 550))
    terminal.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    terminal.nativeBackgroundColor = .black
    terminal.nativeForegroundColor = NSColor(red: 0.78, green: 0.84, blue: 0.96, alpha: 1)
  }
  func start() {
    guard !started else { return }
    started = true
    terminal.startProcess(
      executable: "/bin/zsh", args: ["-l"], environment: nil, execName: "-zsh",
      currentDirectory: directory)
  }
  func stop() { terminal.terminate() }
}
@MainActor final class TerminalSessions: ObservableObject {
  @Published var sessions: [ShellSession] = []
  @Published var selected: UUID?
  func add(directory: String = FileManager.default.homeDirectoryForCurrentUser.path) {
    let session = ShellSession(directory: directory)
    sessions.append(session)
    selected = session.id
  }
  func close(_ id: UUID) {
    sessions.first { $0.id == id }?.stop()
    sessions.removeAll { $0.id == id }
    if selected == id { selected = sessions.last?.id }
  }
}
struct NativeTerminal: NSViewRepresentable {
  @ObservedObject var session: ShellSession
  func makeNSView(context: Context) -> LocalProcessTerminalView {
    session.start()
    return session.terminal
  }
  func updateNSView(_ view: LocalProcessTerminalView, context: Context) {}
}
struct TerminalWorkspace: View {
  // Session ownership is app-scoped so station changes do not terminate shells.
  @EnvironmentObject private var shells: TerminalSessions
  var body: some View {
    ACCPanel {
      HStack {
        Text("LOCAL SHELLS").font(.lcars(20)).foregroundStyle(Color.accPeach)
        Spacer()
        ACCButton(title: "OPEN FOLDER", symbol: "folder") {
          let panel = NSOpenPanel()
          panel.canChooseDirectories = true
          panel.canChooseFiles = false
          panel.allowsMultipleSelection = false
          if panel.runModal() == .OK, let url = panel.url { shells.add(directory: url.path) }
        }
        ACCButton(title: "NEW SESSION", symbol: "plus", primary: true) { shells.add() }
      }
      HStack(spacing: 8) {
        ForEach(shells.sessions) { session in
          HStack {
            Button(session.title) { shells.selected = session.id }
            Button {
              shells.close(session.id)
            } label: {
              Image(systemName: "xmark").font(.caption2)
            }.help("Close shell session")
          }.font(.lcars(12)).padding(10).background(
            shells.selected == session.id ? Color.accLavender.opacity(0.3) : Color.accPanel,
            in: RoundedRectangle(cornerRadius: 10))
        }
      }
      if let selected = shells.sessions.first(where: { $0.id == shells.selected }) {
        NativeTerminal(session: selected).id(selected.id).frame(
          maxWidth: .infinity, maxHeight: .infinity)
        Text(
          "LOCAL / \(selected.directory) · Interactive PTY · Shells keep running between stations"
        ).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.accLavender)
      } else {
        EmptyStation(
          symbol: "terminal", title: "ENGINEERING READY",
          detail:
            "Create a local shell or choose a project folder. Terminal commands run with your user permissions."
        )
      }
    }
  }
}
