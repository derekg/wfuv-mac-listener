import AppKit
import SwiftUI

enum Palette {
    static let paper = Color(red: 0.977, green: 0.971, blue: 0.956)
    static let ink = Color(red: 0.09, green: 0.09, blue: 0.105)
    static let muted = Color(red: 0.44, green: 0.43, blue: 0.43)
    static let red = Color(red: 0.79, green: 0.12, blue: 0.20)
}

struct ListenerView: View {
    @EnvironmentObject private var radio: MacRadioStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("playerCollapsed") private var playerCollapsed = false
    @State private var windowReference = WeakWindowReference()
    @State private var expandedContentSize = NSSize(width: 620, height: 760)

    var body: some View {
        GeometryReader { geometry in
            Group {
                if playerCollapsed {
                    CollapsedPlayerPanel(radio: radio, onExpand: { setCollapsed(false) },
                                         onClose: { windowReference.window?.close() })
                        .padding(.horizontal, 12)
                        .padding(.vertical, 13)
                } else {
                    fullPlayer(in: geometry.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(playerCollapsed ? .clear : Palette.paper)
            .background(WindowObserver { window in
                guard windowReference.window !== window else { return }
                windowReference.window = window
                windowReference.regularStyleMask = window.styleMask
                configureWindow(window, collapsed: playerCollapsed, resize: playerCollapsed)
            })
        }
        .onAppear { radio.startUpdates() }
        .onDisappear { radio.stopUpdates() }
    }

    private func fullPlayer(in size: CGSize) -> some View {
        let expanded = size.width >= 550 && size.height >= 690
        return VStack(spacing: 0) {
            masthead
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 16)

            PlayerPanel(radio: radio, expanded: expanded, tight: size.height < 630) {
                setCollapsed(true)
            }
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
    }

    private func setCollapsed(_ collapsed: Bool) {
        guard playerCollapsed != collapsed else { return }
        if collapsed, let playerWindow = windowReference.window {
            expandedContentSize = playerWindow.contentRect(forFrameRect: playerWindow.frame).size
        }
        playerCollapsed = collapsed
        guard let playerWindow = windowReference.window else { return }
        DispatchQueue.main.async {
            configureWindow(playerWindow, collapsed: collapsed, resize: true)
        }
    }

    private func configureWindow(_ window: NSWindow, collapsed: Bool, resize: Bool) {
        let miniSize = NSSize(width: 444, height: 104)
        // Let the window cross between both size ranges before applying the new limits.
        window.contentMinSize = miniSize
        window.contentMaxSize = NSSize(width: 720, height: 950)

        if collapsed {
            window.styleMask = .borderless
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = true
        } else {
            window.styleMask = windowReference.regularStyleMask
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.isMovableByWindowBackground = false
        }

        if resize {
            let target = collapsed ? miniSize : NSSize(width: max(580, expandedContentSize.width),
                                                        height: max(680, expandedContentSize.height))
            let current = window.frame
            let content = window.contentRect(forFrameRect: current)
            var frame = current
            frame.size.width += target.width - content.width
            frame.size.height += target.height - content.height
            frame.origin.y = current.maxY - frame.height
            if let visible = window.screen?.visibleFrame {
                frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
                frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
            }
            window.setFrame(frame, display: true, animate: !reduceMotion)
        }

        window.contentMinSize = collapsed ? miniSize : NSSize(width: 390, height: 500)
        window.contentMaxSize = collapsed ? miniSize : NSSize(width: 720, height: 950)
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

private final class WeakWindowReference {
    weak var window: NSWindow?
    var regularStyleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
}

private struct WindowObserver: NSViewRepresentable {
    let onWindowReady: (NSWindow) -> Void

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.onWindowReady = onWindowReady
        return view
    }

    func updateNSView(_ view: ObservingView, context: Context) {
        view.onWindowReady = onWindowReady
    }

    final class ObservingView: NSView {
        var onWindowReady: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                self.onWindowReady?(window)
            }
        }
    }
}
