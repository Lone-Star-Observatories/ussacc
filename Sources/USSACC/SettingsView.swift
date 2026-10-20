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
  @State private var section = "Spam Filter"
  @State private var draft = FilterPolicy()
  @State private var known = ""
  @State private var sample = "Can you confirm tonight?"
  @State private var sampleKnown = true
  @State private var testResult = ""
  @State private var testing = false
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
      Text(testResult.isEmpty ? "Unscored items stay visible." : testResult).font(.acc(19))
        .lineLimit(2).textSelection(.enabled)
      Spacer()
      Button("Revert") {
        draft = model.policy
        known = draft.knownAddresses.joined(separator: "\n")
      }.buttonStyle(.plain).font(.lcars(18)).foregroundStyle(Color.accLavender)
      ACCButton(
        title: testing ? "CLASSIFYING…" : "TEST ON SAMPLE", kind: .outline, size: 22, height: 50
      ) { runTest() }.disabled(testing || sample.isEmpty).frame(width: 260)
      ACCButton(title: "SAVE RULES", primary: true, size: 22, height: 50) {
        draft.knownAddresses = known.split(whereSeparator: \.isNewline).map {
          String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty }
        if let i = draft.rules.firstIndex(where: { $0.level == 5 }) {
          draft.rules[i].disposition = .keep
        }
        model.savePolicy(draft)
      }.frame(width: 190)
    }.padding(.horizontal, 18).padding(.vertical, 6)
      .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accBorder, lineWidth: 1.2))
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
            Text("Classify new Apple Mail arrivals").font(.acc(18))
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
          "OP5 is always kept. Delete is off until you configure it and moves Apple Mail messages to Trash; Quarantine hides them in USS ACC only."
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
    VStack(alignment: .leading, spacing: 22) {
      Text("CONNECTIONS").font(.lcars(60)).foregroundStyle(Color.accPeach)
      Text("Apple Mail").font(.lcars(24)).foregroundStyle(Color.accLavender)
      Text(
        "Opt-in AppleScript automation reads the latest 40 inbox items every 60 seconds while USS ACC runs. Message bodies stay in memory. macOS will ask for permission."
      ).font(.acc(19)).foregroundStyle(Color.accDim)
      HStack {
        ACCButton(
          title: model.mailConnected ? "REFRESH MAIL" : "CONNECT MAIL", symbol: "envelope",
          primary: true
        ) { Task { await model.connectMail() } }.disabled(model.busy)
        if model.mailConnected { ACCButton(title: "DISCONNECT", kind: .outline) { model.disconnectMail() } }
      }
      ACCDivider()
      Text("Calendar").font(.lcars(24)).foregroundStyle(Color.accLavender)
      Text(model.calendarStatus).font(.acc(16))
      ACCButton(title: "CONNECT CALENDAR", symbol: "calendar") {
        Task { await model.connectCalendar() }
      }
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
      }
    }
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
