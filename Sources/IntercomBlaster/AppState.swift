import Foundation
import os
import IntercomBlasterCore
import Darwin

private enum NetworkAddressResolver {
    static func primaryHostIdentifier() -> String {
        if let ip = primaryIPv4Address() {
            return ip
        }
        if let bonjour = Host.current().localizedName {
            return sanitizeHostName(bonjour)
        }
        return sanitizeHostName(ProcessInfo.processInfo.hostName)
    }

    private static func primaryIPv4Address() -> String? {
        var addressList: [String] = []
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else { return nil }
        defer { freeifaddrs(ifaddrPointer) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let flags = Int32(interface.ifa_flags)
            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }
            let isUp = (flags & IFF_UP) == IFF_UP
            let isRunning = (flags & IFF_RUNNING) == IFF_RUNNING
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK
            guard isUp, isRunning, !isLoopback else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            if result == 0 {
                let address = hostname.withUnsafeBufferPointer { buffer -> String? in
                    guard let base = buffer.baseAddress else { return nil }
                    return String(validatingCString: base)
                }
                if let address, !address.isEmpty {
                    addressList.append(address)
                }
            }
        }
        return addressList.first
    }

    private static func sanitizeHostName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
    }
}

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
@Published private(set) var hostAddress: String
@Published var windowWidthString: String {
    didSet { scheduleWindowSizeUpdate() }
}
@Published var windowHeightString: String {
    didSet { scheduleWindowSizeUpdate() }
}
@Published private(set) var windowSizeError: String?

private let playbackController = VideoPlaybackController()
private lazy var server = WebRequestServer { [weak self] url in
    await self?.handleIncomingURL(url)
}

private var configurationTask: Task<Void, Never>?
private var windowSizeTask: Task<Void, Never>?
private let logger = Logger(subsystem: "com.intercomblaster.app", category: "AppState")

private enum DefaultsKey {
    static let regex = "IntercomBlasterVideoURLRegex"
    static let port = "IntercomBlasterWebServerPort"
    static let windowWidth = "IntercomBlasterWindowWidth"
    static let windowHeight = "IntercomBlasterWindowHeight"
}
    private static let defaultRegexPattern = #"(https?|rtsp)://.+"#
    private static let legacyDefaultRegexPattern = #"https?://.+"#

    init() {
        let defaults = UserDefaults.standard
        let resolvedRegex: String
        var shouldPersistResolvedRegex = false
        if let persistedRegex = defaults.string(forKey: DefaultsKey.regex) {
            if persistedRegex == Self.legacyDefaultRegexPattern {
                resolvedRegex = Self.defaultRegexPattern
                shouldPersistResolvedRegex = true
            } else {
                resolvedRegex = persistedRegex
            }
        } else {
            resolvedRegex = Self.defaultRegexPattern
        }
        regexPattern = resolvedRegex
        if shouldPersistResolvedRegex {
            defaults.set(resolvedRegex, forKey: DefaultsKey.regex)
        }

        if let storedPort = defaults.object(forKey: DefaultsKey.port) as? Int {
            portString = "\(storedPort)"
    } else {
        portString = "9900"
    }

        hostAddress = NetworkAddressResolver.primaryHostIdentifier()

        let storedWidth = defaults.double(forKey: DefaultsKey.windowWidth)
        let storedHeight = defaults.double(forKey: DefaultsKey.windowHeight)

        let resolvedWidth = storedWidth >= 200 ? storedWidth : 720
        let resolvedHeight = storedHeight >= 200 ? storedHeight : 720

        windowWidthString = String(Int(resolvedWidth))
        windowHeightString = String(Int(resolvedHeight))
        playbackController.updateWindowSize(CGSize(width: resolvedWidth, height: resolvedHeight))

        scheduleWindowSizeUpdate(immediate: true)
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
            let configuration = WebRequestServer.Configuration(
                port: port,
                validator: validator,
                bonjour: makeBonjourConfiguration(port: port)
            )
            try await server.restart(with: configuration)
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

private func makeBonjourConfiguration(port: UInt16) -> WebRequestServer.Configuration.BonjourConfiguration {
    let hostName = Host.current().localizedName ?? "Intercom Blaster"
    hostAddress = NetworkAddressResolver.primaryHostIdentifier()
    let txtRecord = NetService.data(fromTXTRecord: [
        "path": Data("/play".utf8),
        "proto": Data("http".utf8)
    ])
    return .init(
        name: hostName,
        type: "_intercomblaster._tcp",
        domain: nil,
        txtRecord: txtRecord
    )
}

private func scheduleWindowSizeUpdate(immediate: Bool = false) {
    windowSizeTask?.cancel()
    windowSizeTask = Task { [weak self] in
        guard let self else { return }
        if !immediate {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        await self.applyWindowSize()
    }
}

@MainActor
private func applyWindowSize() {
    let defaults = UserDefaults.standard
    guard let width = Double(windowWidthString), let height = Double(windowHeightString) else {
        windowSizeError = "Width and height must be numeric."
        return
    }
    guard (200...1600).contains(width), (200...1600).contains(height) else {
        windowSizeError = "Values must be between 200 and 1600."
        return
    }

    windowSizeError = nil
  defaults.set(width, forKey: DefaultsKey.windowWidth)
  defaults.set(height, forKey: DefaultsKey.windowHeight)
    playbackController.updateWindowSize(CGSize(width: width, height: height))
}
}
