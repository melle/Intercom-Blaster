import Foundation

public struct HTTPRequestHead: Sendable {
    public let method: String
    public let path: String
    private let headerStorage: [String: String]

    public init(method: String, path: String, headers: [String: String]) {
        self.method = method
        self.path = path
        self.headerStorage = headers.reduce(into: [:]) { partialResult, pair in
            partialResult[pair.key.lowercased()] = pair.value
        }
    }

    public func value(forHeader name: String) -> String? {
        headerStorage[name.lowercased()]
    }
}

public enum HTTPRequestParseError: Error, LocalizedError, Equatable {
    case emptyRequestLine
    case invalidRequestLine(String)
    case malformedHeader(String)

    public var errorDescription: String? {
        switch self {
        case .emptyRequestLine:
            return "Request line is empty."
        case let .invalidRequestLine(line):
            return "Invalid request line: \(line)"
        case let .malformedHeader(line):
            return "Malformed header: \(line)"
        }
    }
}

public enum HTTPRequestParser {
    public static func parseHead(from raw: String) throws -> HTTPRequestHead {
        var lines = raw.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            throw HTTPRequestParseError.emptyRequestLine
        }

        let components = requestLine.split(separator: " ")
        guard components.count >= 2 else {
            throw HTTPRequestParseError.invalidRequestLine(String(requestLine))
        }

        let method = String(components[0])
        let path = String(components[1])
        lines.removeFirst()

        var headers: [String: String] = [:]

        for line in lines where !line.isEmpty {
            guard let separatorIndex = line.firstIndex(of: ":") else {
                throw HTTPRequestParseError.malformedHeader(String(line))
            }
            let name = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            let valueStart = line.index(after: separatorIndex)
            let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        return HTTPRequestHead(method: method, path: path, headers: headers)
    }
}
