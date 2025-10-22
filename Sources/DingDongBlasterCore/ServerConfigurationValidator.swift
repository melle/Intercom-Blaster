import Foundation

public struct ServerConfigurationValidator {
    public enum PortValidationError: Error, Equatable {
        case notANumber
        case outOfRange
    }

    public static func normalizePort(_ text: String) -> Result<UInt16, PortValidationError> {
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
