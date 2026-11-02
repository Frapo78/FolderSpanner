import XCTest
@testable import FolderSpannerCore

final class SpanPlannerTests: XCTestCase {
    private var sandbox: URL!
    private var source: URL!
    private var destination: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        source = sandbox.appendingPathComponent("source", isDirectory: true)
        destination = sandbox.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let sandbox { try? FileManager.default.removeItem(at: sandbox) }
    }

    private func add(_ name: String, bytes: Int) throws {
        try Data(repeating: 1, count: bytes).write(to: source.appendingPathComponent(name))
    }

    func testAlphabeticalBatchesStartAtTwo() throws {
        for name in ["e.adf", "c.adf", "a.adf", "b.adf", "d.adf"] { try add(name, bytes: 10) }
        let plan = try SpanPlanner.plan(SpanOptions(source: source, destinationRoot: destination,
                                                    maximumFiles: 2, startingIndex: 2))
        XCTAssertEqual(plan.files.map(\.source.lastPathComponent), ["a.adf", "b.adf", "c.adf", "d.adf", "e.adf"])
        XCTAssertEqual(plan.folders.map(\.name), ["2", "3", "4"])
        XCTAssertEqual(plan.folders.map(\.newFileCount), [2, 2, 1])
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("2").path))
    }

    func testResumeMoveFillsPartiallyCompletedBatch() throws {
        for name in ["a", "b", "c", "d"] { try add(name, bytes: 10) }
        let options = SpanOptions(source: source, destinationRoot: destination, maximumFiles: 2)
        let first = try SpanPlanner.plan(options)
        try SpanExecutor.transfer(first.files[0], mode: .move)
        let resumed = try SpanPlanner.plan(options)
        XCTAssertEqual(resumed.files.count, 3)
        XCTAssertEqual(resumed.folders.first?.existingFileCount, 1)
        XCTAssertEqual(resumed.files[0].destination.deletingLastPathComponent().lastPathComponent, "1")
    }

    func testCombinedFileAndSizeLimits() throws {
        try add("a", bytes: 6)
        try add("b", bytes: 6)
        try add("c", bytes: 6)
        let plan = try SpanPlanner.plan(SpanOptions(source: source, destinationRoot: destination,
                                                    maximumFiles: 5, maximumBytes: 10, folderPattern: "Batch_{n:03}"))
        XCTAssertEqual(plan.folders.map(\.name), ["Batch_001", "Batch_002", "Batch_003"])
    }

    func testNoOverwriteIfDestinationContainsDuplicate() throws {
        try add("same.adf", bytes: 10)
        let targetFolder = destination.appendingPathComponent("1")
        try FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)
        try Data(repeating: 2, count: 10).write(to: targetFolder.appendingPathComponent("same.adf"))
        XCTAssertThrowsError(try SpanPlanner.plan(SpanOptions(source: source, destinationRoot: destination)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("same.adf").path))
    }

    func testRejectsNestedTargetAndOversizedFile() throws {
        let nested = source.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        XCTAssertThrowsError(try SpanPlanner.plan(SpanOptions(source: source, destinationRoot: nested)))
        try add("big", bytes: 20)
        XCTAssertThrowsError(try SpanPlanner.plan(SpanOptions(source: source, destinationRoot: destination,
                                                               maximumFiles: 0, maximumBytes: 10)))
    }

    func testCopyKeepsOriginal() throws {
        try add("a.adf", bytes: 12)
        let plan = try SpanPlanner.plan(SpanOptions(source: source, destinationRoot: destination))
        try SpanExecutor.transfer(plan.files[0], mode: .copy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("a.adf").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("1/a.adf").path))
    }

    func testHiddenFilesSkippedByDefault() throws {
        try add(".DS_Store", bytes: 3)
        try add("visible", bytes: 3)
        let options = SpanOptions(source: source, destinationRoot: destination)
        XCTAssertEqual(try SpanPlanner.plan(options).files.count, 1)
        var all = options
        all.includeHidden = true
        XCTAssertEqual(try SpanPlanner.plan(all).files.count, 2)
    }

    func testFiveHundredFifteenFilesCreateThreeBatches() throws {
        for index in 0..<515 { try add(String(format: "game_%04d.adf", index), bytes: 1) }
        let plan = try SpanPlanner.plan(SpanOptions(source: source, destinationRoot: destination,
                                                    maximumFiles: 200, startingIndex: 2))
        XCTAssertEqual(plan.folders.map(\.name), ["2", "3", "4"])
        XCTAssertEqual(plan.folders.map(\.newFileCount), [200, 200, 115])
    }

    func testFileModifiedAfterPreviewCannotBeTransferred() throws {
        try add("a.adf", bytes: 4)
        let plan = try SpanPlanner.plan(SpanOptions(source: source, destinationRoot: destination))
        try add("a.adf", bytes: 8)
        XCTAssertThrowsError(try SpanExecutor.transfer(plan.files[0], mode: .move))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("a.adf").path))
    }

    func testRecursiveModeRejectsDuplicateNamesInSameBatch() throws {
        let nested = source.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try add("same.adf", bytes: 2)
        try Data(repeating: 2, count: 2).write(to: nested.appendingPathComponent("same.adf"))
        let flat = SpanOptions(source: source, destinationRoot: destination)
        XCTAssertEqual(try SpanPlanner.plan(flat).files.count, 1)
        var recursive = flat
        recursive.recursive = true
        XCTAssertThrowsError(try SpanPlanner.plan(recursive))
    }

}
