import SwiftUI

@main
struct FUVListenerMacApp: App {
    @StateObject private var radio = MacRadioStore()

    var body: some Scene {
        WindowGroup("FUV Listener") {
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
    }
}
