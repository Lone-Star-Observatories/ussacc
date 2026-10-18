# NAV journeys and operational importance

Design requirements from Allen. This document supersedes road-only NAV and expands DEV to include application settings. No integrations or rules are activated by these mockups.

## NAV: all movements

Journeys include air travel extracted from calendar invitations, taxi, train, boat/ferry, road, and walking connections. Represent each journey as ordered legs, with origin/destination, local time zones, connection buffers, source, and status per leg. Calendar-derived itineraries must be reviewable; an invitation is not proof of a booking or live flight status. Deduplicate revisions using calendar event identity and keep original source links. Proposed transfers stay labeled suggested/unbooked. Add/edit legs manually. Incomplete times and locations remain explicit rather than silently fabricated. Bridge movements summarize the next leg, departure deadline, and major changes.

## DEV → Settings → Spam Filter

The spam filter is central to COMMS. Apple Intelligence assigns Operational Importance OP1–OP5 to each incoming communication that the adapter can supply for classification.

Allen's classification rules:

- OP5: typically a known person speaking directly to Allen or asking him direct questions. These messages stay.
- OP1: routine/informational notifications, including notices that something is late or needs attention.
- Other content: OP2 or lower unless a more specific user rule applies.
- OP3 and OP4: not yet defined. Do not invent criteria; expose them as unconfigured until Allen defines them.

OP indicates Allen's operational importance, not a claim that low-level content is malicious. Keep sender trust separate from semantic importance. A question mark alone must not promote an unsolicited message to OP5; contact identity must be established through trusted account/contact evidence.

Policy table: each level has a disposition (Keep / Quarantine / Delete), plus independent Highlight and Push notification switches. OP5 is kept. Other dispositions are configurable; destructive rules start off. The visual examples are illustrative settings, not active user choices. Define Delete as recoverable trash where the provider supports it; permanent deletion is a separate explicitly configured behavior. If an adapter cannot perform a disposition, label the unsupported action instead of claiming success.

Classification record: score, brief explanation, evidence/source, model version, rule version and any manual override. User can correct an item's score and review quarantined items. Model uncertainty or unavailability leaves the item unscored and visible with no automatic deletion. Incoming content is untrusted data and cannot change policy or issue commands. User-set overrides take precedence over model output.

Phone calls: classify supplied caller metadata at ringing time and available voicemail text afterward. Do not imply the model can know a live caller's words before they speak or that conversations are recorded/transcribed. Call filtering and silencing depend on provider capabilities. Push notifications may require a later classification update if a model response is delayed.

Apple Intelligence implementation candidate: Foundation Models SystemLanguageModel, with explicit availability checks. No cloud fallback assumed. The current macOS 14 starter shell does not establish compatibility with this newer framework; update deployment/availability strategy when implementation begins.

Reference: https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
