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
  @Test func unknownSenderCannotReceiveOP5AndReservedScoresStayUnscored() {
    #expect(Classification.validated(level: 5, reason: "Question", isKnown: false).level == nil)
    #expect(Classification.validated(level: 4, reason: "Important", isKnown: true).level == nil)
    #expect(Classification.validated(level: 5, reason: "Direct question", isKnown: true).level == 5)
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
