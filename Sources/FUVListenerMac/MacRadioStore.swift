import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class MacRadioStore: ObservableObject {
    @Published private(set) var current: LiveTrack?
    @Published private(set) var recent: [Song] = []
    @Published private(set) var favorites: [Song] = []
    @Published private(set) var artwork: [String: Data] = [:]
    @Published private(set) var isPlaying = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastChecked: Date?
    @Published var message: String?

    private let player = AVPlayer()
    private let artworkService: ArtworkService
    private var artworkLoading = Set<String>()
    private var artworkOrder: [String] = []
    private var pollTask: Task<Void, Never>?
    private var playStatus: NSKeyValueObservation?
    private var itemStatus: NSKeyValueObservation?
    private var stationTrack: LiveTrack?
    private var playlist: [Song] = []

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        artworkService = ArtworkService(cacheDirectory: support
            .appendingPathComponent("FUVListenerMac/Artwork", isDirectory: true))
        if let data = UserDefaults.standard.data(forKey: "favoriteSongs"),
           let decoded = try? JSONDecoder().decode([Song].self, from: data) {
            favorites = decoded
        }
        player.automaticallyWaitsToMinimizeStalling = true
        playStatus = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                if player.timeControlStatus == .playing { self?.message = nil }
            }
        }
    }

    var currentKey: String? {
        guard let current, current.isMusic else { return nil }
        return Song.favoriteID(title: current.title, artist: current.artist)
    }

    func imageData(for song: Song) -> Data? { artwork[song.favoriteID] }
    func imageDataForCurrent() -> Data? { currentKey.flatMap { artwork[$0] } }
    func isFavorite(_ song: Song) -> Bool { favorites.contains { $0.favoriteID == song.favoriteID } }

    func toggleFavorite(_ song: Song) {
        if let index = favorites.firstIndex(where: { $0.favoriteID == song.favoriteID }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(song, at: 0)
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(favorites), forKey: "favoriteSongs")
        Task { await artworkService.setPinnedSongs(favorites) }
    }

    func toggleCurrentFavorite() {
        guard let current, current.isMusic else { return }
        toggleFavorite(Song(title: current.title, artist: current.artist,
                            playedAt: current.playedAt ?? .now))
    }

    func startUpdates() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.artworkService.setPinnedSongs(self.favorites)
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(for: .seconds(45))
            }
        }
    }

    func stopUpdates() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let feed = WFUVService.fetchSongs()
        async let live = WFUVService.fetchNowPlaying()
        var didUpdate = false
        do {
            playlist = try await feed
            didUpdate = true
        } catch { }
        do {
            stationTrack = try await live
            didUpdate = true
        } catch { }

        if !didUpdate {
            message = "Couldn’t refresh songs. Trying again soon."
            return
        }
        lastChecked = .now
        message = nil
        let selected = TrackSelection.resolve(station: stationTrack,
                                              latest: playlist.first, now: .now).0
        current = selected
        // Derive both surfaces from the same selection, even when the station JSON
        // and playlist RSS reach us at different times.
        if let selected, selected.isMusic {
            let first = Song(title: selected.title, artist: selected.artist,
                             playedAt: selected.playedAt ?? playlist.first?.playedAt ?? .now)
            recent = [first] + playlist.filter { $0.favoriteID != first.favoriteID }
        } else {
            recent = playlist
        }
        if let selected, selected.isMusic {
            loadArtwork(title: selected.title, artist: selected.artist,
                        preferredURL: selected.artworkURL, album: selected.album)
        }
        for song in recent.prefix(4) {
            loadArtwork(title: song.title, artist: song.artist)
        }
    }

    func loadArtwork(for song: Song) {
        loadArtwork(title: song.title, artist: song.artist)
    }

    private func keepArtwork(_ data: Data, for key: String) {
        artwork[key] = data
        artworkOrder.removeAll { $0 == key }
        artworkOrder.append(key)
        while artworkOrder.count > 24 {
            let removed = artworkOrder.removeFirst()
            artwork.removeValue(forKey: removed)
        }
    }

    private func loadArtwork(title: String, artist: String,
                             preferredURL: URL? = nil, album: String? = nil) {
        let key = Song.favoriteID(title: title, artist: artist)
        guard artwork[key] == nil, !artworkLoading.contains(key) else { return }
        artworkLoading.insert(key)
        Task { [weak self] in
            guard let self else { return }
            if let cached = await artworkService.cachedImageData(title: title, artist: artist) {
                keepArtwork(cached, for: key)
            }
            if let found = await artworkService.imageData(title: title, artist: artist,
                                                          preferredURL: preferredURL,
                                                          preferredAlbum: album) {
                keepArtwork(found, for: key)
            }
            artworkLoading.remove(key)
        }
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
            return
        }
        if player.currentItem == nil {
            let item = AVPlayerItem(url: WFUVService.highQualityStreamURL)
            itemStatus = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                Task { @MainActor [weak self] in
                    if item.status == .failed {
                        self?.isPlaying = false
                        self?.message = "Stream unavailable. Try again in a moment."
                    }
                }
            }
            player.replaceCurrentItem(with: item)
        }
        player.play()
        isPlaying = true
    }
}
