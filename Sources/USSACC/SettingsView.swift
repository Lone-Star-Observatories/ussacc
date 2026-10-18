import ACCCore
import SwiftUI

struct DevView: View {
  @EnvironmentObject private var model: AppModel
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Button("TERMINAL") { model.settings = false }.buttonStyle(.bordered).tint(
          model.settings ? .accLavender : .accPeach)
        Button("SETTINGS") { model.settings = true }.buttonStyle(.bordered).tint(
          model.settings ? .accPeach : .accLavender)
        Spacer()
      }.font(.lcars(15))
      if model.settings { SettingsView() } else { TerminalWorkspace() }
    }
  }
}
struct SettingsView: View {
  @EnvironmentObject private var model: AppModel
  @State private var section = "Spam Filter"
  @State private var draft = FilterPolicy()
  @State private var known = ""
  @State private var sample = "Can you confirm tonight?"
  @State private var sampleKnown = true
  @State private var testResult = ""
  @State private var testing = false
  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      ACCPanel {
        ForEach(["General", "Connections", "Spam Filter", "Notifications"], id: \.self) { title in
          Button {
            section = title
          } label: {
            Text(title).font(.lcars(17)).frame(maxWidth: .infinity, alignment: .leading).padding(14)
              .foregroundStyle(section == title ? Color.black : Color.accText).background(
                section == title ? Color.accPeach : Color.accPanel,
                in: RoundedRectangle(cornerRadius: 11))
          }.buttonStyle(.plain)
        }
        Spacer()
      }.frame(width: 195)
      ACCPanel {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            switch section {
            case "Spam Filter": filter
            case "Connections": connections
            case "Notifications": notifications
            default: general
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
        if section == "Spam Filter" {
          HStack {
            ACCButton(title: "SAVE RULES", symbol: "checkmark", primary: true) {
              draft.knownAddresses = known.split(whereSeparator: \.isNewline).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
              }.filter { !$0.isEmpty }
              if let i = draft.rules.firstIndex(where: { $0.level == 5 }) {
                draft.rules[i].disposition = .keep
              }
              model.savePolicy(draft)
            }
            Button("Revert") {
              draft = model.policy
              known = draft.knownAddresses.joined(separator: "\n")
            }
          }
        }
      }
    }.onAppear {
      draft = model.policy
      known = draft.knownAddresses.joined(separator: "\n")
    }
  }
  var filter: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("SPAM FILTER").font(.lcars(31)).foregroundStyle(Color.accPeach)
      Text("Operational Importance · Apple Intelligence").foregroundStyle(Color.accLavender)
      Text(model.modelStatus).font(.caption).textSelection(.enabled)
      Toggle("Classify new incoming Apple Mail communications", isOn: $draft.enabled)
      Text(
        "First connection imports existing inbox items without deleting or notifying. Saved rules apply to subsequent new arrivals. Quarantine hides messages in USS ACC; Delete moves Apple Mail messages to Trash."
      ).font(.caption).foregroundStyle(.secondary)
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 15) {
        GridRow {
          Text("LEVEL")
          Text("MEANING")
          Text("DISPOSITION")
          Text("HIGHLIGHT")
          Text("PUSH")
        }.font(.lcars(11)).foregroundStyle(Color.accLavender)
        ForEach((1...5).reversed(), id: \.self) { level in
          GridRow {
            OPBadge(level: level)
            Text(meaning(level)).font(.system(size: 12)).frame(
              maxWidth: .infinity, alignment: .leading)
            if let index = draft.rules.firstIndex(where: { $0.level == level }) {
              Picker("OP\(level) disposition", selection: $draft.rules[index].disposition) {
                ForEach(Disposition.allCases, id: \.self) { Text($0.rawValue).tag($0) }
              }.labelsHidden().frame(width: 120).disabled(level == 5)
              Toggle("Highlight OP\(level)", isOn: $draft.rules[index].highlight).labelsHidden()
                .toggleStyle(.checkbox)
              Toggle("Push OP\(level)", isOn: $draft.rules[index].push).labelsHidden().toggleStyle(
                .checkbox)
            }
          }
          Divider()
        }
      }
      Text("Known sender addresses — one exact address per line").font(.headline)
      TextEditor(text: $known).font(.system(size: 12, design: .monospaced)).frame(height: 75)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accLavender.opacity(0.4)))
      Text(
        "Known identity is required for automatic OP5. OP3–4 remain undefined. Unscored items stay visible. Rules cannot delete OP5."
      ).font(.caption).foregroundStyle(.secondary)
      Divider()
      Text("TEST CLASSIFICATION").font(.lcars(19)).foregroundStyle(Color.accPeach)
      TextField("Sample communication", text: $sample).textFieldStyle(.roundedBorder)
      Toggle("Sample sender is known", isOn: $sampleKnown)
      ACCButton(title: testing ? "CLASSIFYING…" : "TEST ON SAMPLE", symbol: "sparkles") {
        testing = true
        Task {
          let item = Communication(
            name: "Sample", address: "sample@example.com", channel: .email, body: sample,
            isDemo: true)
          let result = await Intelligence.classify(item, known: sampleKnown)
          testResult = "\(result.level.map { "OP\($0)" } ?? "Unscored"): \(result.reason)"
          testing = false
        }
      }.disabled(testing || sample.isEmpty)
      Text(testResult).font(.callout).textSelection(.enabled)
      Text("Tests never apply dispositions or send notifications. Sender text cannot alter rules.")
        .font(.caption).foregroundStyle(.secondary)
    }
  }
  var connections: some View {
    VStack(alignment: .leading, spacing: 22) {
      Text("CONNECTIONS").font(.lcars(30)).foregroundStyle(Color.accPeach)
      Text("Apple Mail").font(.headline)
      Text(
        "Opt-in AppleScript automation reads the latest 40 inbox items every 60 seconds while USS ACC runs. Message bodies stay in memory. macOS will ask for permission."
      ).font(.callout).foregroundStyle(.secondary)
      HStack {
        ACCButton(
          title: model.mailConnected ? "REFRESH MAIL" : "CONNECT MAIL", symbol: "envelope",
          primary: true
        ) { Task { await model.connectMail() } }.disabled(model.busy)
        if model.mailConnected { Button("Disconnect") { model.disconnectMail() } }
      }
      Divider()
      Text("Calendar").font(.headline)
      Text(model.calendarStatus).font(.caption)
      ACCButton(title: "CONNECT CALENDAR", symbol: "calendar") {
        Task { await model.connectCalendar() }
      }
      Text(
        "Reads the next 60 days. Calendar invitations can be imported into NAV as unconfirmed itinerary legs."
      ).font(.caption).foregroundStyle(.secondary)
      Divider()
      Text("Messages & phone").font(.headline)
      Text(
        "Compose and call actions open the configured system apps. Incoming message history, live calls, voicemail and call screening require additional provider integrations."
      ).font(.callout).foregroundStyle(.secondary)
      Text("Apple Intelligence").font(.headline)
      Text(model.modelStatus).font(.caption)
      Button("Refresh model availability") { model.modelStatus = Intelligence.availability }
    }
  }
  var notifications: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("NOTIFICATIONS").font(.lcars(30)).foregroundStyle(Color.accPeach)
      Text(
        "Choose Push per OP level in Spam Filter, then save. macOS notification permission is requested when you first save a rule with Push enabled."
      )
      Text(
        "Notifications show the sender and OP level, not the message body. Existing inbox imports and classification tests do not notify."
      ).foregroundStyle(.secondary)
    }
  }
  var general: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("USS ACC").font(.lcars(32)).foregroundStyle(Color.accPeach)
      Text("Allen Control Center · 0.1.0").font(.headline)
      Text("BRIDGE / COMMS / EVENTS / NAV / DEV").font(.lcars(16)).foregroundStyle(
        Color.accLavender)
      Text(
        "Command–1 through Command–5 switches stations. Command–comma opens Settings. Demo content is fictional and never sent automatically."
      )
      ACCButton(
        title: model.demo ? "SWITCH TO LIVE WORKSPACE" : "LOAD DEMO WORKSPACE", primary: true
      ) { if model.demo { model.useLive() } else { model.loadDemo() } }
      Text(
        "Filter policy and journey legs are saved in Application Support/USSACC. Mail bodies are not persisted. No cloud backend or analytics."
      ).font(.caption).foregroundStyle(.secondary)
    }
  }
  func meaning(_ level: Int) -> String {
    switch level {
    case 5: "Known person · direct communication"
    case 4, 3: "Not defined"
    case 2: "Other low-priority content"
    default: "Routine notices · late / needs attention"
    }
  }
}
