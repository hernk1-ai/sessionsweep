import Foundation

enum AudioFolderGuidanceKind: String, Sendable {
    case pluginBinary = "Plugin Binary"
    case applicationSupport = "Application Support"
    case contentLibrary = "Content Library"
    case sampleLibrary = "Sample Library"
    case presetLibrary = "Preset Library"
    case impulseResponseLibrary = "Impulse Response Library"
    case cacheDownload = "Cache / Download"
    case unknownAudioFolder = "Unknown Audio Folder"
}

struct AudioFolderGuidance: Sendable {
    let kind: AudioFolderGuidanceKind
    let displayTitle: String
    let explanation: String
    let guidance: String
    let expectedToRemainInPlace: Bool
    let vendorRelocationMayBePossible: Bool
    let relocationSupport: RelocationSupport
    let vendorGuide: VendorGuide
}

enum AudioFolderGuidanceClassifier {
    static nonisolated func guidance(for item: AudioSystemDataItem) -> AudioFolderGuidance {
        let normalizedPath = URL(fileURLWithPath: item.path).standardizedFileURL.path
        let lowerPath = normalizedPath.lowercased()

        if isPluginBinary(item: item, lowerPath: lowerPath) {
            return guidance(
                .pluginBinary,
                item: item,
                explanation: "Installed plugin files used by your DAW.",
                guidance: "Leave in place. Moving these manually can prevent plugins from loading.",
                expectedToRemainInPlace: true,
                vendorRelocationMayBePossible: false,
                normalizedLowerPath: lowerPath
            )
        }

        if item.category == .cachesDownloads || containsAny(lowerPath, cacheDownloadMarkers) {
            return guidance(
                .cacheDownload,
                item: item,
                explanation: "Temporary or downloaded content created by audio software.",
                guidance: "May be reviewable, but SessionSweep should not recommend removal unless existing cleanup logic already classifies it as appropriate for cleanup.",
                expectedToRemainInPlace: false,
                vendorRelocationMayBePossible: true,
                normalizedLowerPath: lowerPath
            )
        }

        if item.category == .impulseResponses || containsAny(lowerPath, impulseResponseMarkers) {
            return guidance(
                .impulseResponseLibrary,
                item: item,
                explanation: "Impulse responses used by reverbs, cabinet simulators, and acoustic processors.",
                guidance: "May be relocatable if the plugin lets you choose a custom IR folder. Do not move it manually unless that workflow is documented.",
                expectedToRemainInPlace: false,
                vendorRelocationMayBePossible: true,
                normalizedLowerPath: lowerPath
            )
        }

        if isPresetContentLibrary(item: item, lowerPath: lowerPath)
            || isContentLibrary(lowerPath: lowerPath) {
            return contentLibraryGuidance(item: item, lowerPath: lowerPath)
        }

        if containsAny(lowerPath, sampleLibraryMarkers) {
            return guidance(
                .sampleLibrary,
                item: item,
                explanation: "Audio samples used by samplers, drum instruments, or production tools.",
                guidance: "Often movable to an external drive when the vendor supports choosing a library location. Avoid dragging it manually unless the vendor documents that workflow.",
                expectedToRemainInPlace: false,
                vendorRelocationMayBePossible: true,
                normalizedLowerPath: lowerPath
            )
        }

        if item.category == .presets || lowerPath.contains("/library/audio/presets/") {
            return guidance(
                .presetLibrary,
                item: item,
                explanation: "Preset and configuration files used by plugins or instruments.",
                guidance: "Usually best left in place. Some folders labeled as presets may also contain large samples or expansion content.",
                expectedToRemainInPlace: true,
                vendorRelocationMayBePossible: false,
                normalizedLowerPath: lowerPath
            )
        }

        if item.category == .pluginContent && lowerPath.contains("/application support/") {
            return guidance(
                .applicationSupport,
                item: item,
                explanation: "Support files, databases, presets, licensing data, and other resources used by installed audio software.",
                guidance: "Usually required. Do not move manually unless the software vendor provides an official relocation tool or library manager.",
                expectedToRemainInPlace: true,
                vendorRelocationMayBePossible: true,
                normalizedLowerPath: lowerPath
            )
        }

        return guidance(
            .unknownAudioFolder,
            item: item,
            explanation: "Audio-related storage that SessionSweep cannot confidently classify.",
            guidance: "Review in Finder and consult the software vendor before moving anything. SessionSweep cannot determine whether you still need this content.",
            expectedToRemainInPlace: true,
            vendorRelocationMayBePossible: false,
            normalizedLowerPath: lowerPath
        )
    }

    private static nonisolated func contentLibraryGuidance(
        item: AudioSystemDataItem,
        lowerPath: String
    ) -> AudioFolderGuidance {
        if lowerPath.contains("/library/audio/presets/refx") || lowerPath.contains("nexus") {
            return guidance(
                .contentLibrary,
                item: item,
                explanation: "This folder may include NEXUS presets, expansions, samples, and other sound content rather than only lightweight preset files.",
                guidance: "It may support relocation to an external drive through reFX tools or settings. Do not move it manually unless reFX documents that workflow.",
                expectedToRemainInPlace: false,
                vendorRelocationMayBePossible: true,
                normalizedLowerPath: lowerPath
            )
        }

        return guidance(
            .contentLibrary,
            item: item,
            explanation: "Large sounds, expansions, samples, or factory content used by an instrument or plugin.",
            guidance: "May support relocation to an external drive through the vendor's own application or settings. Do not drag it manually unless the vendor documents that workflow.",
            expectedToRemainInPlace: false,
            vendorRelocationMayBePossible: true,
            normalizedLowerPath: lowerPath
        )
    }

    private static nonisolated func isPluginBinary(
        item: AudioSystemDataItem,
        lowerPath: String
    ) -> Bool {
        item.category == .plugins
            || lowerPath.contains("/library/audio/plug-ins/")
            || pluginBinaryExtensions.contains {
                lowerPath.hasSuffix(".\($0)") || lowerPath.contains(".\($0)/")
            }
    }

    private static nonisolated func isPresetContentLibrary(
        item: AudioSystemDataItem,
        lowerPath: String
    ) -> Bool {
        guard item.category == .presets || lowerPath.contains("/library/audio/presets/") else {
            return false
        }

        return lowerPath.contains("/refx")
            || lowerPath.contains("nexus")
            || containsAny(lowerPath, contentLibraryMarkers)
    }

    private static nonisolated func isContentLibrary(lowerPath: String) -> Bool {
        containsAny(lowerPath, contentLibraryMarkers)
            || lowerPath.contains("/factory library")
            || lowerPath.contains("/factory sounds")
    }

    private static nonisolated func guidance(
        _ kind: AudioFolderGuidanceKind,
        item: AudioSystemDataItem,
        explanation: String,
        guidance: String,
        expectedToRemainInPlace: Bool,
        vendorRelocationMayBePossible: Bool
    ) -> AudioFolderGuidance {
        let normalizedPath = URL(fileURLWithPath: item.path).standardizedFileURL.path
        return Self.guidance(
            kind,
            item: item,
            explanation: explanation,
            guidance: guidance,
            expectedToRemainInPlace: expectedToRemainInPlace,
            vendorRelocationMayBePossible: vendorRelocationMayBePossible,
            normalizedLowerPath: normalizedPath.lowercased()
        )
    }

    private static nonisolated func guidance(
        _ kind: AudioFolderGuidanceKind,
        item: AudioSystemDataItem,
        explanation: String,
        guidance: String,
        expectedToRemainInPlace: Bool,
        vendorRelocationMayBePossible: Bool,
        normalizedLowerPath lowerPath: String
    ) -> AudioFolderGuidance {
        let vendorGuide = VendorRelocationAdvisor.guide(
            for: item,
            kind: kind,
            expectedToRemainInPlace: expectedToRemainInPlace,
            vendorRelocationMayBePossible: vendorRelocationMayBePossible,
            normalizedLowerPath: lowerPath
        )

        return AudioFolderGuidance(
            kind: kind,
            displayTitle: kind.rawValue,
            explanation: explanation,
            guidance: guidance,
            expectedToRemainInPlace: expectedToRemainInPlace,
            vendorRelocationMayBePossible: vendorRelocationMayBePossible,
            relocationSupport: vendorGuide.relocationSupport,
            vendorGuide: vendorGuide
        )
    }

    private static nonisolated func containsAny(_ path: String, _ markers: [String]) -> Bool {
        markers.contains { path.contains($0) }
    }

    private nonisolated static let pluginBinaryExtensions = [
        "vst3", "component", "vst", "au", "bundle", "plugin", "clap", "aaxplugin"
    ]

    private nonisolated static let contentLibraryMarkers = [
        "/content/",
        "/contents/",
        "/expansion",
        "/expansions",
        "/factory content",
        "/library/",
        "/libraries/",
        "/sound content",
        "/sound library",
        "/sound libraries",
        "/sounds/",
    ]

    private nonisolated static let sampleLibraryMarkers = [
        "/samples/",
        "/sample libraries/",
        "/sample library/",
        "sample librar",
        "/loops/",
        "/apple loops/",
    ]

    private nonisolated static let impulseResponseMarkers = [
        "/impulse responses/",
        "/irs/",
        "/ir library/",
        "/cabinet impulses/",
    ]

    private nonisolated static let cacheDownloadMarkers = [
        "/cache/",
        "/caches/",
        "/download/",
        "/downloads/",
        "/package downloads/",
        "/tmp/",
        "/temp/",
    ]
}
