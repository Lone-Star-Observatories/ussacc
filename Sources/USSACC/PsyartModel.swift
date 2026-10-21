import ACCCore
import AVFoundation
import Foundation

#if canImport(FoundationModels)
  import FoundationModels

  @available(macOS 26.0, *)
  @Generable struct GeneratedMix {
    @Guide(description: "Evocative title for this cultural fusion, 2 to 5 words") var title: String
    @Guide(description: "One-sentence tagline") var tagline: String
    @Guide(description: "Three or four sentences reading the shared cultural psyche of the coordinates")
    var reading: String
    @Guide(
      description:
        "Eight real recording artists, best first. At least four must be from the listed countries.",
      .count(8))
    var artists: [String]
  }
  @available(macOS 26.0, *)
  @Generable struct GeneratedPicks {
    @Guide(description: "Numbers of the five songs that best express the reading", .count(5))
    var songs: [Int]
    @Guide(description: "Numbers of the two albums that best express the reading", .count(2))
    var albums: [Int]
  }
#endif

struct PlaceInfo: Codable, Equatable {
  var summary: String
  var image: URL?
  var link: URL?
}
struct MediaItem: Codable, Equatable, Identifiable {
  var title: String
  var artist: String
  var artwork: URL?
  var preview: URL?
  var link: URL?
  /// Found in a real catalog; unverified items may be model inventions.
  var verified: Bool
  var id: String { title + "|" + artist }
}
struct VideoItem: Codable, Equatable, Identifiable {
  var title: String
  var query: String
  var videoTitle: String?
  var channel: String?
  var thumbnail: URL?
  var link: URL
  var id: String { query }
}
struct PsyartPage: Codable, Equatable {
  var countries: [PsyCountry]
  var places: [CelestialBody]
  var title: String
  var tagline: String
  var reading: String
  var artists: [MediaItem]
  var songs: [MediaItem]
  var albums: [MediaItem]
  var videos: [VideoItem]
  var info: [String: PlaceInfo]
  var created: Date
}

@MainActor final class PsyartModel: ObservableObject {
  @Published var page: PsyartPage?
  @Published var phase = ""
  @Published var busy = false
  @Published var error = ""
  @Published var playing: URL?
  @Published var youtubeKeySaved = MailKeychain.password(for: PsyartModel.youtubeAccount) != nil
  static let youtubeAccount = "youtube-api-key"
  private var player: AVPlayer?
  private let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("USSACC/psyart.json")

  /// Artists used by recent transmissions; excluded so each one brings new music.
  private var recentArtists: [String] {
    get { UserDefaults.standard.stringArray(forKey: "psyart.recentArtists") ?? [] }
    set { UserDefaults.standard.set(Array(newValue.suffix(60)), forKey: "psyart.recentArtists") }
  }
  init() { page = try? LocalPersistence.load(PsyartPage.self, from: file) }

  func generate() async {
    guard !busy else { return }
    busy = true
    error = ""
    defer {
      busy = false
      phase = ""
    }
    let draw = PsyartCatalog.draw()
    phase = "Coordinates locked · consulting Apple Intelligence"
    do {
      let used = Set((recentArtists + (page?.artists.map(\.title) ?? [])).map(ITunes.normalized))
      let mix = try await Self.compose(
        countries: draw.countries, places: draw.places, avoid: Array(used).shuffled().prefix(40).map { $0 })
      phase = "Matching artists in Apple Music"
      async let info = Self.placeInfo(countries: draw.countries, places: draw.places)
      // Keep the first three candidate artists that exist in the catalog.
      var artists: [(item: MediaItem, id: Int)] = []
      for name in mix.artists where artists.count < 3 && !used.contains(ITunes.normalized(name)) {
        if let found = await ITunes.artistRecord(name), !artists.contains(where: { $0.id == found.id }),
          !used.contains(ITunes.normalized(found.item.title))
        {
          artists.append(found)
        }
      }
      guard !artists.isEmpty else {
        throw IntegrationError.message("None of the suggested artists were found in Apple Music. Try again.")
      }
      phase = "Choosing tracks from the artists' catalogs"
      var songs: [MediaItem] = []
      var albums: [MediaItem] = []
      var songOwners: [Int] = []
      var albumOwners: [Int] = []
      for (owner, artist) in artists.enumerated() {
        // Sample beyond the most popular tracks so repeat artists still sound different.
        let artistSongs = (await ITunes.lookup(artist.id, entity: "song", limit: 40)).shuffled().prefix(12)
        let artistAlbums = (await ITunes.lookup(artist.id, entity: "album", limit: 20)).shuffled().prefix(6)
        songs += artistSongs
        albums += artistAlbums
        songOwners += Array(repeating: owner, count: artistSongs.count)
        albumOwners += Array(repeating: owner, count: artistAlbums.count)
      }
      let picks = try await Self.pick(reading: mix.reading, songs: songs, albums: albums)
      // At most two songs and one album per artist, so the manifest spans all three.
      let songIndices = PsyartCatalog.balance(picks.songs, owners: songOwners, count: 5, perOwner: 2)
      let albumIndices = PsyartCatalog.balance(picks.albums, owners: albumOwners, count: 2, perOwner: 1)
      let chosenSongs = songIndices.map { songs[$0] }
      let key = MailKeychain.password(for: Self.youtubeAccount)
      phase = "Locating video transmissions"
      let videos = await withTaskGroup(of: (Int, VideoItem).self) { group in
        for (n, song) in chosenSongs.enumerated() {
          group.addTask {
            (n, await YouTube.resolve(title: "\(song.artist) – \(song.title)", query: "\(song.artist) \(song.title)", key: key))
          }
        }
        var out: [(Int, VideoItem)] = []
        for await item in group { out.append(item) }
        return out.sorted { $0.0 < $1.0 }.map(\.1)
      }
      let result = PsyartPage(
        countries: draw.countries, places: draw.places, title: mix.title, tagline: mix.tagline,
        reading: mix.reading, artists: artists.map(\.item), songs: chosenSongs,
        albums: albumIndices.map { albums[$0] }, videos: videos, info: await info, created: .now)
      page = result
      recentArtists += result.artists.map(\.title)
      try? LocalPersistence.save(result, to: file)
    } catch {
      self.error = error.localizedDescription
    }
  }
  func togglePreview(_ url: URL?) {
    guard let url else { return }
    if playing == url {
      player?.pause()
      playing = nil
    } else {
      player = AVPlayer(url: url)
      player?.play()
      playing = url
    }
  }
  func saveYouTubeKey(_ key: String) {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      MailKeychain.delete(for: Self.youtubeAccount)
    } else {
      try? MailKeychain.save(trimmed, for: Self.youtubeAccount)
    }
    youtubeKeySaved = !trimmed.isEmpty
  }

  struct Mix {
    var title, tagline, reading: String
    var artists: [String]
  }
  static func compose(countries: [PsyCountry], places: [CelestialBody], avoid: [String] = [])
    async throws -> Mix
  {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable {
        let session = LanguageModelSession(
          instructions: """
            You are the cultural curator for an LCARS-style starship arts console.
            Given five Earth countries and five celestial destinations (real astronomy or Star Trek canon),
            imagine the shared cultural psyche of that combination.
            Suggest only REAL, well-known recording artists available on Apple Music. At least three must be
            from, or deeply rooted in, the listed countries; the rest may echo the cosmic or science-fiction mood.
            """)
        let prompt =
          "Countries: \(countries.map(\.name).joined(separator: ", ")).\n"
          + "Destinations: "
          + places.map { "\($0.name) (\($0.kind.label.lowercased()), \($0.trek ? "Star Trek" : "real"))" }
          .joined(separator: ", ") + "."
        let avoidance = avoid.isEmpty ? "" : "\nDo not suggest any of these recently used artists: \(avoid.joined(separator: ", "))."
        // Higher-temperature sampling keeps successive transmissions from converging on the same names.
        let mix = try await session.respond(
          to: prompt + avoidance, generating: GeneratedMix.self,
          options: GenerationOptions(sampling: .random(top: 50), temperature: 1.2)
        ).content
        return Mix(title: mix.title, tagline: mix.tagline, reading: mix.reading, artists: mix.artists)
      }
    #endif
    throw IntegrationError.message(
      "Apple Intelligence is unavailable (\(Intelligence.availability)). PSYART needs it to compose the mix.")
  }
  /// Second pass: the model chooses only from real catalog entries, by number.
  static func pick(reading: String, songs: [MediaItem], albums: [MediaItem]) async throws
    -> (songs: [Int], albums: [Int])
  {
    func fallback(_ count: Int, from total: Int) -> [Int] { Array((0..<total).shuffled().prefix(count)) }
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable, !songs.isEmpty {
        let session = LanguageModelSession(
          instructions: "Choose recordings by their numbers. Only use numbers from the lists. Prefer variety across artists.")
        let prompt =
          "Reading: \(reading)\n\nSongs:\n"
          + songs.enumerated().map { "\($0.offset). \($0.element.title) — \($0.element.artist)" }.joined(separator: "\n")
          + "\n\nAlbums:\n"
          + albums.enumerated().map { "\($0.offset). \($0.element.title) — \($0.element.artist)" }.joined(separator: "\n")
        if let picks = try? await session.respond(to: prompt, generating: GeneratedPicks.self).content {
          var songPicks = picks.songs.filter { songs.indices.contains($0) }
          var albumPicks = picks.albums.filter { albums.indices.contains($0) }
          songPicks = Array(NSOrderedSet(array: songPicks).array as! [Int])
          albumPicks = Array(NSOrderedSet(array: albumPicks).array as! [Int])
          for index in fallback(songs.count, from: songs.count) where songPicks.count < min(5, songs.count) && !songPicks.contains(index) {
            songPicks.append(index)
          }
          for index in fallback(albums.count, from: albums.count) where albumPicks.count < min(2, albums.count) && !albumPicks.contains(index) {
            albumPicks.append(index)
          }
          return (Array(songPicks.prefix(5)), Array(albumPicks.prefix(2)))
        }
      }
    #endif
    return (fallback(min(5, songs.count), from: songs.count), fallback(min(2, albums.count), from: albums.count))
  }

  static func placeInfo(countries: [PsyCountry], places: [CelestialBody]) async -> [String: PlaceInfo] {
    await withTaskGroup(of: (String, PlaceInfo?).self) { group in
      for country in countries {
        group.addTask { (country.id, await Wiki.wikipedia(country.wikipediaTitle)) }
      }
      for place in places {
        group.addTask {
          (place.id, place.trek ? await Wiki.memoryAlpha(place.article) : await Wiki.wikipedia(place.article))
        }
      }
      var result: [String: PlaceInfo] = [:]
      for await (id, info) in group { if let info { result[id] = info } }
      return result
    }
  }
}

enum HTTP {
  static func json(_ url: URL) async -> Any? {
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.setValue("USSACC/0.1 (macOS; personal use)", forHTTPHeaderField: "User-Agent")
    guard let (data, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200
    else { return nil }
    return try? JSONSerialization.jsonObject(with: data)
  }
  static func url(_ base: String, _ query: [String: String]) -> URL {
    var components = URLComponents(string: base)!
    components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    return components.url!
  }
}

enum ITunes {
  static func search(_ term: String, entity: String, limit: Int = 8, attribute: String? = nil) async
    -> [[String: Any]]
  {
    var query = ["term": term, "entity": entity, "limit": String(limit), "media": "music"]
    if let attribute { query["attribute"] = attribute }
    let json = await HTTP.json(HTTP.url("https://itunes.apple.com/search", query)) as? [String: Any]
    return json?["results"] as? [[String: Any]] ?? []
  }
  static func normalized(_ s: String) -> String {
    s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
      .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
      .joined(separator: " ")
  }
  static func matches(_ a: String, _ b: String) -> Bool {
    let x = normalized(a)
    let y = normalized(b)
    return !x.isEmpty && !y.isEmpty && (x.contains(y) || y.contains(x))
  }
  static func artwork(_ result: [String: Any]) -> URL? {
    (result["artworkUrl100"] as? String).flatMap {
      URL(string: $0.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
    }
  }
  static func song(_ title: String, by artist: String) async -> MediaItem {
    let results = await search("\(artist) \(title)", entity: "song")
    if let hit = results.first(where: {
      matches($0["trackName"] as? String ?? "", title) && matches($0["artistName"] as? String ?? "", artist)
    }) {
      return MediaItem(
        title: hit["trackName"] as? String ?? title, artist: hit["artistName"] as? String ?? artist,
        artwork: artwork(hit), preview: (hit["previewUrl"] as? String).flatMap(URL.init),
        link: (hit["trackViewUrl"] as? String).flatMap(URL.init), verified: true)
    }
    return MediaItem(title: title, artist: artist, verified: false)
  }
  static func album(_ title: String, by artist: String) async -> MediaItem {
    let results = await search("\(artist) \(title)", entity: "album")
    if let hit = results.first(where: {
      matches($0["collectionName"] as? String ?? "", title)
        && matches($0["artistName"] as? String ?? "", artist)
    }) {
      return MediaItem(
        title: hit["collectionName"] as? String ?? title,
        artist: hit["artistName"] as? String ?? artist, artwork: artwork(hit),
        link: (hit["collectionViewUrl"] as? String).flatMap(URL.init), verified: true)
    }
    return MediaItem(title: title, artist: artist, verified: false)
  }
  /// Exact-ish artist match with id, genre and artwork from their catalog.
  static func artistRecord(_ name: String) async -> (item: MediaItem, id: Int)? {
    let results = await search(name, entity: "musicArtist", limit: 5)
    guard let hit = results.first(where: { matches($0["artistName"] as? String ?? "", name) }),
      let id = hit["artistId"] as? Int
    else { return nil }
    let albums = await lookup(id, entity: "album", limit: 1)
    return (
      MediaItem(
        title: hit["artistName"] as? String ?? name, artist: hit["primaryGenreName"] as? String ?? "",
        artwork: albums.first?.artwork, link: (hit["artistLinkUrl"] as? String).flatMap(URL.init),
        verified: true),
      id
    )
  }
  /// An artist's catalog entries (songs or albums), all verified.
  static func lookup(_ artistID: Int, entity: String, limit: Int) async -> [MediaItem] {
    let url = HTTP.url(
      "https://itunes.apple.com/lookup", ["id": String(artistID), "entity": entity, "limit": String(limit)])
    let results = ((await HTTP.json(url) as? [String: Any])?["results"] as? [[String: Any]] ?? [])
      .filter { ($0["wrapperType"] as? String) == (entity == "song" ? "track" : "collection") }
    var seen: Set<String> = []
    return results.compactMap { hit in
      let title = (entity == "song" ? hit["trackName"] : hit["collectionName"]) as? String ?? ""
      guard !title.isEmpty, seen.insert(ITunes.normalized(title)).inserted else { return nil }
      return MediaItem(
        title: title, artist: hit["artistName"] as? String ?? "", artwork: artwork(hit),
        preview: (hit["previewUrl"] as? String).flatMap(URL.init),
        link: ((entity == "song" ? hit["trackViewUrl"] : hit["collectionViewUrl"]) as? String).flatMap(URL.init),
        verified: true)
    }
  }
  static func artist(_ name: String) async -> MediaItem {
    let results = await search(name, entity: "album", limit: 5, attribute: "artistTerm")
    if let hit = results.first(where: { matches($0["artistName"] as? String ?? "", name) }) {
      return MediaItem(
        title: hit["artistName"] as? String ?? name, artist: hit["primaryGenreName"] as? String ?? "",
        artwork: artwork(hit), link: (hit["artistViewUrl"] as? String).flatMap(URL.init),
        verified: true)
    }
    return MediaItem(title: name, artist: "", verified: false)
  }
}

enum Wiki {
  static func wikipedia(_ title: String) async -> PlaceInfo? {
    let path = title.replacingOccurrences(of: " ", with: "_")
      .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
    guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(path)"),
      let json = await HTTP.json(url) as? [String: Any], let extract = json["extract"] as? String
    else { return nil }
    let image = ((json["thumbnail"] as? [String: Any])?["source"] as? String).flatMap(URL.init)
    let link = (((json["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"] as? String)
      .flatMap(URL.init)
    return PlaceInfo(summary: extract, image: image, link: link)
  }
  static func memoryAlpha(_ title: String) async -> PlaceInfo? {
    let url = HTTP.url(
      "https://memory-alpha.fandom.com/api.php",
      ["action": "parse", "page": title, "prop": "text", "section": "0", "format": "json", "redirects": "1"])
    guard let json = await HTTP.json(url) as? [String: Any],
      let html = ((json["parse"] as? [String: Any])?["text"] as? [String: Any])?["*"] as? String
    else { return nil }
    let paragraphs = matches(#"<p>(.*?)</p>"#, in: html).map(stripHTML).filter { $0.count > 60 }
    // The page-image API returns the article's lead image; inline <img> tags are often icons.
    let imageQuery = HTTP.url(
      "https://memory-alpha.fandom.com/api.php",
      ["action": "query", "prop": "pageimages", "piprop": "original", "titles": title, "format": "json",
       "redirects": "1"])
    let pages = ((await HTTP.json(imageQuery) as? [String: Any])?["query"] as? [String: Any])?["pages"]
      as? [String: Any]
    let image = pages?.values.compactMap {
      (($0 as? [String: Any])?["original"] as? [String: Any])?["source"] as? String
    }.first.flatMap(URL.init)
    let page = title.replacingOccurrences(of: " ", with: "_")
      .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
    return PlaceInfo(
      summary: paragraphs.first ?? "Memory Alpha record.", image: image,
      link: URL(string: "https://memory-alpha.fandom.com/wiki/\(page)"))
  }
  static func matches(_ pattern: String, in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    else { return [] }
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
      Range($0.range(at: 1), in: text).map { String(text[$0]) }
    }
  }
  static func stripHTML(_ html: String) -> String {
    var text = html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    text = text.replacingOccurrences(of: #"\[\d+\]"#, with: "", options: .regularExpression)
    for (entity, value) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&nbsp;": " ", "&lt;": "<", "&gt;": ">"] {
      text = text.replacingOccurrences(of: entity, with: value)
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

enum YouTube {
  /// With an API key, resolves the top video; otherwise links to a YouTube search.
  static func resolve(title: String, query: String, key: String?) async -> VideoItem {
    let search = HTTP.url("https://www.youtube.com/results", ["search_query": query])
    guard let key else { return VideoItem(title: title, query: query, link: search) }
    let url = HTTP.url(
      "https://www.googleapis.com/youtube/v3/search",
      ["part": "snippet", "type": "video", "maxResults": "1", "q": query, "key": key])
    guard let json = await HTTP.json(url) as? [String: Any],
      let item = (json["items"] as? [[String: Any]])?.first,
      let id = (item["id"] as? [String: Any])?["videoId"] as? String,
      let snippet = item["snippet"] as? [String: Any]
    else { return VideoItem(title: title, query: query, link: search) }
    let thumbnails = snippet["thumbnails"] as? [String: Any]
    let thumb = ((thumbnails?["high"] ?? thumbnails?["medium"]) as? [String: Any])?["url"] as? String
    return VideoItem(
      title: title, query: query, videoTitle: snippet["title"] as? String,
      channel: snippet["channelTitle"] as? String, thumbnail: thumb.flatMap(URL.init),
      link: URL(string: "https://www.youtube.com/watch?v=\(id)")!)
  }
}
