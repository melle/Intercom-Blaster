import Foundation
import Network
import os
import IntercomBlasterCore

actor WebRequestServer {
    struct Configuration: Sendable {
        let port: UInt16
        let validator: VideoURLValidator
        let bonjour: BonjourConfiguration?

        struct BonjourConfiguration: Sendable {
            let name: String?
            let type: String
            let domain: String?
            let txtRecord: Data?
        }
    }

    private let urlHandler: @Sendable (URL) async -> Void
    private let queue = DispatchQueue(label: "com.intercomblaster.webserver")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var configuration: Configuration?
    private let logger = Logger(subsystem: "com.intercomblaster.app", category: "WebRequestServer")

    init(urlHandler: @escaping @Sendable (URL) async -> Void) {
        self.urlHandler = urlHandler
    }

    func restart(with configuration: Configuration) async throws {
        await stop()
        try await start(with: configuration)
    }

    func start(with configuration: Configuration) async throws {
        guard listener == nil else {
            try await restart(with: configuration)
            return
        }
        guard let nwPort = NWEndpoint.Port(rawValue: configuration.port) else {
            throw NSError(domain: "WebRequestServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid port"])
        }

        let listener = try NWListener(using: .tcp, on: nwPort)
        if let bonjour = configuration.bonjour {
            listener.service = NWListener.Service(
                name: bonjour.name,
                type: bonjour.type,
                domain: bonjour.domain,
                txtRecord: bonjour.txtRecord
            )
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task {
                await self.accept(connection: connection)
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task {
                await self.listenerStateDidChange(state)
            }
        }
        listener.start(queue: queue)

        self.listener = listener
        self.configuration = configuration
        logger.info("WebRequestServer listening on port \(nwPort.rawValue)")
    }

    func stop() async {
        if let listener {
            listener.cancel()
            listener.stateUpdateHandler = nil
            self.listener = nil
        }

        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
    }

    private func listenerStateDidChange(_ state: NWListener.State) {
        switch state {
        case .failed(let error):
            logger.error("Listener failed: \(error.localizedDescription, privacy: .public)")
        case .ready:
            logger.info("Listener ready")
        case .waiting(let error):
            logger.warning("Listener waiting: \(error.localizedDescription, privacy: .public)")
        case .cancelled:
            logger.info("Listener cancelled")
        default:
            break
        }
    }

    private func accept(connection: NWConnection) async {
        let identifier = ObjectIdentifier(connection)
        connections[identifier] = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task {
                await self.connection(connection, didUpdateState: state)
            }
        }
        connection.start(queue: queue)

        await processConnection(connection, identifier: identifier)
    }

    private func connection(_ connection: NWConnection, didUpdateState state: NWConnection.State) {
        if case let .failed(error) = state {
            logger.error("Connection failed: \(error.localizedDescription, privacy: .public)")
        }
        if case .cancelled = state {
            connections.removeValue(forKey: ObjectIdentifier(connection))
        }
    }

    private func processConnection(_ connection: NWConnection, identifier: ObjectIdentifier) async {
        defer {
            connection.cancel()
            connections.removeValue(forKey: identifier)
        }

        guard let configuration else {
            await sendResponse(connection, status: .internalServerError, body: "Server not configured.")
            return
        }

        do {
            let (head, body) = try await readRequest(from: connection)
            guard head.method.uppercased() == "POST" else {
                await sendResponse(connection, status: .methodNotAllowed, body: "Only POST supported.")
                return
            }
            guard head.path == "/play" else {
                await sendResponse(connection, status: .notFound, body: "Unknown endpoint.")
                return
            }

            guard let bodyString = String(data: body, encoding: .utf8) else {
                await sendResponse(connection, status: .badRequest, body: "Body must be UTF-8.")
                return
            }

            switch configuration.validator.validate(body: bodyString) {
            case .success(let url):
                logger.info("Accepted URL: \(url.absoluteString, privacy: .public)")
                await urlHandler(url)
                await sendResponse(connection, status: .ok, body: "Playback starting.")
            case .failure(let error):
                logger.error("Rejected request: \(self.errorMessage(error), privacy: .public)")
                await sendResponse(connection, status: .badRequest, body: self.rejectionMessage(for: error))
            }
        } catch {
            logger.error("Request handling error: \(error.localizedDescription, privacy: .public)")
            await sendResponse(connection, status: .badRequest, body: "Request error: \(error.localizedDescription)")
        }
    }

    private func errorMessage(_ error: VideoURLValidator.ValidationError) -> String {
        switch error {
        case .invalidPattern(let message):
            return "Invalid pattern \(message)"
        case .noMatch:
            return "No match"
        case .invalidURL(let urlString):
            return "Invalid URL \(urlString)"
        }
    }

    private func rejectionMessage(for error: VideoURLValidator.ValidationError) -> String {
        switch error {
        case .invalidPattern(let message):
            return "Invalid regex: \(message)"
        case .noMatch:
            return "No URL match."
        case .invalidURL:
            return "Matched text is not a valid URL."
        }
    }

    private func readRequest(from connection: NWConnection) async throws -> (HTTPRequestHead, Data) {
        let headerTerminator = Data("\r\n\r\n".utf8)
        var buffer = Data()

        while true {
            let (chunk, completed) = try await receiveChunk(from: connection)
            guard !chunk.isEmpty else {
                if completed {
                    throw RequestReadError.connectionClosed
                }
                continue
            }
            buffer.append(chunk)
            if let range = buffer.range(of: headerTerminator) {
                let headerData = buffer[..<range.lowerBound]
                guard let headerString = String(data: headerData, encoding: .utf8) else {
                    throw RequestReadError.invalidHeaderEncoding
                }
                let head = try HTTPRequestParser.parseHead(from: headerString)
                guard let contentLengthRaw = head.value(forHeader: "Content-Length") else {
                    throw RequestReadError.missingContentLength
                }
                guard let expectedLength = Int(contentLengthRaw), expectedLength >= 0 else {
                    throw RequestReadError.invalidContentLength
                }

                var body = Data(buffer[range.upperBound...])
                while body.count < expectedLength {
                    let (bodyChunk, bodyComplete) = try await receiveChunk(from: connection)
                    body.append(bodyChunk)
                    if bodyComplete && body.count < expectedLength {
                        throw RequestReadError.connectionClosed
                    }
                }
                if body.count > expectedLength {
                    body = body.prefix(expectedLength)
                }
                return (head, body)
            }

            if completed {
                throw RequestReadError.connectionClosed
            }
        }
    }

    private func receiveChunk(from connection: NWConnection) async throws -> (Data, Bool) {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (data ?? Data(), isComplete))
            }
        }
    }

    private func sendResponse(_ connection: NWConnection, status: HTTPStatus, body: String) async {
        let bodyData = Data(body.utf8)
        let header = [
            "HTTP/1.1 \(status.code) \(status.reason)",
            "Content-Length: \(bodyData.count)",
            "Content-Type: text/plain; charset=utf-8",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        var responseData = Data(header.utf8)
        responseData.append(bodyData)

        await withCheckedContinuation { continuation in
            connection.send(content: responseData, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }
}

private struct HTTPStatus {
    let code: Int
    let reason: String

    static let ok = HTTPStatus(code: 200, reason: "OK")
    static let badRequest = HTTPStatus(code: 400, reason: "Bad Request")
    static let notFound = HTTPStatus(code: 404, reason: "Not Found")
    static let methodNotAllowed = HTTPStatus(code: 405, reason: "Method Not Allowed")
    static let internalServerError = HTTPStatus(code: 500, reason: "Internal Server Error")
}

private enum RequestReadError: Error {
    case connectionClosed
    case invalidHeaderEncoding
    case missingContentLength
    case invalidContentLength
}
