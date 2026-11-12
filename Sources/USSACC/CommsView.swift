import ACCCore
import AppKit
import SwiftUI

struct CommsView: View {
  @EnvironmentObject private var model: AppModel
  @State private var search = ""
  @State private var quarantine = false
  @State private var newConversation = false
  @State private var draft = ""
  @State private var mode: Channel = .message
  @State private var destination = ""
  /// List order: newest first, or grouped by OP level (highest first, newest within a level).
  @AppStorage("commsGroupByLevel") private var groupByLevel = false
  /// Show only one OP level (1–5), unscored (0) or everything (-1).
  @AppStorage("commsLevelFilter") private var levelFilter = -1
  /// Conversations picked with ⌘-click or Shift-click (sender identities), and the row a
  /// Shift-click range starts from. One picked row is the ordinary single selection.
  @State private var picked: Set<String> = []
  @State private var anchor: String?
  /// An action that would quarantine or delete several messages, waiting for confirmation.
  @State private var pending: PendingAction?
  struct PendingAction: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let button: String
    let destructive: Bool
    let run: @MainActor () async -> Void
  }
  /// Messages in the current view: inbox or quarantine, search, and the OP filter.
  var items: [Communication] {
    guard levelFilter >= 0 else { return viewItems }
    return viewItems.filter { ($0.classification?.level ?? 0) == levelFilter }
  }
  var viewItems: [Communication] {
    // Live searches use the local store's index, which also covers archived mail.
    if !search.isEmpty, let stored = model.searchStored(search) {
      let loaded = Dictionary(model.communications.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
      return stored.map { loaded[$0.id] ?? $0 }.filter { !$0.trashed && $0.quarantined == quarantine }
    }
    return model.communications.filter {
      !$0.trashed && $0.quarantined == quarantine
        && (search.isEmpty
          || ($0.name + $0.address + $0.subject + $0.body).localizedCaseInsensitiveContains(search))
    }
  }
  var people: [Communication] {
    var seen: Set<String> = []
    let latest = items.sorted { $0.date > $1.date }.filter { seen.insert($0.identity).inserted }
    guard groupByLevel else { return latest }
    // A conversation sits under its sender rule, else its newest message's level.
    return latest.enumerated().sorted { a, b in
      let (la, lb) = (level(of: a.element), level(of: b.element))
      return la != lb ? la > lb : a.offset < b.offset
    }.map(\.element)
  }
  /// ALL / OP5…OP1 / unscored chips; ⌥0–⌥5 switch them from the keyboard.
  func filterChip(_ title: String, value: Int, color: Color, key: Character?) -> some View {
    let on = levelFilter == value
    let button = Button {
      levelFilter = on && value >= 0 ? -1 : value
      picked = []
    } label: {
      Text(title).font(.lcars(15)).foregroundStyle(on ? Color.black : color)
        .padding(.horizontal, 10).frame(minWidth: 30).frame(height: 28)
        .background(on ? color : Color.accField, in: Capsule())
        .overlay(Capsule().stroke(color, lineWidth: on ? 0 : 1.2)).contentShape(Capsule())
    }.buttonStyle(.plain)
    return Group {
      if let key {
        button.keyboardShortcut(KeyEquivalent(key), modifiers: .option)
          .help(value < 0 ? "Show everything (⌥0)" : "Show only OP\(value) (⌥\(key))")
      } else {
        button
      }
    }
  }
  /// Verification codes, pinned above everything, with time left before they go to Trash.
  var codesStrip: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      VStack(alignment: .leading, spacing: 8) {
        Label("VERIFICATION CODES", systemImage: "key.fill").font(.lcars(16))
          .foregroundStyle(Color.accPeach)
        ForEach(Array(model.codeMessages.prefix(4))) { item in
          codeCard(item, now: context.date)
        }
      }
    }
  }
  func codeCard(_ item: Communication, now: Date) -> some View {
    let left = OneTimeCode.lifetime - now.timeIntervalSince(item.date)
    let minutes = max(0, Int(left / 60))
    let expiry =
      item.classification?.level == 5
      ? "kept · OP5"
      : left <= 0 ? "deleting…" : minutes >= 60 ? "deletes in \(minutes / 60)h \(minutes % 60)m" : "deletes in \(minutes)m"
    return HStack(spacing: 12) {
      Button {
        quarantine = item.quarantined
        if levelFilter >= 0, (item.classification?.level ?? 0) != levelFilter { levelFilter = -1 }
        picked = []
        model.selectedIdentity = item.identity
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text(item.oneTimeCode ?? "").font(.system(size: 28, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.accText)
          Text("\(item.name) · \(item.date.accRelative)").font(.acc(15))
            .foregroundStyle(Color.accDim).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain).help("Open this message")
      Text(expiry).font(.acc(14)).foregroundStyle(Color.accDim)
      Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.oneTimeCode ?? "", forType: .string)
        model.status = "Copied code from \(item.name)"
      } label: {
        Label("COPY", systemImage: "doc.on.doc").font(.lcars(15)).foregroundStyle(.black)
          .padding(.horizontal, 12).frame(height: 32)
          .background(Color.accPeach, in: Capsule()).contentShape(Capsule())
      }.buttonStyle(.plain)
      Button { model.dismissCode(item.id) } label: {
        Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
          .frame(width: 26, height: 26).contentShape(Rectangle())
      }.buttonStyle(.plain).foregroundStyle(Color.accDim)
        .help("Not a code: unpin it and don't delete it")
    }.padding(.horizontal, 14).padding(.vertical, 10)
      .background(Color.accCard, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accPeach, lineWidth: 1.4))
  }
  enum TrashState { case none, some, all }
  /// Whether this conversation's visible messages are on their way to Trash.
  func trashState(_ item: Communication) -> TrashState {
    let mine = items.filter { $0.identity == item.identity }
    let moving = mine.filter { model.trashing.contains($0.id) }.count
    return moving == 0 ? .none : moving == mine.count ? .all : .some
  }
  func level(of item: Communication) -> Int {
    model.policy.senderLevel(item.address) ?? item.classification?.level ?? 0
  }
  /// The conversations currently selected: the picked set while it holds more than one visible
  /// conversation, otherwise the focused one.
  var selection: Set<String> {
    let live = picked.intersection(people.map(\.identity))
    if live.count > 1 { return live }
    return model.selectedIdentity.map { [$0] } ?? []
  }
  var chosen: [Communication] { people.filter { selection.contains($0.identity) } }
  /// Messages in the current view (inbox or quarantine, and search) from these conversations.
  func messages(in conversations: [Communication]) -> [Communication] {
    let ids = Set(conversations.map(\.identity))
    return items.filter { ids.contains($0.identity) }
  }
  /// Click selects one; ⌘-click adds or removes; Shift-click selects the range from the last
  /// clicked row (⌘-Shift adds the range).
  func click(_ item: Communication) {
    let flags = NSEvent.modifierFlags
    let id = item.identity
    if flags.contains(.shift), let anchor,
      let a = people.firstIndex(where: { $0.identity == anchor }),
      let b = people.firstIndex(where: { $0.identity == id })
    {
      let range = Set(people[min(a, b)...max(a, b)].map(\.identity))
      picked = flags.contains(.command) ? selection.union(range) : range
    } else if flags.contains(.command) {
      var current = selection
      if current.contains(id), current.count > 1 { current.remove(id) } else { current.insert(id) }
      picked = current
      anchor = id
      if !current.contains(id) {
        model.selectedIdentity = people.first { current.contains($0.identity) }?.identity
        return
      }
    } else {
      picked = [id]
      anchor = id
    }
    model.selectedIdentity = id
  }
  var thread: [Communication] {
    items.filter { $0.identity == model.selectedIdentity }.sorted { $0.date < $1.date }
  }
  var selected: Communication? { thread.last }
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      list.frame(width: 450).frame(maxHeight: .infinity)
      conversation.frame(maxHeight: .infinity)
    }.confirmationDialog(
      pending?.title ?? "",
      isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
      titleVisibility: .visible, presenting: pending
    ) { action in
      Button(action.button, role: action.destructive ? .destructive : nil) {
        Task { await action.run() }
      }
      Button("Cancel", role: .cancel) {}
    } message: { action in
      Text(action.message)
    }.background {
      // ⌘⌫ marks the selected conversations OP1 (Trash), after confirming. Ignored while a
      // text field is being edited.
      Button("") {
        guard !(NSApp.keyWindow?.firstResponder is NSText) else { return }
        markConversations(chosen, level: 1, confirm: true)
      }.keyboardShortcut(.delete, modifiers: .command).opacity(0).frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }.sheet(isPresented: $newConversation) {
      ComposeSheet(
        mode: mode,
        destination: destination.isEmpty && mode == .email
          ? (selected?.address ?? "") : destination, bodyText: draft
      ).environmentObject(model)
    }
  }
  var list: some View {
    ACCPanel(padding: 16) {
      if !model.codeMessages.isEmpty { codesStrip }
      HStack(spacing: 12) {
        ACCField(placeholder: "Search conversations…", text: $search, symbol: "magnifyingglass")
        ACCButton(title: "NEW CONVERSATION", symbol: "plus", primary: true) {
          destination = ""
          newConversation = true
        }.fixedSize()
      }
      HStack(spacing: 6) {
        Text("SHOW").font(.lcars(15)).foregroundStyle(Color.accDim).padding(.trailing, 2)
        filterChip("ALL", value: -1, color: .accLavender, key: "0")
        ForEach(Array((1...5).reversed()), id: \.self) { level in
          filterChip("OP\(level)", value: level, color: .op(level), key: Character("\(level)"))
        }
        filterChip("–", value: 0, color: .accDim, key: nil).help("Not scored")
        Spacer(minLength: 0)
      }
      HStack(spacing: 10) {
        Text("SORT").font(.lcars(15)).foregroundStyle(Color.accDim)
        ACCSegmented(
          options: [("RECENT", false), ("OP LEVEL", true)], selection: $groupByLevel, height: 32)
      }
      if let run = model.trashProgress {
        HStack(spacing: 10) {
          ProgressView().controlSize(.small)
          Text("Moving to Trash · \(run.done) of \(run.total)").font(.acc(16))
          Spacer()
          ProgressView(value: Double(run.done), total: Double(max(run.total, 1))).frame(width: 110)
        }.foregroundStyle(Color.accText).padding(.horizontal, 14).padding(.vertical, 8)
          .background(Color.op(1).opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
          .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.op(1), lineWidth: 1))
          .transition(.opacity)
      }
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(Array(people.enumerated()), id: \.element.id) { index, item in
            let moving = trashState(item)
            let isSelected = selection.contains(item.identity)
            if groupByLevel, index == 0 || level(of: people[index - 1]) != level(of: item) {
              levelHeader(level(of: item))
            }
            Button {
              click(item)
            } label: {
              HStack(spacing: 18) {
                Avatar(name: item.name, size: 68)
                VStack(alignment: .leading, spacing: 4) {
                  HStack(spacing: 10) {
                    Text(item.name).font(.acc(23, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 6)
                    ChannelTag(item: item)
                    Text(item.date.accRelative).font(.acc(18)).frame(minWidth: 50, alignment: .trailing)
                  }
                  HStack {
                    if moving == .all {
                      Label("Moving to Trash…", systemImage: "trash").font(.acc(19))
                        .foregroundStyle(Color.op(1)).lineLimit(1)
                    } else {
                      Text(item.preview).font(.acc(19)).foregroundStyle(Color.accDim).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if moving != .none { ProgressView().controlSize(.small) }
                    if model.policy.senderLevel(item.address) != nil {
                      Image(systemName: "pin.fill").font(.system(size: 12))
                        .foregroundStyle(Color.accLavender)
                        .help("Sender rule: all mail from this address is scored this level")
                    }
                    if item.channel == .email || item.classification != nil {
                      OPBadge(level: item.classification?.level, size: 15)
                    }
                  }
                }
              }.foregroundStyle(Color.accText).padding(.horizontal, 14).padding(.vertical, 14)
                .background(
                  isSelected ? Color(red: 0.137, green: 0.161, blue: 0.255) : .clear,
                  in: RoundedRectangle(cornerRadius: 12)
                ).overlay(
                  RoundedRectangle(cornerRadius: 12).stroke(
                    isSelected ? Color.accBorder : .clear, lineWidth: 1.2)
                ).contentShape(Rectangle())
                .opacity(moving == .all ? 0.5 : 1)
            }.buttonStyle(.plain)
              .contextMenu {
                // Right-clicking inside a multi-selection acts on all of it.
                conversationMenu(
                  isSelected && selection.count > 1 ? chosen : [item])
              }
            if index < people.count - 1, !isSelected,
              !selection.contains(people[index + 1].identity)
            {
              ACCDivider().padding(.horizontal, 10)
            } else {
              Color.clear.frame(height: 1)
            }
          }
        }
      }
      if people.isEmpty {
        Text(
          levelFilter >= 0
            ? "Nothing \(levelFilter == 0 ? "unscored" : "at OP\(levelFilter)") \(quarantine ? "in quarantine" : "in the inbox")."
            : quarantine ? "No quarantined communications." : "No communications yet.")
          .font(.acc(18)).foregroundStyle(Color.accDim)
      }
      Spacer(minLength: 0)
      if !model.demo {
        let sources = model.accounts.filter(\.enabled).count + (model.mailConnected ? 1 : 0)
        Text(
          sources == 0
            ? "No mail accounts connected. Add Gmail, IMAP, or import from Apple Mail."
            : "\(sources) mail source\(sources == 1 ? "" : "s") · checked every 60 seconds"
        ).font(.acc(15)).foregroundStyle(Color.accDim)
        HStack(spacing: 10) {
          ACCButton(title: "MAIL ACCOUNTS", symbol: "person.crop.circle.badge.plus", kind: .outline) {
            model.station = .dev
            model.settings = true
            model.settingsSection = "Connections"
          }
          if sources > 0 {
            ACCButton(title: "REFRESH", symbol: "arrow.clockwise") { Task { await model.refreshMail() } }
              .disabled(model.busy)
            ACCButton(title: "OLDER", symbol: "clock.arrow.circlepath", kind: .outline) {
              Task { await model.loadOlder() }
            }.disabled(model.busy).help("Download up to 200 older messages per IMAP account")
          }
        }
      }
      ACCSegmented(
        options: [("INBOX", false), ("QUARANTINE", true)], selection: $quarantine, height: 38)
    }
  }
  var conversation: some View {
    ACCPanel(padding: 20) {
      if selection.count > 1 {
        bulkPanel(chosen)
      } else if let selected {
        HStack(alignment: .center, spacing: 18) {
          Avatar(name: selected.name, size: 74)
          VStack(alignment: .leading, spacing: 2) {
            Text(selected.name).font(.acc(31, weight: .medium))
            Text(selected.address).font(.acc(18)).foregroundStyle(Color.accLavender)
              .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
          }
          Spacer()
          ACCButton(title: "EMAIL", symbol: "envelope", size: 17, height: 42) {
            mode = .email
            destination = selected.address
            newConversation = true
          }.fixedSize()
          ACCButton(title: "MESSAGE", symbol: "message", size: 17, height: 42) {
            mode = .message
            destination = ""
            newConversation = true
          }.fixedSize()
          ACCButton(title: "CALL", symbol: "phone.fill", size: 17, height: 42) {
            mode = .call
            destination = ""
            newConversation = true
          }.fixedSize()
        }
        ACCDivider()
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(thread.enumerated()), id: \.element.id) { index, item in
              entry(item, last: index == thread.count - 1)
            }
          }.padding(.top, 6)
        }
        composer(for: selected)
          .task(id: thread.filter(\.archived).map(\.id)) {
            for item in thread where item.archived { model.retrieve(item.id) }
          }
      } else {
        EmptyStation(
          symbol: "bubble.left.and.bubble.right", title: "SELECT A CONVERSATION",
          detail: "Email, messages, and call activity share a single workspace.")
      }
    }
  }
  func entry(_ item: Communication, last: Bool) -> some View {
    let highlighted =
      item.classification?.level.map { model.policy.rule(for: $0).highlight } == true
    return HStack(alignment: .top, spacing: 24) {
      VStack(spacing: 0) {
        Image(systemName: item.channelSymbol).font(.system(size: 19, weight: .semibold))
          .foregroundStyle(item.channel == .call ? Color.black : Color.accField)
          .frame(width: 48, height: 48)
          .background(item.channel == .call ? Color.accGreen : Color.accLavender, in: Circle())
        if !last { Rectangle().fill(Color.accLavender.opacity(0.7)).frame(width: 2).frame(maxHeight: .infinity) }
      }
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          Text(item.channel.rawValue.uppercased()).font(.lcars(22)).foregroundStyle(Color.accLavender)
          Text("·  \(item.date.accClock())").font(.acc(21, weight: .medium)).foregroundStyle(
            Color.accLavender)
          Spacer()
          if let code = item.oneTimeCode {
            Label(code, systemImage: "key.fill")
              .font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(.black)
              .padding(.horizontal, 10).padding(.vertical, 3)
              .background(Color.accPeach, in: Capsule()).textSelection(.enabled)
          }
          OPBadge(level: item.classification?.level)
        }.padding(.top, 10)
        VStack(alignment: .leading, spacing: 8) {
          if !item.subject.isEmpty { Text(item.subject).font(.acc(23, weight: .medium)) }
          if item.archived {
            Label("Retrieving from archive…", systemImage: "archivebox").font(.acc(18))
              .foregroundStyle(Color.accLavender)
          } else {
            Text(item.body).font(.acc(20)).textSelection(.enabled)
          }
          if model.trashing.contains(item.id) {
            ACCDivider()
            HStack(spacing: 10) {
              ProgressView().controlSize(.small)
              Text("Moving to Trash…").font(.lcars(16)).foregroundStyle(Color.op(1))
            }
          } else {
            scoreBar(item)
          }
        }.padding(.horizontal, 26).padding(.vertical, 16)
          .opacity(model.trashing.contains(item.id) ? 0.55 : 1)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.accCard, in: RoundedRectangle(cornerRadius: 12))
          .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(
              highlighted ? Color.accPeach : Color.accBorder, lineWidth: highlighted ? 1.6 : 1.2))
      }.padding(.bottom, 22)
    }
  }
  func levelHeader(_ level: Int) -> some View {
    HStack(spacing: 10) {
      OPBadge(level: level == 0 ? nil : level, size: 15)
      Text(level == 0 ? "Not scored" : model.policy.meaning(for: level)).font(.acc(15))
        .foregroundStyle(Color.accDim).lineLimit(1)
      Spacer()
    }.padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)
  }
  /// Right-click menu for one conversation or a selection: score their messages now, or set a
  /// standing sender rule for all past and future mail from those addresses.
  @ViewBuilder func conversationMenu(_ conversations: [Communication]) -> some View {
    let many = conversations.count > 1
    Section(many ? "Mark \(conversations.count) conversations" : "Mark this conversation") {
      ForEach(Array((1...5).reversed()), id: \.self) { level in
        Button("OP\(level) · \(ruleAction(level))") {
          markConversations(conversations, level: level)
        }
      }
    }
    if quarantine {
      Button("Restore to inbox") {
        model.restore(messages(in: conversations).map(\.id))
        picked = []
      }
    }
    let senders = conversations.filter { $0.channel == .email }.map(\.address)
    if !senders.isEmpty {
      let current = Set(senders.map { model.policy.senderLevel($0) })
      Section(
        senders.count == 1
          ? "Always, for all mail from \(senders[0])" : "Always, for all mail from these \(senders.count) senders"
      ) {
        ForEach(Array((1...5).reversed()), id: \.self) { level in
          Button {
            requestRules(senders, level: level)
          } label: {
            if current == [level] {
              Label("Always OP\(level) · \(ruleAction(level))", systemImage: "checkmark")
            } else {
              Text("Always OP\(level) · \(ruleAction(level))")
            }
          }
        }
      }
      if senders.contains(where: { model.policy.senderLevel($0) != nil }) {
        Divider()
        Button(senders.count == 1 ? "Remove sender rule" : "Remove sender rules") {
          Task { for address in senders { await model.setSenderRule(address, level: nil) } }
        }
      }
    }
  }
  /// Multi-selection pane: the same actions as the right-click menu, as buttons.
  func bulkPanel(_ conversations: [Communication]) -> some View {
    let count = messages(in: conversations).count
    let senders = conversations.filter { $0.channel == .email }.map(\.address)
    return VStack(alignment: .leading, spacing: 22) {
      Text("\(conversations.count) CONVERSATIONS SELECTED").font(.lcars(30))
        .foregroundStyle(Color.accPeach)
      Text(
        "\(count) message\(count == 1 ? "" : "s") in \(quarantine ? "quarantine" : "the inbox") · "
          + conversations.prefix(6).map(\.name).joined(separator: ", ")
          + (conversations.count > 6 ? " and \(conversations.count - 6) more" : "")
      ).font(.acc(18)).foregroundStyle(Color.accDim).lineLimit(3)
      ACCDivider()
      Text("MARK THESE MESSAGES").font(.lcars(16)).foregroundStyle(Color.accDim)
      HStack(spacing: 10) {
        ForEach(Array((1...5).reversed()), id: \.self) { level in
          Button { markConversations(conversations, level: level) } label: {
            Text("OP\(level)").font(.lcars(17)).foregroundStyle(Color.op(level))
              .frame(width: 70, height: 36)
              .background(Color.accField, in: Capsule())
              .overlay(Capsule().stroke(Color.op(level), lineWidth: 1.4)).contentShape(Capsule())
          }.buttonStyle(.plain).help(scoreHelp(level))
        }
        Spacer()
        if quarantine {
          ACCButton(title: "RESTORE", symbol: "tray.and.arrow.up", kind: .outline, size: 17, height: 40) {
            model.restore(messages(in: conversations).map(\.id))
            picked = []
          }.fixedSize()
        }
        Button { markConversations(conversations, level: 1) } label: {
          Label("DELETE", systemImage: "trash").font(.lcars(17)).foregroundStyle(.black)
            .padding(.horizontal, 16).frame(height: 40)
            .background(Color.op(1), in: Capsule()).contentShape(Capsule())
        }.buttonStyle(.plain).help("Mark OP1 and move to Trash (⌘⌫)")
      }
      if !senders.isEmpty {
        Text("ALWAYS, FOR ALL PAST AND FUTURE MAIL FROM THESE SENDERS").font(.lcars(16))
          .foregroundStyle(Color.accDim)
        HStack(spacing: 10) {
          ForEach(Array((1...5).reversed()), id: \.self) { level in
            Button { requestRules(senders, level: level) } label: {
              Label("OP\(level)", systemImage: "pin.fill").font(.lcars(17))
                .foregroundStyle(Color.op(level)).frame(width: 84, height: 36)
                .background(Color.accField, in: Capsule())
                .overlay(Capsule().stroke(Color.op(level), lineWidth: 1.4)).contentShape(Capsule())
            }.buttonStyle(.plain).help("Sender rule: OP\(level) · \(ruleAction(level))")
          }
        }
      }
      Spacer()
      HStack {
        Text("Shift-click selects a range · ⌘-click adds or removes · right-click for the same actions")
          .font(.acc(15)).foregroundStyle(Color.accDim)
        Spacer()
        Button("CLEAR SELECTION") { picked = [] }.buttonStyle(.plain).font(.lcars(15))
          .foregroundStyle(Color.accLavender)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  func ruleAction(_ level: Int) -> String {
    switch PolicyDecision.manual(level: level, policy: model.policy) {
    case .keep: "keep"
    case .quarantine: "quarantine"
    case .delete: "Trash"
    }
  }
  /// Scores every message (in this view) of these conversations. Acting on more than one
  /// conversation asks first when it would quarantine or delete.
  func markConversations(_ conversations: [Communication], level: Int, confirm: Bool = false) {
    let ids = messages(in: conversations).map(\.id)
    guard !ids.isEmpty else { return }
    let disposition = PolicyDecision.manual(level: level, policy: model.policy)
    let run: @MainActor () async -> Void = {
      picked = []
      await model.applyLevel(ids, level: level)
    }
    guard conversations.count > 1 || confirm, disposition != .keep else {
      Task { await run() }
      return
    }
    let verb = disposition == .delete ? "move them to Trash" : "quarantine them"
    pending = PendingAction(
      title:
        "Mark \(ids.count) message\(ids.count == 1 ? "" : "s") from \(conversations.count == 1 ? conversations[0].name : "\(conversations.count) conversations") OP\(level)?",
      message: "This will \(verb).",
      button: disposition == .delete ? "Mark OP\(level) and move to Trash" : "Mark OP\(level) and quarantine",
      destructive: disposition == .delete, run: run)
  }
  /// Sender rules that quarantine or delete existing mail ask first; Keep applies at once.
  func requestRules(_ addresses: [String], level: Int) {
    let disposition = PolicyDecision.manual(level: level, policy: model.policy)
    let count = addresses.reduce(0) { $0 + model.senderMessages($1).count }
    let run: @MainActor () async -> Void = {
      picked = []
      for address in addresses { await model.setSenderRule(address, level: level) }
    }
    if disposition == .keep || count == 0 {
      Task { await run() }
      return
    }
    let who = addresses.count == 1 ? FilterPolicy.normalize(addresses[0]) : "\(addresses.count) senders"
    pending = PendingAction(
      title: "Mark all mail from \(who) as OP\(level)?",
      message:
        "This \(disposition == .delete ? "moves" : "quarantines") the \(count) message\(count == 1 ? "" : "s") already here\(disposition == .delete ? " to Trash" : "") and applies to every future message from \(addresses.count == 1 ? "this sender" : "these senders").",
      button: disposition == .delete
        ? "Mark OP\(level) and move \(count) to Trash" : "Mark OP\(level) and quarantine \(count)",
      destructive: disposition == .delete, run: run)
  }
  /// Always-visible classification controls: the current score and reason, one chip per level
  /// (choosing one applies that level's saved rule), AI re-classify, restore and delete.
  func scoreBar(_ item: Communication) -> some View {
    let current = item.classification?.level
    return VStack(alignment: .leading, spacing: 10) {
      ACCDivider()
      HStack(spacing: 8) {
        Text("CLASSIFY").font(.lcars(15)).foregroundStyle(Color.accDim).padding(.trailing, 4)
        ForEach(1...5, id: \.self) { level in
          let chosen = current == level
          Button {
            Task { await model.correctScore(item.id, level: level) }
          } label: {
            Text("OP\(level)").font(.lcars(16))
              .foregroundStyle(chosen ? Color.black : Color.op(level))
              .frame(width: 58, height: 32)
              .background(chosen ? Color.op(level) : Color.accField, in: Capsule())
              .overlay(Capsule().stroke(Color.op(level), lineWidth: chosen ? 0 : 1.4))
              .contentShape(Capsule())
          }.buttonStyle(.plain).help(scoreHelp(level))
        }
        Spacer(minLength: 8)
        Button { Task { await model.classify(id: item.id, askModel: true) } } label: {
          Label("AI", systemImage: "sparkles").font(.lcars(15))
        }.buttonStyle(.plain).foregroundStyle(Color.accLavender)
          .help("Ask the on-device model to score this message (no rule is applied)")
        if item.quarantined {
          Button { model.restore(item.id) } label: {
            Label("RESTORE", systemImage: "tray.and.arrow.up").font(.lcars(15))
          }.buttonStyle(.plain).foregroundStyle(Color.accLavender)
        }
        if item.channel == .email {
          Button { Task { await model.delete(item.id) } } label: {
            Label("DELETE", systemImage: "trash").font(.lcars(15)).foregroundStyle(.black)
              .padding(.horizontal, 12).frame(height: 32)
              .background(Color.op(1), in: Capsule()).contentShape(Capsule())
          }.buttonStyle(.plain).help("Mark OP1 and move to the account's Trash")
        }
      }
      if let ruled = model.policy.senderLevel(item.address),
        item.classification?.source != Classification.senderRuleSource
      {
        Text("Sender rule is OP\(ruled); this message was set separately.").font(.acc(15))
          .foregroundStyle(Color.accLavender)
      }
      if let classification = item.classification {
        Text("\(classification.reason) · \(classification.source)").font(.acc(15))
          .foregroundStyle(Color.accDim).lineLimit(2)
      } else {
        Text("Not scored yet. Pick a level, or AI to ask the on-device model.").font(.acc(15))
          .foregroundStyle(Color.accDim)
      }
    }
  }
  func scoreHelp(_ level: Int) -> String {
    let meaning = model.policy.meaning(for: level)
    let action: String
    switch PolicyDecision.manual(level: level, policy: model.policy) {
    case .keep: action = "keeps it in the inbox"
    case .quarantine: action = "moves it to quarantine"
    case .delete: action = "moves it to Trash"
    }
    return "OP\(level)\(meaning.isEmpty ? "" : " — \(meaning)") · \(action)"
  }
  func composer(for selected: Communication) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Text("Send as:").font(.acc(18))
        Menu {
          Button("Message") { mode = .message }
          Button("Email") { mode = .email }
        } label: {
          HStack {
            Text(mode == .email ? "Email" : "Message").font(.acc(18))
            Spacer()
            Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
          }.padding(.horizontal, 14).frame(width: 125, height: 46)
            .background(Color.accField, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.accBorder, lineWidth: 1.2))
        }.menuStyle(.button).buttonStyle(.plain).fixedSize()
        ACCField(placeholder: "Write a reply…", text: $draft)
        ACCButton(title: "SEND", primary: true, size: 20) {
          destination = mode == .email ? selected.address : ""
          newConversation = true
        }.frame(minWidth: 110)
      }
      Text("To: \(selected.name) · \(mode == .email ? selected.address : "Messages")   —   opens the system app to review and send")
        .font(.acc(16)).foregroundStyle(Color.accLavender)
    }.padding(14)
      .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accBorder, lineWidth: 1.2))
  }
}
struct ComposeSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var model: AppModel
  @State var mode: Channel
  @State var destination: String
  @State var bodyText: String
  @State private var subject = ""
  @State private var result = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("OPEN A CHANNEL").font(.lcars(27)).foregroundStyle(Color.accPeach)
      Picker("Mode", selection: $mode) {
        ForEach(Channel.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
      }.pickerStyle(.segmented)
      TextField(
        mode == .email ? "Email address" : "Phone number or supported account", text: $destination
      ).textFieldStyle(.roundedBorder)
      if mode == .email { TextField("Subject", text: $subject).textFieldStyle(.roundedBorder) }
      if mode != .call {
        TextEditor(text: $bodyText).frame(height: 150).border(Color.accLavender.opacity(0.3))
      }
      Text(
        mode == .call
          ? "Calls open the configured macOS calling app. Incoming call history and live audio are not connected."
          : "Review and send in the system app. This screen does not send directly."
      ).font(.caption).foregroundStyle(.secondary)
      if model.demo {
        Text(
          "Demo contact addresses are fictional. Enter a real destination before opening an app."
        ).font(.caption).foregroundStyle(Color.accPeach)
      }
      Text(result).font(.caption)
      HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        ACCButton(title: mode == .call ? "OPEN CALLING APP" : "OPEN COMPOSER", primary: true) {
          let scheme = mode == .email ? "mailto" : mode == .call ? "tel" : "sms"
          result =
            Handoff.open(
              scheme, to: destination.trimmingCharacters(in: .whitespacesAndNewlines),
              subject: mode == .email ? subject : nil, body: mode == .call ? nil : bodyText)
            ? "Handed to macOS. Review the destination in the opened app."
            : "No compatible system app is configured."
        }.disabled(
          destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || destination.lowercased().contains("example.com"))
      }
    }.padding(28).frame(width: 590).background(Color.black).preferredColorScheme(.dark)
  }
}
