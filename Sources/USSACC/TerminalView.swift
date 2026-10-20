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
  @Published var split = false
  /// Project folder used for new sessions and the file tree; nil means the home folder.
  @Published var folder: String?
  var workingDirectory: String { folder ?? FileManager.default.homeDirectoryForCurrentUser.path }
  func add(directory: String? = nil) {
    let session = ShellSession(directory: directory ?? workingDirectory)
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
  @State private var target = "LOCAL"
  @State private var branch: String?
  var selected: ShellSession? { shells.sessions.first { $0.id == shells.selected } }
  /// The session shown beside the selected one in split view.
  var companion: ShellSession? {
    guard shells.split, let index = shells.sessions.firstIndex(where: { $0.id == shells.selected })
    else { return nil }
    return index > 0 ? shells.sessions[index - 1] : shells.sessions.dropFirst().first
  }
  var body: some View {
    ACCPanel(padding: 16) {
      HStack(spacing: 14) {
        Menu {
          Button("Open Folder…", action: chooseFolder)
          Button("Home Folder") { shells.folder = nil }
        } label: {
          dropdown(symbol: "folder", text: folderName, width: 300)
        }.menuStyle(.button).buttonStyle(.plain).fixedSize()
        dropdown(symbol: "arrow.triangle.branch", text: branch ?? "No git repo", width: 220)
          .help("Current git branch of the project folder (read-only)")
        ACCButton(title: "NEW SESSION", symbol: "plus", primary: true, height: 48) { shells.add() }
          .fixedSize()
        ACCButton(title: shells.split ? "UNSPLIT" : "SPLIT", symbol: "rectangle.split.2x1", height: 48) {
          if !shells.split && shells.sessions.count < 2 { shells.add() }
          shells.split.toggle()
        }.fixedSize()
        Spacer()
      }
      HStack(alignment: .top, spacing: 10) {
        sidebar.frame(width: 240).frame(maxHeight: .infinity)
        terminalArea.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }.task(id: shells.folder) { branch = await Self.gitBranch(in: shells.workingDirectory) }
  }
  var folderName: String {
    shells.folder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Home"
  }
  func dropdown(symbol: String, text: String, width: CGFloat) -> some View {
    HStack(spacing: 14) {
      Image(systemName: symbol).font(.system(size: 19, weight: .medium))
      Text(text).font(.acc(21)).lineLimit(1)
      Spacer()
      Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold))
    }.foregroundStyle(Color.accText).padding(.horizontal, 18).frame(width: width, height: 48)
      .background(Color.accField, in: RoundedRectangle(cornerRadius: 11))
      .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.accBorder, lineWidth: 1.2))
  }
  var sidebar: some View {
    VStack(alignment: .leading, spacing: 8) {
      targetButton("LOCAL", symbol: "laptopcomputer", enabled: true)
      targetButton("SERVER", symbol: "server.rack", enabled: false)
        .help("Remote shells are not configured")
      ACCDivider().padding(.vertical, 6)
      ScrollView { FileTree(url: URL(fileURLWithPath: shells.workingDirectory), depth: 0) }
    }.padding(8)
      .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accBorder, lineWidth: 1.2))
  }
  func targetButton(_ title: String, symbol: String, enabled: Bool) -> some View {
    Button {
      target = title
    } label: {
      HStack(spacing: 18) {
        Image(systemName: symbol).font(.system(size: 22, weight: .medium)).frame(width: 30)
        Text(title).font(.lcars(21))
        Spacer()
      }.foregroundStyle(target == title ? Color.black : Color.accText).padding(.horizontal, 16)
        .frame(height: 54)
        .background(target == title ? Color.accLavender : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.5)
  }
  var terminalArea: some View {
    VStack(spacing: 0) {
      HStack(spacing: 4) {
        ForEach(shells.sessions) { session in
          HStack(spacing: 14) {
            Button {
              shells.selected = session.id
            } label: {
              HStack(spacing: 12) {
                Text(">_").font(.system(size: 16, weight: .bold, design: .monospaced))
                Text(session.title).font(.acc(20))
              }
            }.buttonStyle(.plain)
            Button {
              shells.close(session.id)
              if shells.sessions.count < 2 { shells.split = false }
            } label: {
              Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
            }.buttonStyle(.plain).help("Close shell session")
          }.foregroundStyle(Color.accText).padding(.horizontal, 18).frame(height: 50)
            .background(
              UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10).fill(
                shells.selected == session.id ? Color.accField : .clear)
            )
            .overlay(
              UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10).stroke(
                shells.selected == session.id ? Color.accBorder : .clear, lineWidth: 1.2))
        }
        Button {
          shells.add()
        } label: {
          Image(systemName: "plus").font(.system(size: 19, weight: .medium)).frame(width: 44, height: 44)
        }.buttonStyle(.plain).help("New session")
        Spacer()
      }.padding(.horizontal, 6).padding(.top, 6)
      ACCDivider()
      if let selected {
        HStack(spacing: 1) {
          if let companion {
            NativeTerminal(session: companion).id(companion.id)
            Rectangle().fill(Color.accBorder).frame(width: 1.5)
          }
          NativeTerminal(session: selected).id(selected.id)
        }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
        ACCDivider()
        Text("LOCAL SHELL  ·  \(abbreviate(selected.directory))  ·  shells keep running between stations")
          .font(.acc(17)).foregroundStyle(Color.accText).frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 18).frame(height: 44)
      } else {
        EmptyStation(
          symbol: "terminal", title: "ENGINEERING READY",
          detail:
            "Create a local shell or choose a project folder. Terminal commands run with your user permissions."
        )
      }
    }.background(Color.black, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accBorder, lineWidth: 1.2))
  }
  func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      shells.folder = url.path
      shells.add(directory: url.path)
    }
  }
  func abbreviate(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
  }
  /// Reads the checked-out branch without running git, so no shell or repository hooks execute.
  static func gitBranch(in directory: String) async -> String? {
    var url = URL(fileURLWithPath: directory)
    for _ in 0..<12 {
      let head = url.appendingPathComponent(".git/HEAD")
      if let text = try? String(contentsOf: head, encoding: .utf8) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.hasPrefix("ref: refs/heads/")
          ? String(line.dropFirst("ref: refs/heads/".count)) : String(line.prefix(7))
      }
      let gitFile = url.appendingPathComponent(".git")
      if let text = try? String(contentsOf: gitFile, encoding: .utf8), text.hasPrefix("gitdir: ") {
        let dir = text.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines)
        let gitDir = dir.hasPrefix("/") ? URL(fileURLWithPath: dir) : url.appendingPathComponent(dir)
        if let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) {
          let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
          return line.hasPrefix("ref: refs/heads/")
            ? String(line.dropFirst("ref: refs/heads/".count)) : String(line.prefix(7))
        }
      }
      let parent = url.deletingLastPathComponent()
      if parent.path == url.path { break }
      url = parent
    }
    return nil
  }
}
/// Lazily expanded, read-only folder outline. Double-click opens a file in its default app.
struct FileTree: View {
  let url: URL
  let depth: Int
  @State private var expanded: Set<URL> = []
  var children: [URL] {
    let items = (try? FileManager.default.contentsOfDirectory(
      at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
    return items.sorted {
      let a = isDirectory($0)
      let b = isDirectory($1)
      return a == b ? $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending : a
    }.prefix(200).map { $0 }
  }
  func isDirectory(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if depth == 0 {
        row(url, folder: true, open: true, root: true)
      }
      ForEach(children, id: \.self) { child in
        let folder = isDirectory(child)
        row(child, folder: folder, open: expanded.contains(child), root: false)
          .padding(.leading, CGFloat(depth + 1) * 16)
        if folder && expanded.contains(child) && depth < 6 {
          FileTree(url: child, depth: depth + 1)
        }
      }
    }
  }
  func row(_ item: URL, folder: Bool, open: Bool, root: Bool) -> some View {
    HStack(spacing: 10) {
      Group {
        if folder {
          Image(systemName: open ? "arrowtriangle.down.fill" : "arrowtriangle.right.fill")
        } else {
          Color.clear
        }
      }.font(.system(size: 10)).frame(width: 12)
      Image(systemName: folder ? "folder.fill" : "doc").font(.system(size: 16))
      Text(item.lastPathComponent).font(.acc(19)).lineLimit(1)
      Spacer(minLength: 0)
    }.foregroundStyle(Color.accText).frame(height: 28).contentShape(Rectangle())
      .onTapGesture(count: 2) { if !folder { NSWorkspace.shared.open(item) } }
      .onTapGesture {
        guard folder, !root else { return }
        if expanded.contains(item) { expanded.remove(item) } else { expanded.insert(item) }
      }
  }
}
