import XCTest
@testable import DualtapCore

final class OutputPathTests: XCTestCase {
    func testDefaultWhenNil() {
        XCTAssertEqual(
            resolveOutputPath(userOutput: nil, timestamp: "20260708_180513", ext: "m4a", cwd: "/tmp"),
            "/tmp/dualtap-20260708_180513.m4a")
    }

    func testAppendsExtWhenMissing() {
        XCTAssertEqual(
            resolveOutputPath(userOutput: "/inbox/20260708_180513", timestamp: "x", ext: "m4a", cwd: "/tmp"),
            "/inbox/20260708_180513.m4a")
    }

    func testKeepsExistingExt() {
        XCTAssertEqual(
            resolveOutputPath(userOutput: "/inbox/rec.m4a", timestamp: "x", ext: "m4a", cwd: "/tmp"),
            "/inbox/rec.m4a")
        XCTAssertEqual(
            resolveOutputPath(userOutput: "/inbox/rec.wav", timestamp: "x", ext: "m4a", cwd: "/tmp"),
            "/inbox/rec.wav")
    }

    func testDirWithDotButFileWithoutExt() {
        XCTAssertEqual(
            resolveOutputPath(userOutput: "/a.b/20260708_180513", timestamp: "x", ext: "m4a", cwd: "/tmp"),
            "/a.b/20260708_180513.m4a")
    }
}
