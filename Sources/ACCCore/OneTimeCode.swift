import Foundation

/// Verification / sign-in / MFA codes. The model proposes a code; these checks decide whether
/// it is believable, because a code message is pinned to the top and deleted after two hours.
public enum OneTimeCode {
  /// How long a code message is kept before it is moved to Trash.
  public static let lifetime: TimeInterval = 2 * 3600
  private static let keywords = try! NSRegularExpression(
    pattern:
      #"(?i)(code|verif|one[- ]?time|\botp\b|passcode|pass code|\b2fa\b|\bmfa\b|two[- ]?(factor|step)|sign[- ]?in|log[- ]?in|security|authenticat|confirm)"#
  )
  private static let digits = try! NSRegularExpression(pattern: #"\d{4,}|\d{3}[ -]\d{3}"#)
  /// Cheap pre-check: worth asking the model only if a code-like number sits next to code words.
  public static func isCandidate(subject: String, body: String) -> Bool {
    let text = subject + "\n" + String(body.prefix(6000))
    let range = NSRange(text.startIndex..., in: text)
    return keywords.firstMatch(in: text, range: range) != nil
      && digits.firstMatch(in: text, range: range) != nil
  }
  /// The model's answer, accepted only if it looks like a code and appears verbatim in the
  /// message (so it can't be invented). Returns nil otherwise.
  public static func validate(_ raw: String, subject: String, body: String) -> String? {
    let code = raw.trimmingCharacters(
      in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'`.:,;()[]")))
    guard (4...12).contains(code.count),
      code.unicodeScalars.allSatisfy({
        CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == " "
      }),
      code.unicodeScalars.allSatisfy({ $0.isASCII }),
      code.filter(\.isNumber).count >= 2,
      (subject + "\n" + body).contains(code)
    else { return nil }
    return code
  }
  public static func expired(_ date: Date, now: Date = .now) -> Bool {
    now.timeIntervalSince(date) > lifetime
  }
}
