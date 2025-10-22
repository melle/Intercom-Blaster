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
    private var statusObservation: NSKeyValueObservation?

    func playStream(from url: URL) {
        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        playerItem.preferredForwardBufferDuration = 1
        prepareWindowIfNeeded()
        playerView?.player = player
        self.player = player
        observeStatus(of: playerItem)
        player.play()
        bringWindowToFront()
    }

    func stopPlayback() {
        player?.pause()
        player = nil
        playerView?.player = nil
        statusObservation = nil
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

    private func observeStatus(of item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] playerItem, _ in
            guard let self else { return }
            switch playerItem.status {
            case .readyToPlay:
                break
            case .failed:
                Task { @MainActor in
                    self.handlePlaybackFailure(item: playerItem)
                }
            case .unknown:
                break
            @unknown default:
                break
            }
        }
    }

    private func handlePlaybackFailure(item: AVPlayerItem) {
        let errorDescription = item.error?.localizedDescription ?? "Unknown error"
        stopPlayback()
        let alert = NSAlert()
        alert.messageText = "Unable to start playback"
        alert.informativeText = errorDescription
        alert.alertStyle = .warning
        alert.runModal()
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
