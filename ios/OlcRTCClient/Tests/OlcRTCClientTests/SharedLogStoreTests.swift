import XCTest

/// Exercises `SharedLogStore` through its test-friendly
/// `init(fileURL:byteCap:)` constructor. Uses a small `byteCap` (512
/// bytes) so the truncation path is reachable without writing
/// thousands of lines. Each test pins the store to a fresh URL under
/// `FileManager.default.temporaryDirectory` and cleans up in
/// `tearDown`.
final class SharedLogStoreTests: XCTestCase {
    private var fileURL: URL!
    private let byteCap = 512

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedLogStoreTests-\(UUID().uuidString).log")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        fileURL = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_readAllReturnsEmpty_whenFileMissing() {
        let store = SharedLogStore(fileURL: fileURL, byteCap: byteCap)
        XCTAssertEqual(store.readAll(), [])
    }

    func test_appendThenReadAll_preservesOrder() {
        let store = SharedLogStore(fileURL: fileURL, byteCap: byteCap)
        store.append("alpha")
        store.append("beta")
        store.append("gamma")
        XCTAssertEqual(store.readAll(), ["alpha", "beta", "gamma"])
    }

    func test_appendAddsTrailingNewline_whenMissing() throws {
        let store = SharedLogStore(fileURL: fileURL, byteCap: byteCap)
        store.append("no newline here")
        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(raw.hasSuffix("\n"))
    }

    func test_appendPreservesNewline_whenAlreadyPresent() throws {
        let store = SharedLogStore(fileURL: fileURL, byteCap: byteCap)
        store.append("already terminated\n")
        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        // Only one newline at the end — append must not double it.
        XCTAssertEqual(raw, "already terminated\n")
    }

    func test_clearRemovesFile_andReadAllReturnsEmpty() throws {
        let store = SharedLogStore(fileURL: fileURL, byteCap: byteCap)
        store.append("present")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(store.clear())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(store.readAll(), [])
    }

    func test_clearReturnsFalse_whenFileMissing() {
        let store = SharedLogStore(fileURL: fileURL, byteCap: byteCap)
        XCTAssertFalse(store.clear())
    }

    func test_truncatesFromHead_whenFileExceedsByteCap() throws {
        let store = SharedLogStore(fileURL: fileURL, byteCap: byteCap)
        // Each line is ~50 bytes including the trailing newline. 30
        // lines = ~1500 bytes, well over the 512-byte cap. After the
        // 30th append the file should be bounded near byteCap/2 (256)
        // and contain only the most recent lines.
        for i in 0..<30 {
            store.append("line-\(String(format: "%03d", i)) padding-padding-padding")
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = attrs[.size] as! Int
        XCTAssertLessThanOrEqual(size, byteCap,
            "file size \(size) should be bounded by byteCap=\(byteCap) after head-truncation")

        let lines = store.readAll()
        // The newest line must always survive.
        XCTAssertEqual(lines.last, "line-029 padding-padding-padding")
        // The oldest few lines must be gone (otherwise the cap was
        // never enforced).
        XCTAssertFalse(lines.contains("line-000 padding-padding-padding"))
        XCTAssertFalse(lines.contains("line-001 padding-padding-padding"))
        // Order is preserved among surviving lines.
        for (i, line) in lines.enumerated().dropFirst() {
            let prevNumber = Int(lines[i - 1].split(separator: " ")[0]
                                   .replacingOccurrences(of: "line-", with: "")) ?? -1
            let thisNumber = Int(line.split(separator: " ")[0]
                                   .replacingOccurrences(of: "line-", with: "")) ?? -2
            XCTAssertLessThan(prevNumber, thisNumber,
                "lines must remain in append order after truncation")
        }
    }

    func test_truncatedFileStartsAtLineBoundary() throws {
        // After head-truncation the file must not begin mid-line —
        // otherwise the first surviving "line" is a fragment of the
        // last evicted one. The truncation routine aligns to the
        // newline after the slice point.
        let store = SharedLogStore(fileURL: fileURL, byteCap: byteCap)
        for i in 0..<40 {
            store.append("entry-\(i) some text some text some text")
        }
        let lines = store.readAll()
        XCTAssertFalse(lines.isEmpty)
        // Every surviving line should start with "entry-" — if the
        // truncation cut mid-line, the first line would start with
        // arbitrary bytes from the middle of some earlier "entry-N".
        for line in lines {
            XCTAssertTrue(
                line.hasPrefix("entry-"),
                "line '\(line)' does not start at a line boundary"
            )
        }
    }
}
