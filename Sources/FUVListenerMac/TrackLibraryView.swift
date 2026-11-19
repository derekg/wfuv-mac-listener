import AppKit
import SwiftUI

private enum LibraryPage: String, CaseIterable {
    case recent = "Recent"
    case favorites = "Favorites"
}

struct TrackLibraryView: View {
    @ObservedObject var radio: MacRadioStore
    @State private var page: LibraryPage = .recent

    private var songs: [Song] {
        page == .recent ? Array(radio.recent.prefix(20)) : radio.favorites
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Played on WFUV")
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

            HStack(spacing: 3) {
                ForEach(LibraryPage.allCases, id: \.self) { option in
                    Button(option.rawValue) { page = option }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: page == option ? .semibold : .medium))
                        .foregroundStyle(page == option ? Palette.ink : Palette.muted)
                        .frame(width: 82, height: 25)
                        .background(page == option ? .white : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityAddTraits(page == option ? [.isSelected] : [])
                }
            }
            .padding(3)
            .background(Palette.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))

            ScrollView {
                if songs.isEmpty {
                    Text(page == .recent ? "Songs will appear when WFUV's feed responds." :
                            "Heart a song to keep it here.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(songs) { song in
                            SongRow(song: song,
                                    data: radio.imageData(for: song),
                                    favorite: radio.isFavorite(song)) {
                                radio.toggleFavorite(song)
                            }
                            .onAppear { radio.loadArtwork(for: song) }
                            if song.id != songs.last?.id {
                                Divider().padding(.leading, 72)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
            }
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(Palette.ink.opacity(0.06), lineWidth: 1)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct SongRow: View {
    let song: Song
    let data: Data?
    let favorite: Bool
    let toggleFavorite: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 11) {
            CoverArt(data: data, title: song.title, artist: song.artist, size: 50)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Text(song.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                Text(song.playedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted.opacity(0.80))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: toggleFavorite) {
                Image(systemName: favorite ? "heart.fill" : "heart")
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.red)
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(favorite ? "Remove \(song.title) from favorites" : "Favorite \(song.title)")

            Button {
                NSWorkspace.shared.open(song.spotifySearchURL)
            } label: {
                HStack(spacing: 3) {
                    Text("Spotify")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Find \(song.title) on Spotify")
            .help("Find on Spotify")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 10)
        .background(hovered ? Palette.red.opacity(0.055) : .clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovered)
    }
}
