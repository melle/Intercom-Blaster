import AppKit
import AVKit

@MainActor
final class VideoPlaybackController {
    private var window: NSWindow?
    private var player: AVPlayer?
    private var playerView: AVPlayerView?
    private lazy var windowDelegate = PlaybackWindowDelegate(onClose: { [weak self] in
        self?.stopPlayback()
    })

    func playStream(from url: URL) {
        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        playerItem.preferredForwardBufferDuration = 1
        prepareWindowIfNeeded()
        playerView?.player = player
        self.player = player
        player.play()
        bringWindowToFront()
    }

    func stopPlayback() {
        player?.pause()
        player = nil
        playerView?.player = nil
    }

    private func prepareWindowIfNeeded() {
        guard window == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 450),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DingDong Blaster"
        window.isReleasedWhenClosed = false
        window.delegate = windowDelegate

        let playerView = AVPlayerView()
        playerView.controlsStyle = .none
        playerView.autoresizingMask = [.width, .height]
        window.contentView = playerView
        window.center()

        self.window = window
        self.playerView = playerView
    }

    private func bringWindowToFront() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class PlaybackWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
