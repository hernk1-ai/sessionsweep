import XCTest
@testable import SessionSweep

final class AudioSystemDataClassifierTests: XCTestCase {
    func testClassifiesPluginFormatsAsEssentialPlugins() {
        let vst3 = AudioSystemDataClassifier.classify(path: "/Library/Audio/Plug-Ins/VST3", size: 47)
        XCTAssertEqual(vst3?.category, .plugins)
        XCTAssertEqual(vst3?.safetyStatus, .essential)
        XCTAssertEqual(vst3?.friendlyName, "VST3 Plug-Ins")

        let au = AudioSystemDataClassifier.classify(path: "/Library/Audio/Plug-Ins/Components", size: 12)
        XCTAssertEqual(au?.category, .plugins)
        XCTAssertEqual(au?.friendlyName, "Audio Units")
    }

    func testClassifiesPresetVendorsAsEssentialPresets() {
        let refx = AudioSystemDataClassifier.classify(path: "/Library/Audio/Presets/reFX", size: 30)

        XCTAssertEqual(refx?.category, .presets)
        XCTAssertEqual(refx?.safetyStatus, .essential)
        XCTAssertEqual(refx?.friendlyName, "reFX Presets")
    }

    func testClassifiesImpulseResponsesAsEssentialAssets() {
        let slate = AudioSystemDataClassifier.classify(
            path: "/Library/Audio/Impulse Responses/Slate Digital",
            size: 7
        )

        XCTAssertEqual(slate?.category, .impulseResponses)
        XCTAssertEqual(slate?.safetyStatus, .essential)
        XCTAssertEqual(slate?.friendlyName, "Slate Digital Impulse Responses")
    }

    func testClassifiesKnownApplicationSupportVendorsAsEssentialContent() {
        let izotope = AudioSystemDataClassifier.classify(path: "/Library/Application Support/iZotope", size: 18)

        XCTAssertEqual(izotope?.category, .pluginContent)
        XCTAssertEqual(izotope?.safetyStatus, .essential)
        XCTAssertEqual(izotope?.friendlyName, "iZotope Application Support")
    }

    func testClassifiesKnownDownloadAndCacheFoldersAsLikelyCache() {
        let waves = AudioSystemDataClassifier.classify(
            path: "/Users/kris/Library/Caches/Waves Audio",
            size: 5
        )
        XCTAssertEqual(waves?.category, .cachesDownloads)
        XCTAssertEqual(waves?.safetyStatus, .likelyCache)

        let ableton = AudioSystemDataClassifier.classify(
            path: "/Users/kris/Library/Caches/Ableton/PackDownloads",
            size: 4
        )
        XCTAssertEqual(ableton?.category, .cachesDownloads)
        XCTAssertEqual(ableton?.safetyStatus, .likelyCache)

        let splice = AudioSystemDataClassifier.classify(
            path: "/Users/kris/Library/Application Support/com.splice.Splice/downloads",
            size: 3
        )
        XCTAssertEqual(splice?.category, .cachesDownloads)
        XCTAssertEqual(splice?.safetyStatus, .likelyCache)
    }

    func testSummaryDoesNotDoubleCountParentAudioFolders() {
        let summary = AudioSystemDataClassifier.summarize(folderSizes: [
            "/Library/Audio": 85,
            "/Library/Audio/Plug-Ins": 47,
            "/Library/Audio/Plug-Ins/VST3": 47,
            "/Library/Audio/Presets": 30,
            "/Library/Audio/Presets/reFX": 29,
            "/Library/Audio/Impulse Responses": 7,
            "/Library/Audio/Impulse Responses/Apple": 7,
            "/Library/Application Support/iZotope": 18,
            "/Users/kris/Library/Caches/Waves Audio": 5,
        ])

        XCTAssertEqual(summary.categoryTotals[.plugins], 47)
        XCTAssertEqual(summary.categoryTotals[.presets], 29)
        XCTAssertEqual(summary.categoryTotals[.impulseResponses], 7)
        XCTAssertEqual(summary.categoryTotals[.pluginContent], 18)
        XCTAssertEqual(summary.categoryTotals[.cachesDownloads], 5)
        XCTAssertEqual(summary.totalSize, 106)
    }

    func testSummaryPrefersSpecificCachePathOverOverlappingApplicationSupportParent() {
        let summary = AudioSystemDataClassifier.summarize(folderSizes: [
            "/Library/Application Support/Adobe": 20,
            "/Library/Application Support/Adobe/downloads": 6,
        ])

        XCTAssertNil(summary.categoryTotals[.pluginContent])
        XCTAssertEqual(summary.categoryTotals[.cachesDownloads], 6)
        XCTAssertEqual(summary.totalSize, 6)
    }
}
