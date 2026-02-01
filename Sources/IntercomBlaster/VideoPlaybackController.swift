import AppKit
import Network
import VLCKit

@MainActor
final class VideoPlaybackController: NSObject {
    private static let preflightPort: UInt16 = 554
    private static let preflightAttempts = 3
    private static let preflightDelayNanoseconds: UInt64 = 200_000_000
    private static let preflightTimeout: TimeInterval = 0.5
    private var window: NSWindow?
    private var videoView: VLCVideoView?
    private var placeholderImageView: NSImageView?
    private var hasRenderedVideo = false
    private var playbackRequestID = UUID()
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
        guard videoView != nil else { return }

        lastErrorDescription = nil
        hasRenderedVideo = false
        setPlaceholderVisible(true)
        if player.isPlaying {
            player.stop()
        }

        let requestID = UUID()
        playbackRequestID = requestID
        Task { [weak self] in
            guard let self else { return }
            await self.preflightWakeWifiIfNeeded(for: url)
            guard self.playbackRequestID == requestID else { return }
            self.startPlayback(with: url)
        }
    }

    private func startPlayback(with url: URL) {
        guard let videoView else { return }

        let media = VLCMedia(url: url)
        // Favor fast startup over buffering. Tune these if playback gets choppy.
        media.addOption(":network-caching=200")
        media.addOption(":live-caching=200")
        media.addOption(":drop-late-frames")
        media.addOption(":skip-frames")
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
        hasRenderedVideo = false
        setPlaceholderVisible(true)
    }

    private var windowSize = CGSize(width: 720, height: 720)

    func updateWindowSize(_ size: CGSize) {
        let clampedWidth = max(200, min(size.width, 1600))
        let clampedHeight = max(200, min(size.height, 1600))
        windowSize = CGSize(width: clampedWidth, height: clampedHeight)
        if let window {
            window.setContentSize(NSSize(width: clampedWidth, height: clampedHeight))
        }
    }

    private func prepareWindowIfNeeded() {
        guard window == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Intercom Blaster"
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = windowDelegate

        let containerView = NSView(
            frame: window.contentView?.bounds
                ?? NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height))
        containerView.autoresizingMask = [.width, .height]
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor

        let checkerboardView = CheckerboardView()
        checkerboardView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(checkerboardView)

        let videoView = VLCVideoView()
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.autoresizingMask = [.width, .height]
        videoView.fillScreen = true
        videoView.wantsLayer = true
        videoView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.addSubview(videoView)

        let placeholderImageView = NSImageView()
        placeholderImageView.translatesAutoresizingMaskIntoConstraints = false
        placeholderImageView.imageScaling = .scaleProportionallyUpOrDown
        placeholderImageView.imageAlignment = .alignCenter
        placeholderImageView.image = loadPlaceholderImage()
        containerView.addSubview(placeholderImageView)

        NSLayoutConstraint.activate([
            checkerboardView.widthAnchor.constraint(equalTo: containerView.widthAnchor),
            checkerboardView.heightAnchor.constraint(equalTo: containerView.heightAnchor),
            checkerboardView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            checkerboardView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            videoView.widthAnchor.constraint(equalTo: containerView.widthAnchor),
            videoView.heightAnchor.constraint(equalTo: containerView.heightAnchor),
            videoView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            videoView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            placeholderImageView.widthAnchor.constraint(equalTo: containerView.widthAnchor),
            placeholderImageView.heightAnchor.constraint(equalTo: containerView.heightAnchor),
            placeholderImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            placeholderImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])

        window.contentView = containerView
        window.center()

        self.window = window
        self.videoView = videoView
        self.placeholderImageView = placeholderImageView
    }

    private func bringWindowToFront() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Sends a dummy request to the camera to wake up wifi (otherwise VLC might run
    /// into "no route to host" and the retry timing of VLC is too slow).
    private func preflightWakeWifiIfNeeded(for url: URL) async {
        guard let host = url.host, !host.isEmpty else { return }

        for attempt in 1...Self.preflightAttempts {
            let reachable = await probeTcpReachability(host: host, port: Self.preflightPort)
            if reachable {
                return
            }
            if attempt < Self.preflightAttempts {
                try? await Task.sleep(nanoseconds: Self.preflightDelayNanoseconds)
            }
        }
    }

    private func probeTcpReachability(host: String, port: UInt16) async -> Bool {
        final class ProbeState: @unchecked Sendable {
            let connection: NWConnection
            let continuation: CheckedContinuation<Bool, Never>
            var completed = false

            init(connection: NWConnection, continuation: CheckedContinuation<Bool, Never>) {
                self.connection = connection
                self.continuation = continuation
            }

            func finish(_ reachable: Bool) {
                guard !completed else { return }
                completed = true
                connection.cancel()
                continuation.resume(returning: reachable)
            }
        }

        return await withCheckedContinuation { continuation in
            let nwHost = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: true)
                return
            }

            let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)
            let queue = DispatchQueue(label: "intercom.preflight")
            let state = ProbeState(connection: connection, continuation: continuation)

            connection.stateUpdateHandler = { stateUpdate in
                switch stateUpdate {
                case .ready:
                    state.finish(true)
                case .failed(let error):
                    if case let .posix(code) = error,
                       code == .ENETUNREACH || code == .EHOSTUNREACH {
                        state.finish(false)
                    } else {
                        state.finish(true)
                    }
                case .cancelled:
                    state.finish(false)
                default:
                    break
                }
            }

            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + Self.preflightTimeout) {
                state.finish(false)
            }
        }
    }

    private func loadPlaceholderImage() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "Intercom", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private func setPlaceholderVisible(_ isVisible: Bool) {
        guard let placeholderImageView else { return }

        if isVisible {
            placeholderImageView.isHidden = false
            placeholderImageView.alphaValue = 1.0
            return
        }

        if placeholderImageView.isHidden {
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 1.0
            placeholderImageView.animator().alphaValue = 0.0
        }, completionHandler: { [weak placeholderImageView] in
            Task { @MainActor in
                placeholderImageView?.isHidden = true
                placeholderImageView?.alphaValue = 1.0
            }
        })
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
        case .opening, .buffering:
            Task { @MainActor in
                if !self.hasRenderedVideo {
                    self.setPlaceholderVisible(true)
                }
            }
        case .playing, .paused:
            Task { @MainActor in
                self.hasRenderedVideo = true
                self.setPlaceholderVisible(false)
            }
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

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in
            guard !self.hasRenderedVideo else { return }
            self.hasRenderedVideo = true
            self.setPlaceholderVisible(false)
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

private final class CheckerboardView: NSView {
    private let squareSize: CGFloat = 16
    private let lightColor = NSColor(white: 1.0, alpha: 0.33)
    private let darkColor = NSColor(white: 0.9, alpha: 0.33)

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let cols = Int(ceil(dirtyRect.width / squareSize))
        let rows = Int(ceil(dirtyRect.height / squareSize))

        for row in 0..<rows {
            for col in 0..<cols {
                let isLight = (row + col).isMultiple(of: 2)
                let color = isLight ? lightColor : darkColor
                let rect = CGRect(
                    x: dirtyRect.origin.x + CGFloat(col) * squareSize,
                    y: dirtyRect.origin.y + CGFloat(row) * squareSize,
                    width: squareSize,
                    height: squareSize
                )
                context.setFillColor(color.cgColor)
                context.fill(rect)
            }
        }
    }
}
