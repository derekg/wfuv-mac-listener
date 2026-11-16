import AppKit
import SwiftUI

private enum Palette {
    static let paper = Color(red: 0.977, green: 0.971, blue: 0.956)
    static let ink = Color(red: 0.09, green: 0.09, blue: 0.105)
    static let muted = Color(red: 0.44, green: 0.43, blue: 0.43)
    static let red = Color(red: 0.79, green: 0.12, blue: 0.20)
}

private enum LibraryPage: String, CaseIterable {
    case recent = "Recently played"
    case favorites = "Favorites"
}

struct ListenerView: View {
    @EnvironmentObject private var radio: MacRadioStore
    @State private var page: LibraryPage = .recent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                masthead
                playerCard
                if let message = radio.message {
                    Label(message, systemImage: "wifi.exclamationmark")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 2)
                        .transition(.opacity)
                }
                library
                footer
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.paper)
        .onAppear { radio.startUpdates() }
        .onDisappear { radio.stopUpdates() }
    }

    private var masthead: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("90.7")
                .foregroundStyle(Palette.red)
            Text("WFUV")
                .foregroundStyle(Palette.ink)
            Spacer()
            Text("FUV LISTENER")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Palette.muted)
        }
        .font(.system(size: 29, weight: .medium, design: .rounded))
        .accessibilityElement(children: .combine)
    }

    private var playerCard: some View {
        let track = radio.current
        let song = track?.isMusic == true ? track : nil
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 7) {
                Circle().fill(Palette.red).frame(width: 7, height: 7)
                Text("ON AIR · WFUV")
                    .tracking(1.6)
                Spacer()
                if radio.isRefreshing {
                    ProgressView().controlSize(.mini)
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.80))

            HStack(alignment: .center, spacing: 16) {
                CoverArt(data: radio.imageDataForCurrent(),
                         title: song?.title ?? "Independent radio",
                         artist: song?.artist ?? "New York",
                         size: 116)
                    .shadow(color: .black.opacity(0.17), radius: 13, y: 7)

                VStack(alignment: .leading, spacing: 6) {
                    Text(song?.title ?? "Listen live")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                    Text(song?.artist ?? "Music discovery on 90.7 FM")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 116)

            HStack(spacing: 14) {
                Button(action: radio.togglePlayback) {
                    Label(radio.isPlaying ? "Pause" : "Play",
                          systemImage: radio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.red)
                .controlSize(.large)
                .accessibilityLabel(radio.isPlaying ? "Pause WFUV radio" : "Play WFUV radio")

                if let track = song {
                    Button(action: radio.toggleCurrentFavorite) {
                        Image(systemName: isCurrentFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 18))
                            .foregroundStyle(isCurrentFavorite ? Palette.red : .white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCurrentFavorite ? "Remove favorite" : "Add favorite")
                    Button {
                        let song = Song(title: track.title, artist: track.artist,
                                        playedAt: track.playedAt ?? .now)
                        NSWorkspace.shared.open(song.spotifySearchURL)
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help("Find on Spotify")
                }
                Spacer(minLength: 0)
                Text(radio.isPlaying ? "LIVE" : "90.7 FM")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: cardColors,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .accessibilityElement(children: .contain)
    }

    private var isCurrentFavorite: Bool {
        guard let track = radio.current, track.isMusic else { return false }
        return radio.favorites.contains {
            $0.favoriteID == Song.favoriteID(title: track.title, artist: track.artist)
        }
    }

    private var cardColors: [Color] {
        let choices: [[Color]] = [
            [Color(red: 0.22, green: 0.32, blue: 0.40), Color(red: 0.13, green: 0.16, blue: 0.22)],
            [Color(red: 0.35, green: 0.27, blue: 0.30), Color(red: 0.17, green: 0.15, blue: 0.20)],
            [Color(red: 0.30, green: 0.33, blue: 0.25), Color(red: 0.17, green: 0.19, blue: 0.18)]
        ]
        let index = (radio.currentKey ?? "wfuv").utf8.reduce(0) { ($0 + Int($1)) % choices.count }
        return choices[index]
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(page.rawValue)
                    .font(.system(size: 23, weight: .bold, design: .serif))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button {
                    Task { await radio.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.red)
                .disabled(radio.isRefreshing)
                .help("Refresh songs")
            }
            HStack(spacing: 14) {
                ForEach(LibraryPage.allCases, id: \.self) { option in
                    Button(option.rawValue) { page = option }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: page == option ? .semibold : .regular))
                        .foregroundStyle(page == option ? Palette.red : Palette.muted)
                        .padding(.bottom, 6)
                        .overlay(alignment: .bottom) {
                            if page == option { Rectangle().fill(Palette.red).frame(height: 2) }
                        }
                }
                Spacer()
            }
            Divider()
            let songs = page == .recent ? Array(radio.recent.prefix(8)) : radio.favorites
            if songs.isEmpty {
                Text(page == .recent ? "Songs will appear when the station feed responds." :
                        "Heart a song to keep it here.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .padding(.vertical, 18)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(songs) { song in
                        SongRow(song: song, data: radio.imageData(for: song),
                                favorite: radio.isFavorite(song)) {
                            radio.toggleFavorite(song)
                        }
                        .onAppear { radio.loadArtwork(for: song) }
                        if song.id != songs.last?.id { Divider().padding(.leading, 54) }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let lastChecked = radio.lastChecked {
                Text("Updated \(lastChecked.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("Independent radio from New York")
            }
            Spacer()
            Link("Support WFUV ↗", destination: URL(string: "https://wfuv.org/support")!)
                .foregroundStyle(Palette.red)
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.muted)
    }
}

private struct SongRow: View {
    let song: Song
    let data: Data?
    let favorite: Bool
    let toggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            CoverArt(data: data, title: song.title, artist: song.artist, size: 43)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Text(song.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 3)
            Text(song.playedAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10))
                .foregroundStyle(Palette.muted)
            Button(action: toggleFavorite) {
                Image(systemName: favorite ? "heart.fill" : "heart")
                    .foregroundStyle(Palette.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(favorite ? "Remove \(song.title) from favorites" : "Favorite \(song.title)")
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Find on Spotify") { NSWorkspace.shared.open(song.spotifySearchURL) }
            Button(favorite ? "Remove Favorite" : "Add Favorite", action: toggleFavorite)
        }
    }
}

private struct CoverArt: View {
    let data: Data?
    let title: String
    let artist: String
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [Color(red: 0.28, green: 0.13, blue: 0.21),
                                            Color(red: 0.09, green: 0.11, blue: 0.18)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("90.7 / WFUV")
                            .font(.system(size: max(4, size * 0.065), weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                        Rectangle().fill(Palette.red).frame(width: size * 0.23, height: 2)
                        Spacer(minLength: 0)
                        if size > 70 {
                            Text(title)
                                .font(.system(size: size * 0.13, weight: .bold, design: .serif))
                                .lineLimit(3)
                            Text(artist)
                                .font(.system(size: size * 0.065))
                                .lineLimit(1)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(size * 0.09)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.11))
        .accessibilityLabel("Artwork for \(title) by \(artist)")
    }
}
