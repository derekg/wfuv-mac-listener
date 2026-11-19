import SwiftUI

enum Palette {
    static let paper = Color(red: 0.977, green: 0.971, blue: 0.956)
    static let ink = Color(red: 0.09, green: 0.09, blue: 0.105)
    static let muted = Color(red: 0.44, green: 0.43, blue: 0.43)
    static let red = Color(red: 0.79, green: 0.12, blue: 0.20)
}

struct ListenerView: View {
    @EnvironmentObject private var radio: MacRadioStore

    var body: some View {
        GeometryReader { geometry in
            let expanded = geometry.size.width >= 550 && geometry.size.height >= 690
            VStack(spacing: 0) {
                masthead
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 16)

                PlayerPanel(radio: radio, expanded: expanded,
                            tight: geometry.size.height < 630)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                if let message = radio.message {
                    Label(message, systemImage: "wifi.exclamationmark")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 10)
                }

                TrackLibraryView(radio: radio)
                    .padding(.horizontal, 20)
                    .frame(maxHeight: .infinity)

                footer
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.paper)
        }
        .onAppear { radio.startUpdates() }
        .onDisappear { radio.stopUpdates() }
    }

    private var masthead: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("90.7").foregroundStyle(Palette.red)
            Text("WFUV").foregroundStyle(Palette.ink)
            Spacer()
            Text("INDEPENDENT RADIO")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(Palette.muted)
        }
        .font(.system(size: 27, weight: .medium, design: .rounded))
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack {
            if let checked = radio.lastChecked {
                Text("Updated \(checked.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("From New York · 90.7 FM")
            }
            Spacer()
            Link("Support WFUV ↗", destination: URL(string: "https://wfuv.org/support")!)
                .foregroundStyle(Palette.red)
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.muted)
    }
}
