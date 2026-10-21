import Foundation

public struct PsyCountry: Identifiable, Hashable, Codable, Sendable {
  public var code: String
  public var name: String
  public var id: String { code }
  /// Regional-indicator flag emoji from the ISO code.
  public var flag: String {
    code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }
      .map(String.init).joined()
  }
  public var wikipediaTitle: String { Self.wikiOverrides[code] ?? name }
  static let wikiOverrides = [
    "GE": "Georgia (country)", "IE": "Republic of Ireland", "CG": "Republic of the Congo",
    "CD": "Democratic Republic of the Congo", "GM": "The Gambia", "BS": "The Bahamas",
    "MK": "North Macedonia", "PS": "State of Palestine", "VA": "Vatican City",
    "FM": "Federated States of Micronesia", "TL": "East Timor",
  ]
}

public enum CelestialKind: String, Codable, Sendable, CaseIterable {
  case planet, dwarfPlanet, moon, starbase, station
  public var label: String {
    switch self {
    case .planet: "Planet"
    case .dwarfPlanet: "Dwarf planet"
    case .moon: "Moon"
    case .starbase: "Starbase"
    case .station: "Station"
    }
  }
}

public struct CelestialBody: Identifiable, Hashable, Codable, Sendable {
  public var name: String
  public var kind: CelestialKind
  /// false = real astronomy (Wikipedia), true = Star Trek canon (Memory Alpha).
  public var trek: Bool
  /// Article title in the matching wiki.
  public var article: String
  public var id: String { (trek ? "trek:" : "real:") + name }
  public init(_ name: String, _ kind: CelestialKind, trek: Bool, article: String? = nil) {
    self.name = name
    self.kind = kind
    self.trek = trek
    self.article = article ?? name
  }
}

public enum PsyartCatalog {
  /// The 193 UN member states plus the two observer states.
  public static let countries: [PsyCountry] = """
    AF Afghanistan|AL Albania|DZ Algeria|AD Andorra|AO Angola|AG Antigua and Barbuda|AR Argentina|AM Armenia|AU Australia|AT Austria|AZ Azerbaijan|BS Bahamas|BH Bahrain|BD Bangladesh|BB Barbados|BY Belarus|BE Belgium|BZ Belize|BJ Benin|BT Bhutan|BO Bolivia|BA Bosnia and Herzegovina|BW Botswana|BR Brazil|BN Brunei|BG Bulgaria|BF Burkina Faso|BI Burundi|CV Cape Verde|KH Cambodia|CM Cameroon|CA Canada|CF Central African Republic|TD Chad|CL Chile|CN China|CO Colombia|KM Comoros|CG Republic of the Congo|CD DR Congo|CR Costa Rica|CI Ivory Coast|HR Croatia|CU Cuba|CY Cyprus|CZ Czech Republic|DK Denmark|DJ Djibouti|DM Dominica|DO Dominican Republic|EC Ecuador|EG Egypt|SV El Salvador|GQ Equatorial Guinea|ER Eritrea|EE Estonia|SZ Eswatini|ET Ethiopia|FJ Fiji|FI Finland|FR France|GA Gabon|GM Gambia|GE Georgia|DE Germany|GH Ghana|GR Greece|GD Grenada|GT Guatemala|GN Guinea|GW Guinea-Bissau|GY Guyana|HT Haiti|HN Honduras|HU Hungary|IS Iceland|IN India|ID Indonesia|IR Iran|IQ Iraq|IE Ireland|IL Israel|IT Italy|JM Jamaica|JP Japan|JO Jordan|KZ Kazakhstan|KE Kenya|KI Kiribati|KP North Korea|KR South Korea|KW Kuwait|KG Kyrgyzstan|LA Laos|LV Latvia|LB Lebanon|LS Lesotho|LR Liberia|LY Libya|LI Liechtenstein|LT Lithuania|LU Luxembourg|MG Madagascar|MW Malawi|MY Malaysia|MV Maldives|ML Mali|MT Malta|MH Marshall Islands|MR Mauritania|MU Mauritius|MX Mexico|FM Micronesia|MD Moldova|MC Monaco|MN Mongolia|ME Montenegro|MA Morocco|MZ Mozambique|MM Myanmar|NA Namibia|NR Nauru|NP Nepal|NL Netherlands|NZ New Zealand|NI Nicaragua|NE Niger|NG Nigeria|MK North Macedonia|NO Norway|OM Oman|PK Pakistan|PW Palau|PA Panama|PG Papua New Guinea|PY Paraguay|PE Peru|PH Philippines|PL Poland|PT Portugal|QA Qatar|RO Romania|RU Russia|RW Rwanda|KN Saint Kitts and Nevis|LC Saint Lucia|VC Saint Vincent and the Grenadines|WS Samoa|SM San Marino|ST São Tomé and Príncipe|SA Saudi Arabia|SN Senegal|RS Serbia|SC Seychelles|SL Sierra Leone|SG Singapore|SK Slovakia|SI Slovenia|SB Solomon Islands|SO Somalia|ZA South Africa|SS South Sudan|ES Spain|LK Sri Lanka|SD Sudan|SR Suriname|SE Sweden|CH Switzerland|SY Syria|TJ Tajikistan|TZ Tanzania|TH Thailand|TL Timor-Leste|TG Togo|TO Tonga|TT Trinidad and Tobago|TN Tunisia|TR Turkey|TM Turkmenistan|TV Tuvalu|UG Uganda|UA Ukraine|AE United Arab Emirates|GB United Kingdom|US United States|UY Uruguay|UZ Uzbekistan|VU Vanuatu|VE Venezuela|VN Vietnam|YE Yemen|ZM Zambia|ZW Zimbabwe|VA Vatican City|PS Palestine
    """.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|").map { entry in
      let parts = entry.split(separator: " ", maxSplits: 1)
      return PsyCountry(code: String(parts[0]), name: String(parts[1]))
    }

  public static let celestial: [CelestialBody] = real + trek

  static let real: [CelestialBody] = [
    .init("Mercury", .planet, trek: false, article: "Mercury (planet)"),
    .init("Venus", .planet, trek: false), .init("Earth", .planet, trek: false),
    .init("Mars", .planet, trek: false), .init("Jupiter", .planet, trek: false),
    .init("Saturn", .planet, trek: false), .init("Uranus", .planet, trek: false),
    .init("Neptune", .planet, trek: false),
    .init("Pluto", .dwarfPlanet, trek: false), .init("Ceres", .dwarfPlanet, trek: false, article: "Ceres (dwarf planet)"),
    .init("Eris", .dwarfPlanet, trek: false, article: "Eris (dwarf planet)"),
    .init("Haumea", .dwarfPlanet, trek: false), .init("Makemake", .dwarfPlanet, trek: false),
    .init("The Moon", .moon, trek: false, article: "Moon"),
    .init("Phobos", .moon, trek: false, article: "Phobos (moon)"),
    .init("Deimos", .moon, trek: false, article: "Deimos (moon)"),
    .init("Io", .moon, trek: false, article: "Io (moon)"),
    .init("Europa", .moon, trek: false, article: "Europa (moon)"),
    .init("Ganymede", .moon, trek: false, article: "Ganymede (moon)"),
    .init("Callisto", .moon, trek: false, article: "Callisto (moon)"),
    .init("Titan", .moon, trek: false, article: "Titan (moon)"),
    .init("Enceladus", .moon, trek: false), .init("Mimas", .moon, trek: false, article: "Mimas (moon)"),
    .init("Iapetus", .moon, trek: false, article: "Iapetus (moon)"),
    .init("Rhea", .moon, trek: false, article: "Rhea (moon)"),
    .init("Miranda", .moon, trek: false, article: "Miranda (moon)"),
    .init("Titania", .moon, trek: false, article: "Titania (moon)"),
    .init("Oberon", .moon, trek: false, article: "Oberon (moon)"),
    .init("Triton", .moon, trek: false, article: "Triton (moon)"),
    .init("Charon", .moon, trek: false, article: "Charon (moon)"),
    .init("Proxima Centauri b", .planet, trek: false),
    .init("TRAPPIST-1e", .planet, trek: false),
    .init("Kepler-452b", .planet, trek: false),
    .init("51 Pegasi b", .planet, trek: false),
    .init("International Space Station", .station, trek: false),
    .init("Tiangong", .station, trek: false, article: "Tiangong space station"),
    .init("Mir", .station, trek: false),
  ]
  static let trek: [CelestialBody] = [
    .init("Vulcan", .planet, trek: true), .init("Qo'noS", .planet, trek: true),
    .init("Romulus", .planet, trek: true), .init("Remus", .planet, trek: true),
    .init("Bajor", .planet, trek: true), .init("Cardassia Prime", .planet, trek: true),
    .init("Ferenginar", .planet, trek: true), .init("Andoria", .moon, trek: true),
    .init("Tellar Prime", .planet, trek: true), .init("Betazed", .planet, trek: true),
    .init("Risa", .planet, trek: true), .init("Trill", .planet, trek: true),
    .init("Denobula", .planet, trek: true), .init("Bolarus IX", .planet, trek: true),
    .init("Talos IV", .planet, trek: true), .init("Ceti Alpha V", .planet, trek: true),
    .init("Genesis Planet", .planet, trek: true), .init("Nimbus III", .planet, trek: true),
    .init("Rura Penthe", .planet, trek: true), .init("Wolf 359", .planet, trek: true),
    .init("Kaelon II", .planet, trek: true), .init("Kataan", .planet, trek: true),
    .init("Turkana IV", .planet, trek: true), .init("Bringloid V", .planet, trek: true),
    .init("Exo III", .planet, trek: true), .init("Janus VI", .planet, trek: true),
    .init("Rigel VII", .planet, trek: true), .init("Ocampa", .planet, trek: true),
    .init("Talax", .planet, trek: true), .init("Kazon homeworld", .planet, trek: true, article: "Kazon"),
    .init("Gideon", .planet, trek: true), .init("Elas", .planet, trek: true),
    .init("Excalbia", .planet, trek: true), .init("Eminiar VII", .planet, trek: true),
    .init("Coridan", .planet, trek: true), .init("Daled IV", .planet, trek: true),
    .init("Praxis", .moon, trek: true), .init("Luna", .moon, trek: true),
    .init("Titan", .moon, trek: true, article: "Titan"), .init("Rakhar", .planet, trek: true),
    .init("Deep Space 9", .station, trek: true), .init("Terok Nor", .station, trek: true),
    .init("Starbase 1", .starbase, trek: true), .init("Starbase 11", .starbase, trek: true),
    .init("Starbase 74", .starbase, trek: true), .init("Starbase 133", .starbase, trek: true),
    .init("Starbase 375", .starbase, trek: true), .init("Starbase 515", .starbase, trek: true),
    .init("Starbase Yorktown", .starbase, trek: true),
    .init("Earth Spacedock", .starbase, trek: true), .init("Regula I", .station, trek: true),
    .init("Deep Space Station K-7", .station, trek: true),
    .init("Jupiter Station", .station, trek: true),
    .init("Utopia Planitia Fleet Yards", .station, trek: true),
    .init("Empok Nor", .station, trek: true), .init("Deep Space 4", .station, trek: true),
    .init("Memory Alpha", .planet, trek: true, article: "Memory Alpha (planetoid)"),
    .init("Starbase 39-Sierra", .starbase, trek: true),
  ]

  /// Five distinct countries and five distinct celestial destinations.
  public static func draw<G: RandomNumberGenerator>(using generator: inout G)
    -> (countries: [PsyCountry], places: [CelestialBody])
  {
    (
      Array(countries.shuffled(using: &generator).prefix(5)),
      Array(celestial.shuffled(using: &generator).prefix(5))
    )
  }
  public static func draw() -> (countries: [PsyCountry], places: [CelestialBody]) {
    var generator = SystemRandomNumberGenerator()
    return draw(using: &generator)
  }
}

extension PsyartCatalog {
  /// Keeps the model's preferred order but limits each owner (artist) to `perOwner` picks,
  /// filling any gap round-robin from owners not yet represented.
  public static func balance(
    _ preferred: [Int], owners: [Int], count: Int, perOwner: Int
  ) -> [Int] {
    var chosen: [Int] = []
    var perCount: [Int: Int] = [:]
    func take(_ index: Int) {
      guard owners.indices.contains(index), !chosen.contains(index), chosen.count < count,
        perCount[owners[index], default: 0] < perOwner
      else { return }
      chosen.append(index)
      perCount[owners[index], default: 0] += 1
    }
    preferred.forEach(take)
    // Round-robin over owners, least represented first.
    var remaining = owners.indices.filter { !chosen.contains($0) }
    while chosen.count < count, !remaining.isEmpty {
      let before = chosen.count
      for owner in Set(owners).sorted(by: { perCount[$0, default: 0] < perCount[$1, default: 0] }) {
        if let index = remaining.first(where: { owners[$0] == owner }) {
          take(index)
          remaining.removeAll { $0 == index }
        }
      }
      if chosen.count == before { break }
    }
    return chosen
  }
}
