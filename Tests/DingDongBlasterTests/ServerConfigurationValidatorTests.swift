import Testing
@testable import DingDongBlaster

@Suite("Port validation")
struct ServerConfigurationValidatorTests {
    @Test("Parses valid port")
    func parsesValidPort() {
        let result = ServerConfigurationValidator.normalizePort(" 8080 ")
        switch result {
        case .success(let value):
            #expect(value == 8080)
        default:
            Issue.record("Expected port to parse")
        }
    }

    @Test("Rejects non-numeric input")
    func rejectsNonNumericPort() {
        let result = ServerConfigurationValidator.normalizePort("abc")
        switch result {
        case .failure(.notANumber):
            break
        default:
            Issue.record("Expected notANumber failure")
        }
    }

    @Test("Rejects out-of-range values")
    func rejectsOutOfRangePort() {
        let result = ServerConfigurationValidator.normalizePort("70000")
        switch result {
        case .failure(.outOfRange):
            break
        default:
            Issue.record("Expected outOfRange failure")
        }
    }
}
