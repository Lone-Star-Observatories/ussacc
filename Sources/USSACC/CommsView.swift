import ACCCore
import SwiftUI

struct CommsView: View {
  @EnvironmentObject private var model: AppModel
  @State private var search = ""
  @State private var quarantine = false
  @State private var newConversation = false
  @State private var draft = ""
  @State private var mode: Channel = .message
  @State private var destination = ""
  var items: [Communication] {
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
    return items.sorted { $0.date > $1.date }.filter { seen.insert($0.identity).inserted }
  }
  var thread: [Communication] {
    items.filter { $0.identity == model.selectedIdentity }.sorted { $0.date < $1.date }
  }
  var selected: Communication? { thread.last }
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      list.frame(width: 450).frame(maxHeight: .infinity)
      conversation.frame(maxHeight: .infinity)
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
      HStack(spacing: 12) {
        ACCField(placeholder: "Search conversations…", text: $search, symbol: "magnifyingglass")
        ACCButton(title: "NEW CONVERSATION", symbol: "plus", primary: true) {
          destination = ""
          newConversation = true
        }.fixedSize()
      }
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(Array(people.enumerated()), id: \.element.id) { index, item in
            let isSelected = model.selectedIdentity == item.identity
            Button {
              model.selectedIdentity = item.identity
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
                    Text(item.preview).font(.acc(19)).foregroundStyle(Color.accDim).lineLimit(1)
                    Spacer(minLength: 6)
                    if let level = item.classification?.level {
                      Text("OP\(level)").font(.lcars(14)).foregroundStyle(
                        level == 5 ? Color.accPeach : Color.accLavender)
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
            }.buttonStyle(.plain)
            if index < people.count - 1, !isSelected,
              people[index + 1].identity != model.selectedIdentity
            {
              ACCDivider().padding(.horizontal, 10)
            } else {
              Color.clear.frame(height: 1)
            }
          }
        }
      }
      if people.isEmpty {
        Text(quarantine ? "No quarantined communications." : "No communications yet.")
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
      if let selected {
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
          HStack(spacing: 14) {
            if let classification = item.classification {
              Text("\(classification.reason) · \(classification.source)").font(.acc(15))
                .foregroundStyle(Color.accDim).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("CLASSIFY") { Task { await model.classify(id: item.id) } }
            Menu("CORRECT SCORE") {
              ForEach(1...5, id: \.self) { level in
                Button("OP\(level)") { model.correctScore(item.id, level: level) }
              }
            }.menuStyle(.borderlessButton).fixedSize()
            if item.quarantined { Button("RESTORE") { model.restore(item.id) } }
          }.font(.lcars(15)).foregroundStyle(Color.accLavender).buttonStyle(.plain)
        }.padding(.horizontal, 26).padding(.vertical, 16)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.accCard, in: RoundedRectangle(cornerRadius: 12))
          .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(
              highlighted ? Color.accPeach : Color.accBorder, lineWidth: highlighted ? 1.6 : 1.2))
      }.padding(.bottom, 22)
    }
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
