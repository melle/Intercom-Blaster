import Foundation

struct ServerConfigurationValidator {
    enum PortValidationError: Error, Equatable {
        case notANumber
        case outOfRange
    }

    static func normalizePort(_ text: String) -> Result<UInt16, PortValidationError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let intValue = UInt32(trimmed) else {
            return .failure(.notANumber)
        }
        guard (1...UInt32(UInt16.max)).contains(intValue) else {
            return .failure(.outOfRange)
        }
        return .success(UInt16(intValue))
    }
}
