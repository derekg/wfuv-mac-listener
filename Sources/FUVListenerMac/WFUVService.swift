import Foundation

enum WFUVService {
    static let highQualityStreamURL = URL(string: "https://onair.wfuv.org/onair-hi")!
    static let dataSaverStreamURL = URL(string: "https://onair.wfuv.org/onair-aacplus")!
    static let playlistURL = URL(string: "https://wfuv.org/playlist/feed")!
    static let nowPlayingURL = URL(string: "https://wfuv.org/sites/default/files/player/playlist/now_playing.json")!

    static func fetchSongs() async throws -> [Song] {
        var components = URLComponents(url: playlistURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "refresh", value: String(Int(Date().timeIntervalSince1970)))]
        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try PlaylistParser.parse(data)
    }

    static func fetchNowPlaying() async throws -> LiveTrack? {
        var components = URLComponents(url: nowPlayingURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "refresh", value: String(Int(Date().timeIntervalSince1970)))]
        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(NowPlayingResponse.self, from: data).live
    }
}

struct Song: Codable, Identifiable, Hashable {
    let title: String
    let artist: String
    let playedAt: Date

    // RSS guid contains only a title and repeats, so use the broadcast timestamp.
    var id: String { "\(playedAt.timeIntervalSince1970)|\(title)|\(artist)" }

    // A heart marks the recording, not one particular broadcast of it.
    var favoriteID: String { Self.favoriteID(title: title, artist: artist) }

    static func favoriteID(title: String, artist: String) -> String {
        func normalized(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .lowercased()
        }
        return "\(normalized(title))|\(normalized(artist))"
    }

    var spotifySearchURL: URL {
        var components = URLComponents(string: "https://open.spotify.com/search")!
        components.path = "/search/\(artist) \(title)"
        return components.url!
    }
}

struct LiveTrack: Decodable {
    let title: String
    let artist: String
    let album: String?
    let timestamp: String?
    let eventType: String?
    let art: Artwork?

    enum CodingKeys: String, CodingKey {
        case title, artist, album, timestamp, art
        case eventType = "event_type"
    }

    var artworkURL: URL? {
        guard let path = art?.large, !path.contains("history-item-image") else { return nil }
        return URL(string: path, relativeTo: URL(string: "https://wfuv.org"))?.absoluteURL
    }

    var isMusic: Bool { eventType == "MUSIC" && !title.isEmpty }

    var playedAt: Date? {
        guard let timestamp else { return nil }
        return Self.timestampFormatter.date(from: timestamp)
    }

    static func fromPlaylist(_ song: Song) -> LiveTrack {
        LiveTrack(title: song.title, artist: song.artist, album: nil,
                  timestamp: nil, eventType: "MUSIC", art: nil)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "MMddyyyy-HHmmss"
        return formatter
    }()
}

struct Artwork: Decodable { let large: String? }
struct NowPlayingResponse: Decodable { let live: LiveTrack? }

enum TrackSelection {
    static func resolve(station: LiveTrack?, latest: Song?, now: Date) -> (LiveTrack?, Bool) {
        if let latest {
            let age = now.timeIntervalSince(latest.playedAt)
            if (-60...720).contains(age),
               latest.playedAt > (station?.playedAt ?? .distantPast).addingTimeInterval(30) {
                return (LiveTrack.fromPlaylist(latest), false)
            }
        }
        if let station, let playedAt = station.playedAt,
           now.timeIntervalSince(playedAt) > 1_800 { return (nil, false) }
        return (station, station != nil)
    }
}

enum TimelineSelection {
    static func liveOnlySong(track: LiveTrack?, isConfirmedLive: Bool, songs: [Song]) -> Song? {
        guard isConfirmedLive, let track, track.isMusic, let playedAt = track.playedAt else { return nil }
        let current = Song(title: track.title, artist: track.artist, playedAt: playedAt)
        if let latest = songs.first {
            if latest.favoriteID == current.favoriteID { return nil }
            // Only add a live row ahead of the playlist when its timestamp is newer.
            if playedAt < latest.playedAt.addingTimeInterval(-30) { return nil }
        }
        return current
    }
}

private final class PlaylistParser: NSObject, XMLParserDelegate {
    private var songs: [Song] = []
    private var currentElement = ""
    private var title = ""
    private var artist = ""
    private var date = ""
    private var inItem = false

    static func parse(_ data: Data) throws -> [Song] {
        let delegate = PlaylistParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), !delegate.songs.isEmpty else { throw URLError(.cannotParseResponse) }
        return delegate.songs
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "item" {
            inItem = true
            title = ""
            artist = ""
            date = ""
        }
        currentElement = elementName
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch currentElement {
        case "title": title += string
        case "dc:creator": artist += string
        case "pubDate": date += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanTitle.isEmpty, !cleanArtist.isEmpty,
               let playedAt = Self.dateFormatter.date(from: date.trimmingCharacters(in: .whitespacesAndNewlines)) {
                songs.append(Song(title: cleanTitle, artist: cleanArtist, playedAt: playedAt))
            }
            inItem = false
        }
        currentElement = ""
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()
}
