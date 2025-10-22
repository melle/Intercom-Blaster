import Testing
@testable import IntercomBlasterCore

@Suite("HTTPRequestParser")
struct HTTPRequestParserTests {
    @Test("Parses request head successfully")
    func parsesRequestHead() throws {
        let raw = "POST /play HTTP/1.1\r\nHost: localhost\r\nContent-Length: 10\r\n\r\n"
        let head = try HTTPRequestParser.parseHead(from: raw)
        #expect(head.method == "POST")
        #expect(head.path == "/play")
        #expect(head.value(forHeader: "host") == "localhost")
        #expect(head.value(forHeader: "content-length") == "10")
    }

    @Test("Throws for malformed request line")
    func throwsForMalformedRequestLine() {
        let raw = "POST\r\n\r\n"
        #expect(throws: HTTPRequestParseError.invalidRequestLine("POST")) {
            try HTTPRequestParser.parseHead(from: raw)
        }
    }

    @Test("Throws for malformed header")
    func throwsForMalformedHeader() {
        let raw = "POST /play HTTP/1.1\r\nContent-Length 10\r\n\r\n"
        #expect(throws: HTTPRequestParseError.malformedHeader("Content-Length 10")) {
            try HTTPRequestParser.parseHead(from: raw)
        }
    }
}
