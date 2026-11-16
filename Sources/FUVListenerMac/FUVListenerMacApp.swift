import AppKit
import SwiftUI

@main
struct FUVListenerMacApp: App {
    @StateObject private var radio = MacRadioStore()

    var body: some Scene {
        WindowGroup("FUV Listener", id: "listener") {
            ListenerView()
                .environmentObject(radio)
                .frame(minWidth: 340, idealWidth: 380, maxWidth: 470,
                       minHeight: 480, idealHeight: 610)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Radio") {
                Button(radio.isPlaying ? "Pause WFUV" : "Play WFUV") { radio.togglePlayback() }
                    .keyboardShortcut(" ", modifiers: [])
                Button("Refresh Songs") { Task { await radio.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarControls(radio: radio)
        } label: {
            Label("WFUV", systemImage: radio.isPlaying ? "waveform" : "dot.radiowaves.left.and.right")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarControls: View {
    @ObservedObject var radio: MacRadioStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let track = radio.current, track.isMusic {
            Text(track.title)
            Text(track.artist)
        } else {
            Text("WFUV 90.7 FM")
        }
        Divider()
        Button(radio.isPlaying ? "Pause Live Radio" : "Play Live Radio",
               systemImage: radio.isPlaying ? "pause.fill" : "play.fill") {
            radio.togglePlayback()
        }
        Button("Open Player", systemImage: "macwindow") {
            openWindow(id: "listener")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Refresh Song", systemImage: "arrow.clockwise") {
            Task { await radio.refresh() }
        }
        Divider()
        Button("Quit FUV Listener") { NSApp.terminate(nil) }
        .onAppear { Task { await radio.refresh() } }
    }
}
