import Foundation
import os

@MainActor
final class AppState: ObservableObject {
    enum ServerStatus: Equatable {
        case stopped
        case running(port: UInt16)
        case error(String)
    }

    @Published var regexPattern: String {
        didSet { scheduleConfigurationUpdate() }
    }

    @Published var portString: String {
        didSet { scheduleConfigurationUpdate() }
    }

    @Published private(set) var regexError: String?
    @Published private(set) var portError: String?
    @Published private(set) var serverStatus: ServerStatus = .stopped
    @Published private(set) var lastRequestDescription: String?

    private let playbackController = VideoPlaybackController()
    private lazy var server = WebRequestServer { [weak self] url in
        await self?.handleIncomingURL(url)
    }

    private var configurationTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.dingdongblaster.app", category: "AppState")

    private enum DefaultsKey {
        static let regex = "VideoURLRegex"
        static let port = "WebServerPort"
    }

    init() {
        let defaults = UserDefaults.standard
        if let persistedRegex = defaults.string(forKey: DefaultsKey.regex) {
            regexPattern = persistedRegex
        } else {
            regexPattern = #"https?://.+"#
        }

        if let storedPort = defaults.object(forKey: DefaultsKey.port) as? Int {
            portString = "\(storedPort)"
        } else {
            portString = "9900"
        }
    }

    func bootstrap() {
        scheduleConfigurationUpdate(immediate: true)
    }

    private func scheduleConfigurationUpdate(immediate: Bool = false) {
        configurationTask?.cancel()
        configurationTask = Task { [weak self] in
            guard let self else { return }
            if !immediate {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            await self.applyConfiguration()
        }
    }

    private func applyConfiguration() async {
        let validator = VideoURLValidator(pattern: regexPattern)
        regexError = nil
        portError = nil

        do {
            _ = try validator.compiledRegex()
        } catch let VideoURLValidator.ValidationError.invalidPattern(message) {
            regexError = message
        } catch {
            regexError = error.localizedDescription
        }

        let portResult = ServerConfigurationValidator.normalizePort(portString)
        guard regexError == nil else {
            await stopServer()
            return
        }

        let port: UInt16
        switch portResult {
        case .success(let value):
            port = value
        case .failure(let error):
            switch error {
            case .notANumber:
                portError = "Port must be a number between 1 and 65535."
            case .outOfRange:
                portError = "Port must be between 1 and 65535."
            }
            await stopServer()
            return
        }

        do {
            try await server.restart(with: .init(port: port, validator: validator))
            persist(regex: regexPattern, port: port)
            serverStatus = .running(port: port)
            logger.info("Server running on port \(port)")
        } catch {
            serverStatus = .error(error.localizedDescription)
            logger.error("Failed to start server: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stopServer() async {
        await server.stop()
        serverStatus = .stopped
    }

    private func persist(regex: String, port: UInt16) {
        let defaults = UserDefaults.standard
        defaults.set(regex, forKey: DefaultsKey.regex)
        defaults.set(Int(port), forKey: DefaultsKey.port)
    }

    private func handleIncomingURL(_ url: URL) async {
        lastRequestDescription = url.absoluteString
        playbackController.playStream(from: url)
    }

    func stopPlayback() {
        playbackController.stopPlayback()
    }
}
