import Foundation
import XCTest
@testable import FolderSpannerCore

final class SpanCatalogTests: XCTestCase {
    private var sandbox: URL!
    private var root: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        root = sandbox.appendingPathComponent("collection", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    private func add(_ path: String, bytes: Int) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 42, count: bytes).write(to: url)
    }

    func testFlatCatalogIsReadableAndDoesNotIncludeSubfolders() throws {
        try add("b.bin", bytes: 10)
        try add("a.bin", bytes: 4)
        try add("nested/c.bin", bytes: 8)
        let report = try SpanCatalog.generate(CatalogOptions(root: root, recursive: false))
        XCTAssertEqual(report.fileCount, 2)
        XCTAssertEqual(report.totalBytes, 14)
        XCTAssertEqual(report.folderCount, 1)
        let text = try String(contentsOf: report.url, encoding: .utf8)
        XCTAssertTrue(text.contains("| a.bin | a.bin | 4 |"))
        XCTAssertTrue(text.contains("| b.bin | b.bin | 10 |"))
        XCTAssertFalse(text.contains("nested/c.bin"))
        XCTAssertTrue(text.contains("- Total bytes: 14"))
    }

    func testRecursiveCatalogExcludesItselfAndEscapesPipes() throws {
        try add("other/a|b.bin", bytes: 7)
        try add("other/deeper/second.bin", bytes: 3)
        try add(".hidden.bin", bytes: 2)
        let once = try SpanCatalog.generate(CatalogOptions(root: root))
        XCTAssertEqual(once.fileCount, 2)
        XCTAssertEqual(once.folderCount, 2)
        let data = try String(contentsOf: once.url, encoding: .utf8)
        XCTAssertTrue(data.contains("other/a\\|b.bin"))
        XCTAssertTrue(data.contains("other/deeper/second.bin"))
        XCTAssertFalse(data.contains(".hidden.bin"))
        let twice = try SpanCatalog.generate(
            CatalogOptions(root: root, recursive: true, includeHidden: true,
                           overwriteExisting: true))
        XCTAssertEqual(twice.fileCount, 3)
        let next = try String(contentsOf: twice.url, encoding: .utf8)
        XCTAssertFalse(next.contains("| FolderSpanner-catalog.md |"))
        XCTAssertTrue(next.contains(".hidden.bin"))
    }

    func testExistingCatalogIsNotOverwrittenWithoutConsent() throws {
        let output = root.appendingPathComponent(SpanCatalog.fileName)
        try "old catalog".write(to: output, atomically: true, encoding: .utf8)
        try add("a.bin", bytes: 6)
        XCTAssertThrowsError(try SpanCatalog.generate(CatalogOptions(root: root)))
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "old catalog")
        let report = try SpanCatalog.generate(
            CatalogOptions(root: root, overwriteExisting: true))
        XCTAssertEqual(report.fileCount, 1)
        XCTAssertTrue(try String(contentsOf: output, encoding: .utf8).contains("a.bin"))
    }

    func testCancelledScanLeavesPreviousCatalogUntouchedAndRemovesTemp() throws {
        try add("a.bin", bytes: 1)
        let output = root.appendingPathComponent(SpanCatalog.fileName)
        try "keep".write(to: output, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try SpanCatalog.generate(
            CatalogOptions(root: root, overwriteExisting: true),
            shouldCancel: { true }
        )) { error in XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "keep")
        let contents = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertFalse(contents.contains { $0.hasPrefix(".FolderSpanner-catalog-") })
    }

    func testEmptyFolderCreatesValidSummary() throws {
        let report = try SpanCatalog.generate(CatalogOptions(root: root))
        XCTAssertEqual(report.fileCount, 0)
        XCTAssertEqual(report.totalBytes, 0)
        XCTAssertEqual(report.folderCount, 0)
        XCTAssertTrue(try String(contentsOf: report.url, encoding: .utf8)
            .contains("## Summary"))
    }
}
