import XCTest
@testable import SessionSweep

final class KeepSafeProtectionTests: XCTestCase {
    func testProtectionRefreshReusesScanDerivedStorageExplorerDataAndUpdatesTotals() {
        let duplicatePath = "/Users/test/Downloads/original copy.wav"
        let installerPath = "/Users/test/Downloads/Example.dmg"
        let result = makeScanResult(duplicatePath: duplicatePath, installerPath: installerPath)
        let protectedItems = [
            makeKeepSafeItem(path: duplicatePath, size: 1_500_000, category: "Duplicate File"),
            makeKeepSafeItem(path: installerPath, size: 20_000_000, category: "Installers"),
        ]

        let snapshots = ResultsProtectionProjectionTestHarness.refreshedSnapshot(
            result: result,
            initialKeepSafeItems: [],
            refreshedKeepSafeItems: protectedItems
        )

        XCTAssertEqual(snapshots.before.duplicateActionableTotal, 1_500_000)
        XCTAssertEqual(snapshots.before.installerActionableTotal, 20_000_000)
        XCTAssertEqual(snapshots.after.duplicateActionableTotal, 0)
        XCTAssertEqual(snapshots.after.installerActionableTotal, 0)
        XCTAssertEqual(snapshots.after.protectedItemCount, 2)
        XCTAssertEqual(snapshots.before.scanDataObjectID, snapshots.after.scanDataObjectID)
        XCTAssertEqual(snapshots.before.scanReuseToken, snapshots.after.scanReuseToken)
        XCTAssertEqual(snapshots.before.storageExplorerRootNodeIDs, snapshots.after.storageExplorerRootNodeIDs)
    }

    func testProtectionRefreshKeepsRowIdentityStable() {
        let duplicatePath = "/Users/test/Downloads/original copy.wav"
        let installerPath = "/Users/test/Downloads/Example.dmg"
        let result = makeScanResult(duplicatePath: duplicatePath, installerPath: installerPath)
        let protectedItems = [
            makeKeepSafeItem(path: duplicatePath, size: 1_500_000, category: "Duplicate File"),
            makeKeepSafeItem(path: installerPath, size: 20_000_000, category: "Installers"),
        ]

        let snapshots = ResultsProtectionProjectionTestHarness.refreshedSnapshot(
            result: result,
            initialKeepSafeItems: [],
            refreshedKeepSafeItems: protectedItems
        )

        XCTAssertEqual(snapshots.before.duplicateGroupIDs, snapshots.after.duplicateGroupIDs)
        XCTAssertEqual(snapshots.before.duplicatePathIDs, snapshots.after.duplicatePathIDs)
        XCTAssertEqual(snapshots.before.installerRowIDs, snapshots.after.installerRowIDs)
    }

    @MainActor
    func testPathSelectionAccountingUpdatesIncrementallyAndPrunesAgainstStageablePaths() {
        let selection = PathSelectionState()
        selection.configure(
            stageablePaths: ["/a.wav", "/b.wav"],
            byteSizes: [
                "/a.wav": 10,
                "/b.wav": 30,
            ]
        )

        selection.insert("/a.wav")
        XCTAssertEqual(selection.selectedPaths, ["/a.wav"])
        XCTAssertEqual(selection.selectedCount, 1)
        XCTAssertEqual(selection.selectedBytes, 10)

        selection.insert("/b.wav")
        XCTAssertEqual(selection.selectedCount, 2)
        XCTAssertEqual(selection.selectedBytes, 40)

        selection.remove("/a.wav")
        XCTAssertEqual(selection.selectedPaths, ["/b.wav"])
        XCTAssertEqual(selection.selectedCount, 1)
        XCTAssertEqual(selection.selectedBytes, 30)

        selection.setSelection(
            ["/a.wav", "/b.wav"],
            blockedPathKeys: [KeepSafeStore.standardizedPath("/b.wav")]
        )
        XCTAssertEqual(selection.selectedPaths, ["/a.wav"])
        XCTAssertEqual(selection.selectedBytes, 10)

        selection.configure(
            stageablePaths: ["/b.wav"],
            byteSizes: ["/b.wav": 30]
        )
        XCTAssertTrue(selection.selectedPaths.isEmpty)
        XCTAssertEqual(selection.selectedCount, 0)
        XCTAssertEqual(selection.selectedBytes, 0)
    }

    func testRecommendationOutputUpdatesAfterKeepSafeChange() {
        let duplicatePath = "/Users/test/Downloads/original copy.wav"
        let installerPath = "/Users/test/Downloads/Example.dmg"
        let result = makeScanResult(duplicatePath: duplicatePath, installerPath: installerPath)
        let protectedItems = [
            makeKeepSafeItem(path: duplicatePath, size: 1_500_000, category: "Duplicate File"),
            makeKeepSafeItem(path: installerPath, size: 20_000_000, category: "Installers"),
        ]

        let snapshots = ResultsProtectionProjectionTestHarness.refreshedSnapshot(
            result: result,
            initialKeepSafeItems: [],
            refreshedKeepSafeItems: protectedItems
        )

        XCTAssertTrue(snapshots.before.recommendationKinds.contains(.safeCleanup))
        XCTAssertFalse(snapshots.before.recommendationKinds.contains(.keepSafe))
        XCTAssertFalse(snapshots.after.recommendationKinds.contains(.safeCleanup))
        XCTAssertTrue(snapshots.after.recommendationKinds.contains(.keepSafe))
    }

    func testKeepSafeStoreMatchesExactAndDescendantFolderProtection() throws {
        let store = KeepSafeStore(fileURL: temporaryKeepSafeURL())

        try store.addPersisting(
            path: "/Users/test/Sessions",
            itemType: .folder,
            size: 0,
            classification: "Session folder",
            category: "Projects"
        )
        try store.addPersisting(
            path: "/Users/test/Downloads/Example.dmg",
            itemType: .file,
            size: 20_000_000,
            classification: "Installer",
            category: "Installers"
        )

        XCTAssertTrue(store.isProtected("/Users/test/Sessions"))
        XCTAssertTrue(store.isProtected("/Users/test/Sessions/Song/Audio Files/kick.wav"))
        XCTAssertTrue(store.isProtected("/Users/test/Downloads/Example.dmg"))
        XCTAssertFalse(store.isProtected("/Users/test/Downloads/Other.dmg"))
    }

    func testFailedKeepSafePersistenceRollsBackVisibleItems() throws {
        let parentFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionSweep-KeepSafe-Failure-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: parentFileURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: parentFileURL) }
        let store = KeepSafeStore(fileURL: parentFileURL.appendingPathComponent("KeepSafeItems.json"))

        XCTAssertThrowsError(try store.addPersisting(
            path: "/Users/test/Downloads/Example.dmg",
            itemType: .file,
            size: 20_000_000,
            classification: "Installer",
            category: "Installers"
        ))
        XCTAssertTrue(store.items.isEmpty)
    }

    private func makeScanResult(duplicatePath: String, installerPath: String) -> ScanResult {
        var result = ScanResult()
        result.totalSize = 121_500_000
        result.fileCount = 3
        result.rootPath = "/Users/test"
        result.categoryTotals = [
            .audioFiles: 3_000_000,
            .installers: 20_000_000,
            .other: 98_500_000,
        ]
        result.folderSizes = [
            "/Users/test": 121_500_000,
            "/Users/test/Downloads": 21_500_000,
            "/Users/test/Music": 1_500_000,
        ]
        result.folderChildren = [
            "/Users/test": [
                "/Users/test/Downloads",
                "/Users/test/Music",
            ],
        ]
        result.duplicateGroups = [
            DuplicateGroup(
                fileSize: 1_500_000,
                paths: [
                    "/Users/test/Music/original.wav",
                    duplicatePath,
                ],
                sameName: true
            ),
        ]
        result.installerFiles = [
            SizedItem(
                url: URL(fileURLWithPath: installerPath),
                size: 20_000_000,
                category: .installers
            ),
        ]
        return result
    }

    private func makeKeepSafeItem(
        path: String,
        size: Int64,
        category: String
    ) -> KeepSafeItem {
        KeepSafeItem(
            id: UUID(),
            originalPath: path,
            resolvedPath: path,
            displayName: URL(fileURLWithPath: path).lastPathComponent,
            itemType: .file,
            sizeAtProtection: size,
            dateProtected: Date(timeIntervalSinceReferenceDate: 1),
            lastSeenDate: nil,
            lastKnownExists: false,
            sourceVolumeIdentifier: nil,
            bookmarkData: nil,
            classification: category,
            category: category,
            note: nil
        )
    }

    private func temporaryKeepSafeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionSweep-KeepSafe-\(UUID().uuidString)")
            .appendingPathComponent("KeepSafeItems.json")
    }
}
