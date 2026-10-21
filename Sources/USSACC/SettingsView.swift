import ACCCore
import SwiftUI

struct DevView: View {
  @EnvironmentObject private var model: AppModel
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .bottom, spacing: 30) {
        StationTitle(station: .dev, showSubtitle: false)
        HStack(spacing: 8) {
          tab("TERMINAL", active: !model.settings) { model.settings = false }
          tab("SETTINGS", active: model.settings) { model.settings = true }
        }
        Spacer()
      }.frame(height: 92, alignment: .bottom)
      Group {
        if model.settings { SettingsView() } else { TerminalWorkspace() }
      }.frame(maxHeight: .infinity)
    }
  }
  func tab(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).font(.lcars(22)).foregroundStyle(active ? Color.black : Color.accText)
        .frame(width: 166, height: 46)
        .background(
          UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10).fill(
            active ? Color.accPeach : Color.accField)
        )
        .overlay(
          UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10).stroke(
            active ? .clear : Color.accBorder, lineWidth: 1.2)
        ).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityAddTraits(active ? .isSelected : [])
  }
}
struct SettingsView: View {
  @EnvironmentObject private var model: AppModel
  private var section: String {
    get { model.settingsSection }
    nonmutating set { model.settingsSection = newValue }
  }
  @State private var draft = FilterPolicy()
  @State private var known = ""
  @State private var sample = "Can you confirm tonight?"
  @State private var sampleKnown = true
  @State private var testResult = ""
  @State private var testing = false
  @State private var editing: AccountDraft?
  @State private var importing = false
  var body: some View {
    ACCPanel(padding: 12) {
      HStack(alignment: .top, spacing: 18) {
        VStack(spacing: 8) {
          ForEach(
            [
              ("General", "gearshape.fill"), ("Connections", "link"),
              ("Spam Filter", "line.3.horizontal.decrease"), ("Notifications", "bell"),
            ], id: \.0
          ) { title, symbol in
            Button {
              section = title
            } label: {
              HStack(spacing: 18) {
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).frame(width: 30)
                Text(title).font(.acc(23, weight: .medium))
                Spacer()
              }.padding(.horizontal, 20).frame(height: 66)
                .foregroundStyle(section == title ? Color.black : Color.accText).background(
                  section == title ? Color.accPeach : Color.black,
                  in: RoundedRectangle(cornerRadius: 10)
                ).overlay(
                  RoundedRectangle(cornerRadius: 10).stroke(
                    section == title ? .clear : Color.accBorder.opacity(0.6), lineWidth: 1)
                ).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityAddTraits(section == title ? .isSelected : [])
          }
          Spacer()
        }.frame(width: 232)
        VStack(alignment: .leading, spacing: 12) {
          ScrollView {
            VStack(alignment: .leading, spacing: 20) {
              switch section {
              case "Spam Filter": filter
              case "Connections": connections
              case "Notifications": notifications
              default: general
              }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 8)
          }
          if section == "Spam Filter" { actionBar }
        }.padding(.vertical, 8)
      }
    }.onAppear {
      draft = model.policy
      known = draft.knownAddresses.joined(separator: "\n")
    }
  }
  var actionBar: some View {
    HStack(spacing: 14) {
      if unsaved {
        Label("Unsaved changes · Save Rules to keep them", systemImage: "exclamationmark.circle")
          .font(.acc(19)).foregroundStyle(Color.accPeach).lineLimit(2)
      } else {
        Text(testResult.isEmpty ? "Unscored items stay visible." : testResult).font(.acc(19))
          .lineLimit(2).textSelection(.enabled)
      }
      Spacer()
      Button("Revert") {
        draft = model.policy
        known = draft.knownAddresses.joined(separator: "\n")
      }.buttonStyle(.plain).font(.lcars(18)).foregroundStyle(Color.accLavender)
      ACCButton(
        title: testing ? "CLASSIFYING…" : "TEST ON SAMPLE", kind: .outline, size: 22, height: 50
      ) { runTest() }.disabled(testing || sample.isEmpty).frame(width: 260)
      ACCButton(title: "SAVE RULES", primary: true, size: 22, height: 50) {
        draft.knownAddresses = parsedKnown
        if let i = draft.rules.firstIndex(where: { $0.level == 5 }) {
          draft.rules[i].disposition = .keep
        }
        model.savePolicy(draft)
      }.frame(width: 190)
    }.padding(.horizontal, 18).padding(.vertical, 6)
      .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accBorder, lineWidth: 1.2))
  }
  var parsedKnown: [String] {
    known.split(whereSeparator: \.isNewline).map {
      String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }.filter { !$0.isEmpty }
  }
  var unsaved: Bool {
    var pending = draft
    pending.knownAddresses = parsedKnown
    return pending != model.policy
  }
  func runTest() {
    testing = true
    Task {
      let item = Communication(
        name: "Sample", address: "sample@example.com", channel: .email, body: sample,
        isDemo: true)
      let result = await Intelligence.classify(item, known: sampleKnown)
      testResult = "Test · \(result.level.map { "OP\($0)" } ?? "Unscored"): \(result.reason)"
      testing = false
    }
  }
  /// Classified communications shown as examples; demo data in the demo workspace.
  var examples: [Communication] {
    let scored = model.communications.filter { $0.classification?.level != nil }
    let high = scored.first { $0.classification?.level == 5 }
    let low = scored.filter { ($0.classification?.level ?? 5) < 3 }.min {
      ($0.classification?.level ?? 0) < ($1.classification?.level ?? 0)
    }
    return [high, low].compactMap { $0 }
  }
  var filter: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: -2) {
          Text("SPAM FILTER").font(.lcars(54)).foregroundStyle(Color.accPeach)
          Text("Operational Importance · Apple Intelligence").font(.acc(26, weight: .medium))
            .foregroundStyle(Color.accLavender)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 6) {
          HStack(spacing: 12) {
            ACCTag(text: "Model status")
            Text(model.modelStatus).font(.acc(17)).foregroundStyle(Color.accLavender)
              .lineLimit(2).frame(maxWidth: 220, alignment: .leading).textSelection(.enabled)
          }
          Toggle(isOn: $draft.enabled) {
            Text("Classify new mail arrivals").font(.acc(18))
          }.toggleStyle(ACCCheckboxStyle())
        }.padding(.top, 8)
      }
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          Text("LEVEL").frame(width: 100, alignment: .leading)
          Text("MEANING").frame(maxWidth: .infinity, alignment: .leading)
          Text("DISPOSITION").frame(width: 195, alignment: .leading)
          Text("HIGHLIGHT").frame(width: 120)
          Text("PUSH").frame(width: 90)
        }.font(.lcars(20)).foregroundStyle(Color.accLavender).padding(.horizontal, 20)
          .frame(height: 50)
        ForEach((1...5).reversed(), id: \.self) { level in
          ACCDivider()
          if let index = draft.rules.firstIndex(where: { $0.level == level }) {
            HStack(spacing: 0) {
              OPBadge(level: level).frame(width: 100, alignment: .leading)
              Text(meaning(level)).font(.acc(20)).frame(maxWidth: .infinity, alignment: .leading)
              dispositionMenu(level: level, index: index).frame(width: 195, alignment: .leading)
              Toggle(isOn: $draft.rules[index].highlight) { EmptyView() }.accessibilityLabel("Highlight OP\(level)")
                .toggleStyle(ACCCheckboxStyle()).frame(width: 120)
              Toggle(isOn: $draft.rules[index].push) { EmptyView() }.accessibilityLabel("Push OP\(level)")
                .toggleStyle(ACCCheckboxStyle()).frame(width: 90)
            }.padding(.horizontal, 20).frame(height: 46)
          }
        }
        ACCDivider()
        Text(
          "OP5 is always kept. Delete is off until you configure it and moves mail to the account's Trash; Quarantine hides it in USS ACC only."
        ).font(.acc(17)).foregroundStyle(Color.accText).frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 12).padding(.vertical, 10)
      }.background(Color.black, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accBorder, lineWidth: 1.2))
      Text("CLASSIFIER EXAMPLES").font(.lcars(24)).foregroundStyle(Color.accLavender)
      HStack(spacing: 14) {
        ForEach(examples) { item in
          HStack(alignment: .top, spacing: 20) {
            Image(systemName: item.channelSymbol).font(.system(size: 26)).foregroundStyle(
              Color.accLavender)
            VStack(alignment: .leading, spacing: 4) {
              Text("\(item.name): \(item.preview)").font(.acc(22, weight: .medium)).lineLimit(1)
              (Text("Reason: ").foregroundStyle(Color.accPeach)
                + Text(item.classification?.reason ?? "").foregroundStyle(Color.accLavender))
                .font(.acc(18)).lineLimit(1)
            }
            Spacer(minLength: 6)
            OPBadge(level: item.classification?.level)
          }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accBorder, lineWidth: 1.2))
        }
        if examples.isEmpty {
          Text("No classified communications yet. Connect Mail, enable classification, or test a sample below.")
            .font(.acc(18)).foregroundStyle(Color.accDim)
        }
      }
      HStack(alignment: .top, spacing: 14) {
        VStack(alignment: .leading, spacing: 8) {
          Text("KNOWN SENDERS").font(.lcars(22)).foregroundStyle(Color.accLavender)
          TextEditor(text: $known).font(.system(size: 14, design: .monospaced))
            .scrollContentBackground(.hidden).padding(8).frame(height: 96)
            .background(Color.accField, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accBorder, lineWidth: 1.2))
          Text("One exact address per line. Required for automatic OP5. OP3–4 remain undefined.")
            .font(.acc(16)).foregroundStyle(Color.accDim)
        }
        VStack(alignment: .leading, spacing: 8) {
          Text("TEST SAMPLE").font(.lcars(22)).foregroundStyle(Color.accLavender)
          ACCField(placeholder: "Sample communication", text: $sample)
          Toggle(isOn: $sampleKnown) { Text("Sample sender is known").font(.acc(18)) }
            .toggleStyle(ACCCheckboxStyle())
          Text("Tests never apply dispositions or notify. Sender text cannot alter rules.")
            .font(.acc(16)).foregroundStyle(Color.accDim)
        }
      }
    }
  }
  func dispositionMenu(level: Int, index: Int) -> some View {
    Menu {
      ForEach(Disposition.allCases, id: \.self) { disposition in
        Button(disposition.rawValue) { draft.rules[index].disposition = disposition }
      }
    } label: {
      HStack {
        Text(draft.rules[index].disposition.rawValue).font(.acc(20))
        Spacer()
        Image(systemName: "chevron.down").font(.system(size: 14, weight: .semibold))
      }.foregroundStyle(Color.accText).padding(.horizontal, 14).frame(width: 170, height: 40)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.accBorder, lineWidth: 1.2))
    }.menuStyle(.button).buttonStyle(.plain).fixedSize().disabled(level == 5)
      .opacity(level == 5 ? 0.6 : 1).accessibilityLabel("OP\(level) disposition")
  }
  var connections: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: -2) {
        Text("CONNECTIONS").font(.lcars(54)).foregroundStyle(Color.accPeach)
        Text("Mail accounts, calendar, and on-device intelligence").font(.acc(24, weight: .medium))
          .foregroundStyle(Color.accLavender)
      }
      HStack(spacing: 10) {
        ACCButton(title: "ADD GMAIL", symbol: "envelope.badge", primary: true) {
          editing = AccountDraft(account: MailAccount(provider: .gmail, email: ""), isNew: true)
        }.fixedSize()
        ACCButton(title: "ADD IMAP ACCOUNT", symbol: "server.rack") {
          editing = AccountDraft(account: MailAccount(provider: .imap, email: ""), isNew: true)
        }.fixedSize()
        ACCButton(title: "IMPORT FROM APPLE MAIL", symbol: "square.and.arrow.down", kind: .outline) {
          importing = true
        }.fixedSize()
      }
      VStack(spacing: 0) {
        accountRow(
          symbol: "envelope.open", title: "Apple Mail", detail: "Automation · inbox of every Mail account",
          status: model.accountStatus[IntakeLedger.appleMail]
            ?? (model.mailConnected ? "Connected" : "Not connected")
        ) {
          if model.mailConnected {
            ACCButton(title: "DISCONNECT", kind: .outline, size: 16, height: 38) { model.disconnectMail() }
              .fixedSize()
          } else {
            ACCButton(title: "CONNECT", size: 16, height: 38) { Task { await model.connectMail() } }
              .fixedSize().disabled(model.busy)
          }
        }
        ForEach(model.accounts) { account in
          ACCDivider()
          accountRow(
            symbol: account.provider == .gmail ? "envelope.badge" : "server.rack",
            title: account.title,
            detail: "\(account.provider.title) · \(account.host):\(account.port)"
              + (account.importedFromAppleMail ? " · imported" : ""),
            status: !account.enabled
              ? "Paused"
              : model.hasPassword(account)
                ? (model.accountStatus[account.id] ?? "Waiting for first check") : "Needs password"
          ) {
            ACCButton(title: "EDIT", kind: .outline, size: 16, height: 38) {
              editing = AccountDraft(account: account, isNew: false)
            }.fixedSize()
            Button("REMOVE") { model.removeAccount(account.id) }.buttonStyle(.plain)
              .font(.lcars(16)).foregroundStyle(Color.accPeach)
          }
        }
      }.background(Color.black, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accBorder, lineWidth: 1.2))
      Text(
        "Accounts are checked every 60 seconds while USS ACC runs (newest 40 Inbox messages, read without marking them read). Passwords are stored in your login Keychain. Delete rules move mail to the account's Trash and never expunge."
      ).font(.acc(16)).foregroundStyle(Color.accDim)
      ACCDivider()
      Text("Calendar").font(.lcars(24)).foregroundStyle(Color.accLavender)
      Text(model.calendarStatus).font(.acc(16))
      ACCButton(title: "CONNECT CALENDAR", symbol: "calendar") {
        Task { await model.connectCalendar() }
      }.fixedSize()
      Text(
        "Reads the next 60 days. Calendar invitations can be imported into NAV as unconfirmed itinerary legs."
      ).font(.acc(16)).foregroundStyle(Color.accDim)
      ACCDivider()
      Text("Messages & phone").font(.lcars(24)).foregroundStyle(Color.accLavender)
      Text(
        "Compose and call actions open the configured system apps. Incoming message history, live calls, voicemail and call screening require additional provider integrations."
      ).font(.acc(19)).foregroundStyle(Color.accDim)
      Text("Apple Intelligence").font(.lcars(24)).foregroundStyle(Color.accLavender)
      Text(model.modelStatus).font(.acc(16))
      ACCButton(title: "REFRESH MODEL STATUS", symbol: "arrow.clockwise", kind: .outline) {
        model.modelStatus = Intelligence.availability
      }.fixedSize()
    }.sheet(item: $editing) { draft in
      AccountEditor(draft: draft).environmentObject(model)
    }.sheet(isPresented: $importing) {
      AppleMailImportSheet { picked in
        importing = false
        guard let first = picked.first else { return }
        // Let the import sheet finish dismissing before presenting the editor.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
          editing = AccountDraft(account: first, isNew: true, queue: Array(picked.dropFirst()))
        }
      }.environmentObject(model)
    }
  }
  func accountRow<Actions: View>(
    symbol: String, title: String, detail: String, status: String,
    @ViewBuilder actions: () -> Actions
  ) -> some View {
    HStack(spacing: 18) {
      Image(systemName: symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(
        Color.accLavender
      ).frame(width: 34)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.acc(22, weight: .medium)).lineLimit(1)
        Text(detail).font(.acc(16)).foregroundStyle(Color.accDim).lineLimit(1)
        Text(status).font(.acc(16)).foregroundStyle(
          status.hasPrefix("Checked") || status.hasPrefix("Connected")
            ? Color.accGreen : status == "Needs password" ? Color.accPeach : Color.accLavender
        ).lineLimit(2)
      }
      Spacer(minLength: 10)
      actions()
    }.padding(.horizontal, 18).padding(.vertical, 12)
  }
  var notifications: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("NOTIFICATIONS").font(.lcars(60)).foregroundStyle(Color.accPeach)
      Text(
        "Choose Push per OP level in Spam Filter, then save. macOS notification permission is requested when you first save a rule with Push enabled."
      ).font(.acc(20))
      Text(
        "Notifications show the sender and OP level, not the message body. Existing inbox imports and classification tests do not notify."
      ).font(.acc(20)).foregroundStyle(Color.accDim)
    }
  }
  var general: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("USS ACC").font(.lcars(60)).foregroundStyle(Color.accPeach)
      Text("Allen Control Center · 0.1.0").font(.lcars(24)).foregroundStyle(Color.accLavender)
      Text("BRIDGE / COMMS / EVENTS / NAV / DEV").font(.lcars(22)).foregroundStyle(
        Color.accLavender)
      Text(
        "Command–1 through Command–5 switches stations. Command–comma opens Settings. Demo content is fictional and never sent automatically."
      ).font(.acc(20))
      ACCButton(
        title: model.demo ? "SWITCH TO LIVE WORKSPACE" : "LOAD DEMO WORKSPACE", primary: true
      ) { if model.demo { model.useLive() } else { model.loadDemo() } }
      Text(
        "Filter policy and journey legs are saved in Application Support/USSACC. Mail bodies are not persisted. No cloud backend or analytics."
      ).font(.acc(16)).foregroundStyle(Color.accDim)
    }
  }
  func meaning(_ level: Int) -> String {
    switch level {
    case 5: "Known person · direct question"
    case 4, 3: "Not defined"
    case 2: "Other low-priority content"
    default: "Routine notices · late or needs attention"
    }
  }
}

struct ACCCheckboxStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy))
          .foregroundStyle(configuration.isOn ? Color.black : .clear)
          .frame(width: 26, height: 26)
          .background(
            configuration.isOn ? Color.accLavender : Color.black, in: RoundedRectangle(cornerRadius: 6)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Color.accLavender.opacity(0.8), lineWidth: 1.6))
        configuration.label
      }.contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityAddTraits(configuration.isOn ? .isSelected : [])
  }
}

struct AccountDraft: Identifiable {
  let id = UUID()
  var account: MailAccount
  var isNew: Bool
  /// Further imported accounts to review after this one.
  var queue: [MailAccount] = []
}

struct AccountEditor: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var model: AppModel
  @State var draft: AccountDraft
  @State private var password = ""
  @State private var result = ""
  @State private var testing = false
  @State private var port = "993"
  var account: MailAccount { draft.account }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(draft.isNew ? "ADD MAIL ACCOUNT" : "EDIT MAIL ACCOUNT").font(.lcars(34))
        .foregroundStyle(Color.accPeach)
      if !draft.queue.isEmpty {
        Text("\(draft.queue.count) more imported account\(draft.queue.count == 1 ? "" : "s") after this one")
          .font(.acc(16)).foregroundStyle(Color.accLavender)
      }
      Picker("Provider", selection: Binding(
        get: { account.provider },
        set: { provider in
          draft.account.provider = provider
          if let host = provider.host { draft.account.host = host }
          draft.account.port = 993
          port = "993"
        })
      ) {
        ForEach(MailProvider.allCases, id: \.self) { Text($0.title).tag($0) }
      }.pickerStyle(.segmented)
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
        field("Email", text: Binding(
          get: { account.email },
          set: { value in
            let followUser = draft.account.username.isEmpty || draft.account.username == draft.account.email
            draft.account.email = value.trimmingCharacters(in: .whitespaces)
            if followUser { draft.account.username = draft.account.email }
          }))
        field("Display name", text: $draft.account.name, prompt: "Optional")
        field("Username", text: $draft.account.username)
        if account.provider == .imap {
          field("IMAP server", text: $draft.account.host, prompt: "imap.example.com")
          field("TLS port", text: Binding(
            get: { port },
            set: { port = $0; draft.account.port = Int($0) ?? 0 }))
        }
        GridRow {
          Text("Password").font(.acc(18)).gridColumnAlignment(.trailing)
          SecureField(
            draft.isNew || !model.hasPassword(account) ? "App password" : "Leave blank to keep saved password",
            text: $password
          ).textFieldStyle(.roundedBorder).font(.acc(18))
        }
      }
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "key.fill").foregroundStyle(Color.accLavender)
        Text(account.provider.passwordHelp).font(.acc(16)).foregroundStyle(Color.accDim)
        if let url = account.provider.passwordURL {
          Link("Open", destination: url).font(.lcars(16))
        }
      }
      Toggle(isOn: $draft.account.enabled) { Text("Check this account").font(.acc(18)) }
        .toggleStyle(ACCCheckboxStyle())
      if !result.isEmpty {
        Text(result).font(.acc(17)).foregroundStyle(
          result.hasPrefix("Connected") ? Color.accGreen : Color.accPeach
        ).textSelection(.enabled)
      }
      HStack {
        Button(draft.queue.isEmpty ? "Cancel" : "Skip") { advance() }.buttonStyle(.plain)
          .font(.lcars(18)).foregroundStyle(Color.accLavender)
        Spacer()
        ACCButton(title: testing ? "TESTING…" : "TEST CONNECTION", symbol: "bolt.horizontal", kind: .outline) {
          testing = true
          result = ""
          Task {
            result = await model.testAccount(account, password: effectivePassword)
            testing = false
          }
        }.fixedSize().disabled(testing || effectivePassword.isEmpty || account.validationError != nil)
        ACCButton(title: "SAVE", primary: true) {
          model.saveAccount(account, password: password.isEmpty ? nil : password)
          advance()
        }.fixedSize().disabled(account.validationError != nil || (draft.isNew && password.isEmpty && !model.hasPassword(account)))
      }
      if let problem = account.validationError, !account.email.isEmpty {
        Text(problem).font(.acc(15)).foregroundStyle(Color.accPeach)
      }
    }.padding(28).frame(width: 640).background(Color.black).preferredColorScheme(.dark)
      .onAppear { port = String(account.port) }
  }
  var effectivePassword: String { password.isEmpty ? (model.password(for: account) ?? "") : password }
  func field(_ label: String, text: Binding<String>, prompt: String = "") -> some View {
    GridRow {
      Text(label).font(.acc(18)).gridColumnAlignment(.trailing)
      TextField(prompt.isEmpty ? label : prompt, text: text).textFieldStyle(.roundedBorder)
        .font(.acc(18)).autocorrectionDisabled()
    }
  }
  func advance() {
    if let next = draft.queue.first {
      draft = AccountDraft(account: next, isNew: true, queue: Array(draft.queue.dropFirst()))
      password = ""
      result = ""
      port = String(next.port)
    } else {
      dismiss()
    }
  }
}

struct AppleMailImportSheet: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var model: AppModel
  let onImport: ([MailAccount]) -> Void
  @State private var found: [MailAccount] = []
  @State private var selected: Set<String> = []
  @State private var message = "Reading accounts from Apple Mail…"
  @State private var loading = true
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("IMPORT FROM APPLE MAIL").font(.lcars(34)).foregroundStyle(Color.accPeach)
      Text(
        "Server settings are copied from Mail. Mail does not share passwords, so you'll enter an app password for each account next."
      ).font(.acc(17)).foregroundStyle(Color.accDim)
      if loading {
        ProgressView().controlSize(.small)
      }
      ForEach(found) { account in
        Toggle(isOn: Binding(
          get: { selected.contains(account.id) },
          set: { on in if on { selected.insert(account.id) } else { selected.remove(account.id) } })
        ) {
          VStack(alignment: .leading, spacing: 1) {
            Text(account.title).font(.acc(20, weight: .medium))
            Text("\(account.provider.title) · \(account.email) · \(account.host):\(account.port)")
              .font(.acc(15)).foregroundStyle(Color.accDim)
          }
        }.toggleStyle(ACCCheckboxStyle())
      }
      if !loading && found.isEmpty {
        Text(message).font(.acc(17)).foregroundStyle(Color.accLavender)
      }
      HStack {
        Button("Cancel") { dismiss() }.buttonStyle(.plain).font(.lcars(18))
          .foregroundStyle(Color.accLavender)
        Spacer()
        ACCButton(title: "CONTINUE", primary: true) {
          onImport(found.filter { selected.contains($0.id) })
        }.fixedSize().disabled(selected.isEmpty)
      }
    }.padding(28).frame(width: 600).background(Color.black).preferredColorScheme(.dark)
      .task {
        do {
          found = try await model.appleMailAccounts()
          selected = Set(found.map(\.id))
          message = "No IMAP, Gmail, or iCloud accounts found in Apple Mail that aren't already added. POP and Exchange accounts aren't supported."
        } catch {
          message = "Couldn't read Apple Mail: \(error.localizedDescription) Allow USS ACC under System Settings → Privacy & Security → Automation."
        }
        loading = false
      }
  }
}
