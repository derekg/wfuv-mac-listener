import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Looks up cover art only when the recording and artist match the broadcast metadata.
actor ArtworkService {
    static let shared = ArtworkService()

    private struct SearchResponse: Decodable { let recordings: [Recording] }
    private struct Recording: Decodable {
        let title: String
        let releases: [Release]?
        let artistCredit: [Credit]?

        enum CodingKeys: String, CodingKey {
            case title, releases
            case artistCredit = "artist-credit"
        }
    }
    private struct Credit: Decodable {
        let name: String
        init(from decoder: Decoder) throws {
            if let string = try? decoder.singleValueContainer().decode(String.self) {
                name = string
            } else {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decode(String.self, forKey: .name)
            }
        }
        private enum CodingKeys: String, CodingKey { case name }
    }
    private struct Release: Decodable {
        let id: String?
        let status: String?
        let date: String?
        let releaseGroup: ReleaseGroup?
        enum CodingKeys: String, CodingKey { case id, status, date; case releaseGroup = "release-group" }
    }
    private struct ReleaseCandidate {
        let id: String
        let date: String
    }
    private struct ReleaseGroup: Decodable {
        let id: String
        let title: String?
        let primaryType: String?
        let secondaryTypes: [String]?
        let firstReleaseDate: String?
        var observedReleaseDate: String? = nil
        var releaseCandidates: [ReleaseCandidate] = []

        enum CodingKeys: String, CodingKey {
            case id, title
            case primaryType = "primary-type"
            case secondaryTypes = "secondary-types"
            case firstReleaseDate = "first-release-date"
        }

        var preference: Int {
            let tags = Set((secondaryTypes ?? []).map { $0.lowercased() })
            let base: Int
            switch primaryType?.lowercased() {
            case "album": base = 0
            case "ep": base = 1
            case "single": base = 2
            default: base = 4
            }
            let title = (title ?? "").lowercased()
            let isBroadcast = primaryType?.lowercased() == "broadcast" || title.contains("broadcast")
            let isLive = tags.contains("live") || title.contains("live at ") || title.contains("live from ")
            let isCompilation = tags.contains("compilation") || tags.contains("soundtrack")
            return base + (isBroadcast ? 30 : 0) + (isLive ? 20 : 0) + (isCompilation ? 10 : 0)
        }

        var earliestDate: String {
            [firstReleaseDate, observedReleaseDate]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .min() ?? "9999"
        }
    }

    private struct CacheRecord: Codable {
        let source: String
        let album: String?
        let releaseGroupID: String?
        let checkedAt: Date
        let retryAfter: Date?
    }

    private let images: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 40
        cache.totalCostLimit = 20_000_000
        return cache
    }()
    private var retryAfter: [String: Date] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private var serviceRetryAfter = Date.distantPast
    private var nextSearch = Date.distantPast
    private var records: [String: CacheRecord] = [:]
    private var recordsLoaded = false
    private var pinnedDigests = Set<String>()
    private let cacheDirectory: URL

    init(cacheDirectory: URL? = nil) {
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            for oldName in ["AlbumArtwork", "AlbumArtworkV2", "AlbumArtworkV3"] {
                try? FileManager.default.removeItem(at: support.appendingPathComponent(oldName, isDirectory: true))
            }
            self.cacheDirectory = support.appendingPathComponent("AlbumArtworkV4", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    func imageData(title: String, artist: String, preferredURL: URL? = nil,
                   preferredAlbum: String? = nil) async -> Data? {
        let key = "\(title.lowercased())|\(artist.lowercased())"
        let cached = cachedImageData(title: title, artist: artist)
        let record = records[digest(for: key)]
        if cached != nil, record?.source == "station" || record?.source == "archive" { return cached }
        if let retryDate = record?.retryAfter, retryDate > .now, preferredURL == nil { return cached }
        if let inFlight = inFlight[key] { return await inFlight.value ?? cached }
        let task = Task {
            await fetchImageData(key: key, title: title, artist: artist,
                                 preferredURL: preferredURL, preferredAlbum: preferredAlbum)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result ?? cached
    }

    func cachedImageData(title: String, artist: String) -> Data? {
        let key = "\(title.lowercased())|\(artist.lowercased())"
        loadRecordsIfNeeded()
        if let cached = images.object(forKey: key as NSString) { return cached as Data }
        let file = cacheFile(for: key)
        if let cached = try? Data(contentsOf: file) {
            let hash = digest(for: key)
            if records[hash] == nil {
                let normalized = Self.normalizedImageData(cached)
                let stored = normalized.flatMap { $0.count < cached.count ? $0 : nil } ?? cached
                if stored.count < cached.count {
                    try? stored.write(to: file, options: .atomic)
                }
                records[hash] = CacheRecord(source: "legacy", album: nil, releaseGroupID: nil,
                                            checkedAt: .now, retryAfter: nil)
                saveRecords()
                remember(stored, for: key)
                return stored
            }
            remember(cached, for: key)
            return cached
        }
        return nil
    }

    func setPinnedSongs(_ songs: [Song]) {
        pinnedDigests = Set(songs.map { digest(for: "\($0.title.lowercased())|\($0.artist.lowercased())") })
        pruneCache()
    }

    private func fetchImageData(key: String, title: String, artist: String,
                                preferredURL: URL?, preferredAlbum: String?) async -> Data? {
        if let preferredURL {
            var preferredRequest = URLRequest(url: preferredURL)
            preferredRequest.timeoutInterval = 12
            if let (data, response) = try? await URLSession.shared.data(for: preferredRequest),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let compact = Self.normalizedImageData(data) {
                save(compact, for: key, source: "station", album: preferredAlbum, releaseGroupID: nil)
                return compact
            }
        }
        if let retryDate = retryAfter[key], retryDate > .now { return nil }
        if serviceRetryAfter > .now { return nil }

        let delay = nextSearch.timeIntervalSinceNow
        nextSearch = Date().addingTimeInterval(max(0, delay) + 1.1)
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        guard !Task.isCancelled else { return nil }
        if serviceRetryAfter > .now { return nil }

        guard var url = URLComponents(string: "https://musicbrainz.org/ws/2/recording/") else { return nil }
        url.queryItems = [
            URLQueryItem(name: "query", value: "recording:\"\(Self.searchPhrase(title))\" AND artist:\"\(Self.searchPhrase(artist))\""),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "100")
        ]
        guard let searchURL = url.url else { return nil }
        var request = URLRequest(url: searchURL)
        request.timeoutInterval = 7
        request.setValue("FUVListener/1.2 (https://github.com/derekg/wfuv-mac-listener)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                if let status = (response as? HTTPURLResponse)?.statusCode, status == 429 || status >= 500 {
                    serviceRetryAfter = Date().addingTimeInterval(300)
                }
                retryAfter[key] = Date().addingTimeInterval(300)
                return nil
            }
            let candidates = try JSONDecoder().decode(SearchResponse.self, from: data).recordings
            let exact = candidates.filter { recording in
                Self.normalized(recording.title) == Self.normalized(title)
                    && Self.normalized(recording.artistCredit?.map(\.name).joined() ?? "") == Self.normalized(artist)
            }
            var groupsByID: [String: ReleaseGroup] = [:]
            for recording in exact {
                for release in recording.releases ?? [] where release.status == "Official" {
                    guard var group = release.releaseGroup else { continue }
                    if let existing = groupsByID[group.id] { group = existing }
                    if let date = release.date, !date.isEmpty {
                        group.observedReleaseDate = min(group.observedReleaseDate ?? date, date)
                    }
                    if let id = release.id, !group.releaseCandidates.contains(where: { $0.id == id }) {
                        group.releaseCandidates.append(ReleaseCandidate(id: id, date: release.date ?? "9999"))
                    }
                    groupsByID[group.id] = group
                }
            }
            var groups = Array(groupsByID.values)
            let albumHint = preferredAlbum.map(Self.normalized)
            groups.sort {
                if let albumHint, !albumHint.isEmpty {
                    let lhsMatches = Self.normalized($0.title ?? "") == albumHint
                    let rhsMatches = Self.normalized($1.title ?? "") == albumHint
                    if lhsMatches != rhsMatches { return lhsMatches }
                }
                if $0.preference != $1.preference { return $0.preference < $1.preference }
                return $0.earliestDate < $1.earliestDate
            }
            guard !groups.isEmpty else {
                markMissing(key)
                return nil
            }
            var hadServerFailure = false
            let selectedGroups = Array(groups.prefix(15))
            for start in stride(from: 0, to: selectedGroups.count, by: 3) {
                let batch = Array(selectedGroups[start..<min(start + 3, selectedGroups.count)])
                let results = await withTaskGroup(of: (Int, Data?, Bool).self) { tasks in
                    for (index, group) in batch.enumerated() {
                        tasks.addTask {
                            let releaseIDs = group.releaseCandidates.sorted { $0.date < $1.date }.prefix(2).map(\.id)
                            let result = await Self.fetchCover(groupID: group.id, releaseIDs: releaseIDs)
                            return (index, result.0, result.1)
                        }
                    }
                    var completed: [(Int, Data?, Bool)] = []
                    for await result in tasks { completed.append(result) }
                    return completed.sorted { $0.0 < $1.0 }
                }
                hadServerFailure = hadServerFailure || results.contains { $0.2 }
                if let match = results.first(where: { $0.1 != nil }), let artData = match.1 {
                    let group = batch[match.0]
                    save(artData, for: key, source: "archive", album: group.title, releaseGroupID: group.id)
                    return artData
                }
            }
            if hadServerFailure { retryAfter[key] = Date().addingTimeInterval(300) }
            else { markMissing(key) }
            return nil
        } catch {
            serviceRetryAfter = Date().addingTimeInterval(120)
            retryAfter[key] = Date().addingTimeInterval(300)
            return nil
        }
    }

    private func digest(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func cacheFile(for key: String) -> URL {
        cacheDirectory.appendingPathComponent(digest(for: key)).appendingPathExtension("img")
    }

    private var recordsFile: URL { cacheDirectory.appendingPathComponent("artwork-index.json") }

    private func loadRecordsIfNeeded() {
        guard !recordsLoaded else { return }
        recordsLoaded = true
        if let data = try? Data(contentsOf: recordsFile),
           let decoded = try? JSONDecoder().decode([String: CacheRecord].self, from: data) {
            records = decoded
        }
    }

    private func saveRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: recordsFile, options: .atomic)
    }

    private func save(_ data: Data, for key: String, source: String,
                      album: String?, releaseGroupID: String?) {
        loadRecordsIfNeeded()
        remember(data, for: key)
        try? data.write(to: cacheFile(for: key), options: .atomic)
        records[digest(for: key)] = CacheRecord(source: source, album: album,
                                                releaseGroupID: releaseGroupID,
                                                checkedAt: .now, retryAfter: nil)
        saveRecords()
        pruneCache()
    }

    private func markMissing(_ key: String) {
        loadRecordsIfNeeded()
        records[digest(for: key)] = CacheRecord(source: "missing", album: nil,
                                                releaseGroupID: nil, checkedAt: .now,
                                                retryAfter: Date().addingTimeInterval(86_400))
        saveRecords()
    }

    private func remember(_ data: Data, for key: String) {
        images.setObject(data as NSData, forKey: key as NSString, cost: data.count)
    }

    private func pruneCache() {
        loadRecordsIfNeeded()
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: Array(keys)) else { return }
        let sorted = files.filter { $0.pathExtension == "img" }.compactMap { url -> (URL, Date, Int)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }.sorted {
            let lhsPinned = pinnedDigests.contains($0.0.deletingPathExtension().lastPathComponent)
            let rhsPinned = pinnedDigests.contains($1.0.deletingPathExtension().lastPathComponent)
            if lhsPinned != rhsPinned { return lhsPinned }
            return $0.1 > $1.1
        }
        var totalBytes = 0
        var kept = 0
        var changed = false
        for entry in sorted {
            if kept < 400 && totalBytes + entry.2 <= 80_000_000 {
                kept += 1
                totalBytes += entry.2
            } else {
                try? FileManager.default.removeItem(at: entry.0)
                records.removeValue(forKey: entry.0.deletingPathExtension().lastPathComponent)
                changed = true
            }
        }
        if changed { saveRecords() }
    }

    static func normalizedImageData(_ data: Data) -> Data? {
        guard data.count > 1_000, data.count < 10_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 600
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let output = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func fetchCover(groupID: String, releaseIDs: [String]) async -> (Data?, Bool) {
        let groupCover = await fetchCover(at: "https://coverartarchive.org/release-group/\(groupID)/front-500")
        if groupCover.0 != nil { return groupCover }
        var serverFailure = groupCover.1
        for releaseID in releaseIDs {
            let releaseCover = await fetchCover(at: "https://coverartarchive.org/release/\(releaseID)/front-500")
            if releaseCover.0 != nil { return releaseCover }
            serverFailure = serverFailure || releaseCover.1
        }
        return (nil, serverFailure)
    }

    private static func fetchCover(at address: String) async -> (Data?, Bool) {
        guard let url = URL(string: address) else { return (nil, false) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return (normalizedImageData(data), false) }
            return (nil, status == 429 || status >= 500)
        } catch {
            return (nil, true)
        }
    }

    private static func searchPhrase(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func normalized(_ string: String) -> String {
        string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}
