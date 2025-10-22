import Foundation

public struct VideoURLValidator: Sendable {
    public enum ValidationError: Error, Equatable {
        case invalidPattern(String)
        case noMatch
        case invalidURL(String)

        public static func == (lhs: ValidationError, rhs: ValidationError) -> Bool {
            switch (lhs, rhs) {
            case let (.invalidPattern(a), .invalidPattern(b)):
                return a == b
            case (.noMatch, .noMatch):
                return true
            case let (.invalidURL(a), .invalidURL(b)):
                return a == b
            default:
                return false
            }
        }
    }

    public let pattern: String

    public init(pattern: String) {
        self.pattern = pattern
    }

    public func isPatternValid() -> Bool {
        (try? Regex(pattern)) != nil
    }

    public func compiledRegex() throws -> Regex<AnyRegexOutput> {
        do {
            return try Regex(pattern)
        } catch {
            throw ValidationError.invalidPattern(error.localizedDescription)
        }
    }

    public func validate(body: String) -> Result<URL, ValidationError> {
        let regex: Regex<AnyRegexOutput>
        do {
            regex = try compiledRegex()
        } catch let ValidationError.invalidPattern(message) {
            return .failure(.invalidPattern(message))
        } catch {
            return .failure(.invalidPattern(error.localizedDescription))
        }

        guard let match = body.firstMatch(of: regex) else {
            return .failure(.noMatch)
        }

        let matchText = String(body[match.range])

        guard let url = URL(string: matchText) else {
            return .failure(.invalidURL(matchText))
        }

        guard let scheme = url.scheme, !scheme.isEmpty else {
            return .failure(.invalidURL(matchText))
        }

        return .success(url)
    }
}
