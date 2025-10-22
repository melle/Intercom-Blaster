import Testing
@testable import DingDongBlasterCore

@Suite("VideoURLValidator")
struct VideoURLValidatorTests {
    @Test("Accepts when regex matches valid URL")
    func acceptsValidMatch() throws {
        let validator = VideoURLValidator(pattern: #"(https?|rtsp)://[\w\.-]+/stream"#)
        let body = "https://example.com/stream"
        let result = validator.validate(body: body)
        #expect(try result.get().absoluteString == body)
    }

    @Test("Accepts RTSP URL when pattern includes RTSP")
    func acceptsRTSPURL() throws {
        let validator = VideoURLValidator(pattern: #"(https?|rtsp)://[\w\.-]+/stream"#)
        let body = "rtsp://example.com/stream"
        let result = validator.validate(body: body)
        #expect(try result.get().absoluteString == body)
    }

    @Test("Rejects when regex does not match")
    func rejectsWhenNoMatch() {
        let validator = VideoURLValidator(pattern: #"https?://[\w\.-]+/stream"#)
        let result = validator.validate(body: "rtsp://example.com/stream")
        switch result {
        case .failure(.noMatch):
            break
        default:
            Issue.record("Expected noMatch failure")
        }
    }

    @Test("Detects invalid regex pattern")
    func detectsInvalidPattern() {
        let validator = VideoURLValidator(pattern: #"("#)
        let result = validator.validate(body: "https://example.com/video")
        switch result {
        case .failure(.invalidPattern):
            break
        default:
            Issue.record("Expected invalid pattern failure")
        }
    }

    @Test("Rejects when match is not a valid URL")
    func rejectsInvalidURLMatch() {
        let validator = VideoURLValidator(pattern: #"foo"#)
        let result = validator.validate(body: "foo")
        switch result {
        case .failure(.invalidURL("foo")):
            break
        default:
            Issue.record("Expected invalidURL failure")
        }
    }
}
