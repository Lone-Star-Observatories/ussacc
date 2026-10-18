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
    model.communications.filter {
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
    HStack(alignment: .top, spacing: 14) {
      ACCPanel {
        HStack {
          TextField("Search conversations…", text: $search).textFieldStyle(.roundedBorder)
          Button {
            newConversation = true
          } label: {
            Image(systemName: "plus")
          }.help("New conversation")
        }
        Picker("View", selection: $quarantine) {
          Text("Inbox").tag(false)
          Text("Quarantine").tag(true)
        }.pickerStyle(.segmented)
        ScrollView {
          LazyVStack(spacing: 5) {
            ForEach(people) { item in
              Button {
                model.selectedIdentity = item.identity
              } label: {
                HStack(alignment: .top, spacing: 11) {
                  Avatar(name: item.name)
                  VStack(alignment: .leading, spacing: 6) {
                    HStack {
                      Text(item.name).font(.headline)
                      Spacer()
                      OPBadge(level: item.classification?.level)
                    }
                    Text(item.subject.isEmpty ? item.body : item.subject).font(.caption).lineLimit(
                      2)
                    HStack {
                      Text(item.channel.rawValue.uppercased()).font(.lcars(10))
                      Spacer()
                      Text(item.date, style: .time).font(.caption2)
                    }.foregroundStyle(Color.accLavender)
                  }
                }.padding(12).background(
                  model.selectedIdentity == item.identity
                    ? Color.accLavender.opacity(0.22) : Color.clear,
                  in: RoundedRectangle(cornerRadius: 12))
              }.buttonStyle(.plain)
              Divider()
            }
          }
        }
        if people.isEmpty {
          Text(quarantine ? "No quarantined communications." : "No communications yet.").font(
            .callout
          ).foregroundStyle(.secondary)
        }
        if !model.demo {
          Text("Apple Mail inbox is supported. Messages and calls use system handoff.").font(
            .caption
          ).foregroundStyle(.secondary)
          ACCButton(
            title: model.mailConnected ? "REFRESH MAIL" : "CONNECT APPLE MAIL", symbol: "envelope"
          ) { Task { await model.connectMail() } }.disabled(model.busy)
        }
      }.frame(width: 340)
      ACCPanel {
        if let selected {
          HStack(alignment: .top) {
            Avatar(name: selected.name)
            VStack(alignment: .leading, spacing: 5) {
              Text(selected.name).font(.lcars(25))
              Text(selected.address).font(.caption).foregroundStyle(Color.accLavender)
                .textSelection(.enabled)
            }
            Spacer()
            ACCButton(title: "CALL", symbol: "phone") {
              mode = .call
              newConversation = true
            }
          }
          Divider().overlay(Color.accLavender)
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
              ForEach(thread) { item in
                VStack(alignment: .leading, spacing: 10) {
                  HStack {
                    Image(
                      systemName: item.channel == .email
                        ? "envelope" : item.channel == .call ? "phone" : "bubble.left")
                    Text(item.channel.rawValue.uppercased()).font(.lcars(13))
                    Text(item.date, style: .time).font(.caption)
                    Spacer()
                    OPBadge(level: item.classification?.level)
                  }.foregroundStyle(Color.accLavender)
                  if !item.subject.isEmpty { Text(item.subject).font(.headline) }
                  Text(item.body).font(.system(size: 14)).textSelection(.enabled)
                  if let classification = item.classification {
                    Text(classification.reason).font(.caption).foregroundStyle(.secondary)
                    Text(classification.source).font(.caption2).foregroundStyle(.secondary)
                  }
                  HStack {
                    Button("CLASSIFY") { Task { await model.classify(id: item.id) } }.font(
                      .lcars(10))
                    Menu("CORRECT SCORE") {
                      ForEach(1...5, id: \.self) { level in
                        Button("OP\(level)") { model.correctScore(item.id, level: level) }
                      }
                    }.font(.lcars(10)).fixedSize()
                    if item.quarantined {
                      Button("RESTORE") { model.restore(item.id) }.font(.lcars(10))
                    }
                  }
                }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(
                  Color.accPanel, in: RoundedRectangle(cornerRadius: 13)
                ).overlay(
                  RoundedRectangle(cornerRadius: 13).stroke(
                    item.classification?.level.map { model.policy.rule(for: $0).highlight } == true
                      ? Color.accPeach : Color.clear))
              }
            }
          }
          Divider()
          HStack {
            Picker("Send as", selection: $mode) {
              Text("Message").tag(Channel.message)
              Text("Email").tag(Channel.email)
            }.frame(width: 180)
            TextField("Write a reply…", text: $draft).textFieldStyle(.roundedBorder)
            ACCButton(title: "COMPOSE", primary: true) {
              destination = mode == .email ? selected.address : ""
              newConversation = true
            }
          }
          Text("Opens the system app to review and send. Drafts are never sent automatically.")
            .font(.caption2).foregroundStyle(.secondary)
        } else {
          EmptyStation(
            symbol: "bubble.left.and.bubble.right", title: "SELECT A CONVERSATION",
            detail: "Email, messages, and call activity share a single workspace.")
        }
      }
    }.sheet(isPresented: $newConversation) {
      ComposeSheet(
        mode: mode,
        destination: destination.isEmpty && mode == .email
          ? (selected?.address ?? "") : destination, bodyText: draft
      ).environmentObject(model)
    }
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
