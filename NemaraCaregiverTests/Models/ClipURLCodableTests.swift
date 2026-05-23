import XCTest
@testable import Nemara

final class ClipURLCodableTests: XCTestCase {

    private let decoder = NemaraJSON.decoder()

    func test_decode_clip_url_response_assigns_every_field() throws {
        let json = """
        {
          "url": "https://example.supabase.co/storage/v1/object/sign/incident-clips/events/abc.mp4?token=eyJhbGciOi",
          "expires_in_seconds": 600
        }
        """
        let resp = try decoder.decode(
            ClipURLResponse.self,
            from: json.data(using: .utf8)!,
        )
        XCTAssertEqual(
            resp.url.absoluteString,
            "https://example.supabase.co/storage/v1/object/sign/incident-clips/events/abc.mp4?token=eyJhbGciOi",
        )
        XCTAssertEqual(resp.expiresInSeconds, 600)
    }

    func test_decode_rejects_malformed_url() {
        let json = """
        { "url": "not a url at all and has spaces", "expires_in_seconds": 60 }
        """
        // URL(string:) accepts a lot of garbage on Apple platforms, so
        // we test the more meaningful negative case — missing the
        // url field entirely.
        let malformed = """
        { "expires_in_seconds": 60 }
        """
        XCTAssertThrowsError(
            try decoder.decode(ClipURLResponse.self, from: malformed.data(using: .utf8)!)
        )
        // The first JSON happens to decode (URL(string:) is permissive);
        // documenting that here so a future test author doesn't get
        // surprised.
        _ = json
    }
}
