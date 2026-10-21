import Foundation
import Testing

@testable import ACCCore

@Suite struct PolicyTests {
  @Test func op5AlwaysStaysEvenWithMalformedPersistedRule() {
    var policy = FilterPolicy()
    policy.enabled = true
    policy.rules = [LevelRule(level: 5, disposition: .delete, highlight: true, push: true)]
    let result = PolicyDecision.evaluate(item(level: 5), policy: policy)
    #expect(result.disposition == .keep)
    #expect(result.highlight)
    #expect(result.notify)
  }
  @Test func unscoredAndDisabledNeverDelete() {
    var policy = FilterPolicy()
    policy.rules = (0...5).map { LevelRule(level: $0, disposition: .delete, push: true) }
    #expect(PolicyDecision.evaluate(item(level: 1), policy: policy).disposition == .keep)
    policy.enabled = true
    #expect(
      PolicyDecision.evaluate(item(level: nil), policy: policy)
        == PolicyDecision(disposition: .keep, highlight: false, notify: false))
    #expect(PolicyDecision.evaluate(item(level: 1), policy: policy).disposition == .delete)
  }
  @Test func unknownSenderCannotReceiveOP5AndUndefinedLevelsStayUnscored() {
    #expect(Classification.validated(level: 5, reason: "Question", isKnown: false).level == nil)
    #expect(Classification.validated(level: 5, reason: "Direct question", isKnown: true).level == 5)
    #expect(Classification.validated(level: 4, reason: "Urgent invite", isKnown: false).level == 4)
    var policy = FilterPolicy()
    policy.rules[3].meaning = "  "  // OP4 cleared
    #expect(policy.definedLevels == [1, 2, 3, 5])
    #expect(
      Classification.validated(
        level: 4, reason: "Urgent", isKnown: true, allowed: policy.definedLevels
      ).level == nil)
    #expect(Classification.validated(level: 9, reason: "x", isKnown: true).level == nil)
  }
  @Test func meaningsDefaultAndOlderPoliciesGainDefaults() throws {
    let policy = FilterPolicy()
    #expect(policy.meaning(for: 5) == "Direct question or email of personal nature")
    #expect(policy.meaning(for: 1) == "Unactionable garbage")
    let legacy = Data(
      #"{"enabled":true,"knownAddresses":[],"rules":[{"level":2,"disposition":"Quarantine","highlight":false,"push":false}]}"#
        .utf8)
    let restored = try JSONDecoder().decode(FilterPolicy.self, from: legacy)
    #expect(restored.rules[0].meaning == "Eblasts, newsletters, regular emails")
    #expect(restored.rules[0].disposition == .quarantine)
  }
  @Test func knownIdentityUsesExactAddressNotDisplayNameOrSubstring() {
    var policy = FilterPolicy()
    policy.knownAddresses = [" Jamie@Example.com "]
    #expect(policy.isKnown("jamie@example.com"))
    #expect(!policy.isKnown("fakejamie@example.com"))
    #expect(!policy.isKnown("Jamie"))
  }
  @Test func calendarCandidatesAreUnconfirmedAndDeduplicated() throws {
    let entry = CalendarEntry(
      id: "event-1", title: "Flight AUS → SEA", start: .now, end: .now.addingTimeInterval(3600),
      location: "Seattle")
    let candidate = try #require(JourneyImport.candidate(entry))
    #expect(candidate.mode == .air)
    #expect(!candidate.reviewed)
    #expect(JourneyImport.merge(existing: [candidate], candidates: [candidate]).count == 1)
    let nonTravel = CalendarEntry(
      id: "x", title: "Flightless bird presentation", start: .now, end: .now)
    #expect(JourneyImport.candidate(nonTravel) == nil)
  }
  @Test func reviewedJourneyNotOverwrittenOnCalendarRefresh() {
    var leg = JourneyLeg(
      id: "calendar:a", mode: .air, origin: "AUS", destination: "SEA", departure: .now,
      arrival: .now, reviewed: true)
    let saved = leg
    leg.destination = "Changed"
    leg.reviewed = false
    #expect(JourneyImport.merge(existing: [saved], candidates: [leg]) == [saved])
  }
  @Test func policyRoundTrip() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("policy.json")
    var policy = FilterPolicy()
    policy.rules[0].disposition = .quarantine
    try LocalPersistence.save(policy, to: url)
    #expect(try LocalPersistence.load(FilterPolicy.self, from: url) == policy)
  }
  private func item(level: Int?) -> Communication {
    Communication(
      name: "Jamie", address: "jamie@example.com", channel: .email, body: "Hello",
      classification: .init(level: level, reason: "Test", source: "Test"))
  }
}
@Suite struct IntakeTests {
  @Test func baselineNeverActionsOldMessagesAndReconnectDoesNotReplay() throws {
    var ledger = IntakeLedger()
    #expect(ledger.receive(["old-a", "old-b"]).isEmpty)
    #expect(ledger.receive(["new", "old-a"]) == ["new"])
    let bytes = try JSONEncoder().encode(ledger)
    var restored = try JSONDecoder().decode(IntakeLedger.self, from: bytes)
    #expect(restored.receive(["new", "old-b"]).isEmpty)
    #expect(restored.receive(["next"]) == ["next"])
  }
}

@Test func eventNotesSplitIntoSummaryAndReminders() {
  let event = CalendarEntry(
    id: "e", title: "Session", start: .now, end: .now,
    notes: "Telescope operations.\n- Charge batteries\n• Pack new filter\n")
  #expect(event.summary == "Telescope operations.")
  #expect(event.reminders == ["Charge batteries", "Pack new filter"])
  #expect(CalendarEntry(id: "x", title: "", start: .now, end: .now).reminders.isEmpty)
}

@Test func sessionPreferencesRoundTripAndTolerateMissingKeys() throws {
  var prefs = SessionPreferences()
  prefs.live = true
  prefs.calendar = true
  let restored = try JSONDecoder().decode(
    SessionPreferences.self, from: JSONEncoder().encode(prefs))
  #expect(restored == prefs)
  let partial = try JSONDecoder().decode(SessionPreferences.self, from: Data(#"{"live":true}"#.utf8))
  #expect(partial.live && !partial.appleMail && !partial.calendar)
}

@Test func retroactivePlanAppliesSavedRulesButKeepsOP5UnscoredAndDemo() {
  var policy = FilterPolicy()
  policy.enabled = false  // retroactive runs are explicit and ignore the automatic toggle
  for i in policy.rules.indices { policy.rules[i].disposition = .delete }
  policy.rules[1].disposition = .quarantine  // OP2
  func item(_ id: String, _ level: Int?, demo: Bool = false, quarantined: Bool = false) -> Communication {
    var c = Communication(
      id: id, name: "x", address: "x@y.z", channel: .email, body: "",
      classification: level.map { .init(level: $0, reason: "", source: "t") }, isDemo: demo)
    c.quarantined = quarantined
    return c
  }
  let plan = RetroactivePlan.make(
    [item("a", 5), item("b", 1), item("c", nil), item("d", 2), item("e", 2, quarantined: true),
     item("f", 1, demo: true)], policy: policy)
  #expect(plan.entries.map(\.id) == ["a", "b", "c", "d", "e"])
  #expect(plan.entries.first { $0.id == "a" }?.disposition == .keep)
  #expect(plan.entries.first { $0.id == "c" }?.disposition == .keep)
  #expect(plan.count(.delete) == 1 && plan.count(.quarantine) == 1 && plan.count(.keep) == 3)
  #expect(plan.actions.map(\.id) == ["b", "d"])
}
