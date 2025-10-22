import AppKit
import VLCKit

@MainActor
final class VideoPlaybackController: NSObject {
    private var window: NSWindow?
    private var videoView: VLCVideoView?
    private lazy var windowDelegate = PlaybackWindowDelegate(onClose: { [weak self] in
        self?.stopPlayback()
    })

    private lazy var player: VLCMediaPlayer = {
        let mediaPlayer = VLCMediaPlayer()
        mediaPlayer.delegate = self
        return mediaPlayer
    }()

    private var lastErrorDescription: String?

    func playStream(from url: URL) {
        prepareWindowIfNeeded()
        guard let videoView else { return }

        lastErrorDescription = nil
        if player.isPlaying {
            player.stop()
        }

        let media = VLCMedia(url: url)
        media.addOption(":network-caching=1000")
        media.addOption(":clock-jitter=0")
        media.addOption(":clock-synchro=0")

        player.drawable = videoView
        player.media = media
        player.play()
        bringWindowToFront()
    }

    func stopPlayback() {
        player.stop()
        player.media = nil
        player.drawable = nil
    }

    private func prepareWindowIfNeeded() {
        guard window == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Intercom Blaster"
        window.isReleasedWhenClosed = false
        window.delegate = windowDelegate

        let videoView = VLCVideoView()
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.autoresizingMask = [.width, .height]
        videoView.fillScreen = true

        let containerView = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 720, height: 720))
        containerView.autoresizingMask = [.width, .height]
        containerView.addSubview(videoView)
        videoView.frame = containerView.bounds

        NSLayoutConstraint.activate([
            videoView.widthAnchor.constraint(equalTo: containerView.widthAnchor),
            videoView.heightAnchor.constraint(equalTo: containerView.widthAnchor),
            videoView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            videoView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])

        window.contentView = containerView
        window.center()

        self.window = window
        self.videoView = videoView
    }

    private func bringWindowToFront() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentErrorAlert(message: String) {
        guard message != lastErrorDescription else { return }
        lastErrorDescription = message
        stopPlayback()
        let alert = NSAlert()
        alert.messageText = "Unable to start playback"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

extension VideoPlaybackController: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerEncounteredError(_ aNotification: Notification) {
        Task { @MainActor in
            self.presentErrorAlert(message: "The stream cannot be decoded.")
        }
    }

    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        switch player.state {
        case .error:
            Task { @MainActor in
                self.presentErrorAlert(message: "The stream reported an error.")
            }
        case .ended, .stopped:
            Task { @MainActor in
                self.stopPlayback()
            }
        default:
            break
        }
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
