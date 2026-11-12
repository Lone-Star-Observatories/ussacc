import Foundation
import Testing

@testable import ACCCore

@Suite struct OneTimeCodeTests {
  @Test func candidatesNeedCodeWordsAndCodeLikeNumbers() {
    #expect(OneTimeCode.isCandidate(subject: "Sign-in attempt", body: "Your code is 482913."))
    #expect(OneTimeCode.isCandidate(subject: "", body: "Use 482 913 to verify your account"))
    #expect(!OneTimeCode.isCandidate(subject: "Lunch?", body: "See you at noon"))
    #expect(!OneTimeCode.isCandidate(subject: "Invoice 2024", body: "Thanks for your order"))
  }
  @Test func codesMustAppearVerbatimAndLookLikeCodes() {
    let body = "Your verification code is G-482913. It expires in 10 minutes."
    #expect(OneTimeCode.validate("G-482913", subject: "", body: body) == "G-482913")
    #expect(OneTimeCode.validate(" \"G-482913\". ", subject: "", body: body) == "G-482913")
    #expect(OneTimeCode.validate("123456", subject: "", body: body) == nil)  // not in message
    #expect(OneTimeCode.validate("", subject: "", body: body) == nil)
    #expect(OneTimeCode.validate("verification", subject: "", body: body) == nil)
    #expect(OneTimeCode.validate("X7K9QP", subject: "Code X7K9QP", body: "") == "X7K9QP")
  }
  @Test func codesExpireAfterTwoHours() {
    let now = Date()
    #expect(!OneTimeCode.expired(now.addingTimeInterval(-3600), now: now))
    #expect(OneTimeCode.expired(now.addingTimeInterval(-2 * 3600 - 1), now: now))
  }
  @Test func ledgerKeepsCodesAndLoadsOlderFiles() throws {
    var ledger = IntakeLedger()
    ledger.codes["m1"] = "482913"
    ledger.dismissedCodes = ["m2"]
    let round = try JSONDecoder().decode(IntakeLedger.self, from: JSONEncoder().encode(ledger))
    #expect(round.codes == ["m1": "482913"] && round.dismissedCodes == ["m2"])
    let old = try JSONDecoder().decode(IntakeLedger.self, from: Data(#"{"seenIDs":["a"]}"#.utf8))
    #expect(old.codes.isEmpty && old.seenIDs == ["a"])
  }
}
