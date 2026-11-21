import AppKit
import SwiftUI

struct PlayerPanel: View {
    @ObservedObject var radio: MacRadioStore
    let expanded: Bool
    let tight: Bool
    let onCollapse: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowing = false

    private var track: LiveTrack? {
        guard let current = radio.current, current.isMusic else { return nil }
        return current
    }

    private var artSize: CGFloat { expanded ? 150 : tight ? 104 : 124 }
    private var playSize: CGFloat { expanded ? 58 : tight ? 48 : 54 }

    var body: some View {
        VStack(alignment: .leading, spacing: tight ? 9 : 12) {
            HStack(spacing: 8) {
                Circle().fill(Palette.red).frame(width: 7, height: 7)
                Text("NOW PLAYING · WFUV")
                    .tracking(1.4)
                Spacer()
                if radio.isLiveAudio {
                    LiveBars(expanded: expanded)
                } else if radio.isPlaying {
                    ProgressView().controlSize(.mini)
                }
                Text(radio.isLiveAudio ? "LIVE" : radio.isPlaying ? "CONNECTING" : "PAUSED")
                    .tracking(1.1)
                Button(action: onCollapse) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 25, height: 24)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse player")
                .help("Collapse player")
            }
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))

            HStack(alignment: .center, spacing: expanded ? 18 : 14) {
                ZStack {
                    if expanded && radio.isLiveAudio && !reduceMotion {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Palette.red.opacity(0.28))
                            .frame(width: artSize + 10, height: artSize + 10)
                            .blur(radius: 25)
                            .scaleEffect(glowing ? 1.08 : 0.92)
                            .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                                       value: glowing)
                            .onAppear { glowing = true }
                            .onDisappear { glowing = false }
                    }
                    CoverArt(data: radio.imageDataForCurrent(),
                             title: track?.title ?? "WFUV",
                             artist: track?.artist ?? "90.7 FM",
                             size: artSize)
                        .shadow(color: .black.opacity(0.28), radius: 13, y: 9)
                }

                VStack(alignment: .leading, spacing: tight ? 4 : 7) {
                    Text(track == nil ? "LIVE RADIO" : "ON THE AIR")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.56))
                    Text(track?.title ?? "Listen live")
                        .font(.system(size: expanded ? 27 : 23, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                    Text(track?.artist ?? "Independent music from New York")
                        .font(.system(size: expanded ? 16 : 13))
                        .foregroundStyle(.white.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                    if let track {
                        HStack(spacing: 14) {
                            Button(action: radio.toggleCurrentFavorite) {
                                Image(systemName: isCurrentFavorite ? "heart.fill" : "heart")
                                    .foregroundStyle(isCurrentFavorite ? Palette.red : .white)
                                    .font(.system(size: 17))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isCurrentFavorite ? "Remove favorite" : "Add favorite")

                            Button {
                                openSpotify(for: track)
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Spotify")
                                    Image(systemName: "arrow.up.right")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.86))
                            }
                            .buttonStyle(.plain)
                            .help("Find this song on Spotify")
                        }
                        .padding(.top, 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: radio.togglePlayback) {
                    Image(systemName: radio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: expanded ? 23 : 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: radio.isPlaying ? 0 : 2)
                        .frame(width: playSize, height: playSize)
                        .background(Palette.red, in: Circle())
                        .shadow(color: Palette.red.opacity(0.35), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(radio.isPlaying ? "Pause WFUV radio" : "Play WFUV radio")
                .help(radio.isPlaying ? "Pause live radio" : "Play live radio")
            }
            .frame(minHeight: artSize)
        }
        .padding(tight ? 16 : 18)
        .background {
            RoundedRectangle(cornerRadius: 25)
                .fill(LinearGradient(colors: PlayerCardColors.colors(for: radio.currentKey),
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 25)
                        .strokeBorder(.white.opacity(0.09), lineWidth: 1)
                }
        }
        .animation(.easeInOut(duration: 0.35), value: radio.currentKey)
        .accessibilityElement(children: .contain)
    }

    private var isCurrentFavorite: Bool {
        guard let track else { return false }
        return radio.favorites.contains {
            $0.favoriteID == Song.favoriteID(title: track.title, artist: track.artist)
        }
    }

    private func openSpotify(for track: LiveTrack) {
        let song = Song(title: track.title, artist: track.artist,
                        playedAt: track.playedAt ?? .now)
        NSWorkspace.shared.open(song.spotifySearchURL)
    }
}

struct CollapsedPlayerPanel: View {
    @ObservedObject var radio: MacRadioStore
    let onExpand: () -> Void
    let onClose: () -> Void

    private var track: LiveTrack? {
        guard let current = radio.current, current.isMusic else { return nil }
        return current
    }

    private var isCurrentFavorite: Bool {
        guard let track else { return false }
        return radio.favorites.contains {
            $0.favoriteID == Song.favoriteID(title: track.title, artist: track.artist)
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onExpand) {
                CoverArt(data: radio.imageDataForCurrent(),
                         title: track?.title ?? "WFUV",
                         artist: track?.artist ?? "90.7 FM",
                         size: 54)
            }
            .buttonStyle(.plain)
            .help("Expand player")
            .accessibilityLabel("Expand player")

            VStack(alignment: .leading, spacing: 2) {
                Text(radio.isLiveAudio ? "LIVE · WFUV" : radio.isPlaying ? "CONNECTING" : "WFUV 90.7")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.67))
                Text(track?.title ?? "Listen live")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(track?.artist ?? "Independent music from New York")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: radio.toggleCurrentFavorite) {
                Image(systemName: isCurrentFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isCurrentFavorite ? Palette.red : .white)
                    .frame(width: 26, height: 42)
            }
            .buttonStyle(.plain)
            .disabled(track == nil)
            .opacity(track == nil ? 0.4 : 1)
            .accessibilityLabel(isCurrentFavorite ? "Remove current song from favorites" :
                                "Add current song to favorites")
            .help(isCurrentFavorite ? "Remove from favorites" : "Add to favorites")

            Button(action: radio.togglePlayback) {
                Image(systemName: radio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: radio.isPlaying ? 0 : 1)
                    .frame(width: 42, height: 42)
                    .background(Palette.red, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(radio.isPlaying ? "Pause WFUV radio" : "Play WFUV radio")

            Button(action: onExpand) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 21, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open playlist and favorites")
            .help("Open playlist and favorites")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 16, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close player window")
            .help("Close player window")
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: PlayerCardColors.colors(for: radio.currentKey),
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.23), radius: 10, y: 5)
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .contain)
    }
}

private enum PlayerCardColors {
    static func colors(for key: String?) -> [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.20, green: 0.31, blue: 0.39), Color(red: 0.10, green: 0.14, blue: 0.20)],
            [Color(red: 0.34, green: 0.24, blue: 0.29), Color(red: 0.14, green: 0.12, blue: 0.18)],
            [Color(red: 0.28, green: 0.32, blue: 0.24), Color(red: 0.13, green: 0.16, blue: 0.15)]
        ]
        let index = (key ?? "wfuv").utf8.reduce(0) { ($0 + Int($1)) % palettes.count }
        return palettes[index]
    }
}

private struct LiveBars: View {
    let expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<4) { index in
                Capsule()
                    .fill(Palette.red)
                    .frame(width: 3, height: reduceMotion ? 9 : animate ? heights[index] : 4)
                    .animation(reduceMotion ? nil :
                        .easeInOut(duration: 0.55 + Double(index) * 0.13)
                            .repeatForever(autoreverses: true).delay(Double(index) * 0.1),
                        value: animate)
            }
        }
        .frame(height: expanded ? 22 : 16)
        .onAppear { animate = true }
        .accessibilityHidden(true)
    }

    private var heights: [CGFloat] { expanded ? [10, 20, 14, 18] : [8, 16, 11, 14] }
}

struct CoverArt: View {
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text("90.7 / WFUV")
                            .font(.system(size: max(4, size * 0.065), weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                        Rectangle().fill(Palette.red).frame(width: size * 0.23, height: 2)
                        Spacer(minLength: 0)
                        if size > 80 {
                            Text(title)
                                .font(.system(size: size * 0.11, weight: .bold, design: .serif))
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
        .clipShape(RoundedRectangle(cornerRadius: size * 0.10))
        .accessibilityLabel("Artwork for \(title) by \(artist)")
    }
}
