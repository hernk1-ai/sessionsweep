import Foundation

enum RelocationSupport: Sendable {
    case officialSupported
    case vendorToolRequired
    case manualPossible
    case reviewFirst
    case leaveInPlace
    case unknown

    nonisolated var displayTitle: String {
        switch self {
        case .officialSupported:
            return "Official Relocation Supported"
        case .vendorToolRequired:
            return "Vendor Tool Required"
        case .manualPossible:
            return "Manual Relocation May Be Possible"
        case .reviewFirst:
            return "Review Before Moving"
        case .leaveInPlace:
            return "Leave In Place"
        case .unknown:
            return "Unknown"
        }
    }
}

struct VendorGuide: Sendable {
    let vendorName: String
    let folderPattern: String
    let relocationSupport: RelocationSupport
    let about: String
    let whyItExists: String
    let recommendedMethod: String?
    let riskSummary: String
    let documentationTitle: String?
    let documentationURLString: String?
    let notes: String?
}

enum VendorRelocationAdvisor {
    static nonisolated func guide(
        for item: AudioSystemDataItem,
        kind: AudioFolderGuidanceKind,
        expectedToRemainInPlace: Bool,
        vendorRelocationMayBePossible: Bool
    ) -> VendorGuide {
        let normalizedPath = URL(fileURLWithPath: item.path).standardizedFileURL.path
        return guide(
            for: item,
            kind: kind,
            expectedToRemainInPlace: expectedToRemainInPlace,
            vendorRelocationMayBePossible: vendorRelocationMayBePossible,
            normalizedLowerPath: normalizedPath.lowercased()
        )
    }

    static nonisolated func guide(
        for item: AudioSystemDataItem,
        kind: AudioFolderGuidanceKind,
        expectedToRemainInPlace: Bool,
        vendorRelocationMayBePossible: Bool,
        normalizedLowerPath lowerPath: String
    ) -> VendorGuide {
        if let knownGuide = knownGuidePatternIndex.first(where: { lowerPath.contains($0.pattern) }) {
            return knownGuide.guide
        }

        return fallbackGuide(
            for: item,
            kind: kind,
            expectedToRemainInPlace: expectedToRemainInPlace,
            vendorRelocationMayBePossible: vendorRelocationMayBePossible
        )
    }

    private static nonisolated func fallbackGuide(
        for item: AudioSystemDataItem,
        kind: AudioFolderGuidanceKind,
        expectedToRemainInPlace: Bool,
        vendorRelocationMayBePossible: Bool
    ) -> VendorGuide {
        let support: RelocationSupport = {
            if expectedToRemainInPlace { return .leaveInPlace }
            if vendorRelocationMayBePossible { return .unknown }
            return .unknown
        }()

        let recommendedMethod: String
        let riskSummary: String
        switch support {
        case .leaveInPlace:
            recommendedMethod = "Leave this folder in its current location unless the vendor documents a supported relocation workflow."
            riskSummary = "Moving this folder manually may prevent plugins, presets, or supporting files from loading."
        default:
            recommendedMethod = "No verified relocation method is currently available for this folder."
            riskSummary = "Review vendor documentation before moving it manually. SessionSweep cannot verify that relocation is safe for this folder."
        }

        return VendorGuide(
            vendorName: "Unknown Vendor",
            folderPattern: kind.rawValue,
            relocationSupport: support,
            about: fallbackAbout(for: item, kind: kind),
            whyItExists: fallbackWhyItExists(for: kind),
            recommendedMethod: recommendedMethod,
            riskSummary: riskSummary,
            documentationTitle: nil,
            documentationURLString: nil,
            notes: nil
        )
    }

    private static nonisolated func fallbackAbout(
        for item: AudioSystemDataItem,
        kind: AudioFolderGuidanceKind
    ) -> String {
        switch kind {
        case .contentLibrary:
            return "This folder appears to store sound content, expansions, samples, or factory content used by an audio instrument or plugin."
        case .sampleLibrary:
            return "This folder appears to store audio samples used by samplers, drum instruments, or production tools."
        case .impulseResponseLibrary:
            return "This folder appears to store impulse responses used by reverbs, cabinet simulators, or acoustic processors."
        case .applicationSupport:
            return "This folder stores support files used by installed audio software."
        case .presetLibrary:
            return "This folder stores presets or configuration files used by plugins or instruments."
        case .pluginBinary:
            return "This folder contains installed plugin files used by your DAW."
        case .cacheDownload:
            return "This folder contains temporary or downloaded files created by audio software."
        case .unknownAudioFolder:
            return "\(item.friendlyName) appears to be audio-related storage, but SessionSweep cannot confidently identify the vendor workflow."
        }
    }

    private static nonisolated func fallbackWhyItExists(
        for kind: AudioFolderGuidanceKind
    ) -> String {
        switch kind {
        case .contentLibrary, .sampleLibrary, .impulseResponseLibrary:
            return "Audio software reads this content while projects are open so instruments, presets, or effects can load correctly."
        case .applicationSupport, .presetLibrary, .pluginBinary:
            return "Audio software expects these files in specific locations so plugins and related tools can launch reliably."
        case .cacheDownload:
            return "Audio software may use this location to store downloads, installers, or temporary data."
        case .unknownAudioFolder:
            return "The folder is part of your music production environment, but SessionSweep cannot verify its exact role."
        }
    }

    private struct KnownGuide: Sendable {
        let folderPatterns: [String]
        let guide: VendorGuide
    }

    private struct KnownGuidePattern: Sendable {
        let pattern: String
        let guide: VendorGuide
    }

    private nonisolated static let knownGuidePatternIndex: [KnownGuidePattern] = knownGuides.flatMap { knownGuide in
        knownGuide.folderPatterns.map { pattern in
            KnownGuidePattern(pattern: pattern, guide: knownGuide.guide)
        }
    }

    private nonisolated static let knownGuides: [KnownGuide] = [
        KnownGuide(
            folderPatterns: ["native instruments", "/kontakt", "/maschine", "/komplete"],
            guide: VendorGuide(
                vendorName: "Native Instruments",
                folderPattern: "Native Instruments / Kontakt / Komplete",
                relocationSupport: .vendorToolRequired,
                about: "This folder stores Native Instruments sound libraries, Kontakt content, or supporting files used by NI instruments.",
                whyItExists: "Kontakt, Maschine, and other NI tools stream or index this content while projects are open.",
                recommendedMethod: "Use Native Access to change, locate, or repair the library location.",
                riskSummary: "Do not move the folder directly in Finder unless Native Instruments documents that workflow. Manual moves can cause missing libraries.",
                documentationTitle: "Native Instruments Support",
                documentationURLString: "https://support.native-instruments.com/hc/en-us",
                notes: nil
            )
        ),
        KnownGuide(
            folderPatterns: ["xln audio", "addictive drums", "addictive keys"],
            guide: VendorGuide(
                vendorName: "XLN Audio",
                folderPattern: "XLN Audio / Addictive Drums / Addictive Keys",
                relocationSupport: .vendorToolRequired,
                about: "This folder stores XLN Audio sample content used by Addictive Drums, Addictive Keys, and related XLN instruments.",
                whyItExists: "The plugin streams these samples while your projects are open.",
                recommendedMethod: "Use XLN Online Installer to manage the sample content location.",
                riskSummary: "Moving this folder manually may cause XLN instruments to report missing samples.",
                documentationTitle: "XLN Audio Support",
                documentationURLString: "https://support.xlnaudio.com/hc/en-us",
                notes: nil
            )
        ),
        KnownGuide(
            folderPatterns: ["refx", "nexus"],
            guide: VendorGuide(
                vendorName: "reFX",
                folderPattern: "reFX / NEXUS",
                relocationSupport: .vendorToolRequired,
                about: "This folder may include NEXUS expansions, presets, samples, and other sound content.",
                whyItExists: "NEXUS uses this content to load factory sounds and installed expansions.",
                recommendedMethod: "Use reFX Cloud or documented reFX settings to manage the library location.",
                riskSummary: "Avoid dragging NEXUS content manually unless reFX documents that workflow.",
                documentationTitle: "reFX Support",
                documentationURLString: "https://refx.com/support/",
                notes: nil
            )
        ),
        KnownGuide(
            folderPatterns: ["arturia"],
            guide: VendorGuide(
                vendorName: "Arturia",
                folderPattern: "Arturia",
                relocationSupport: .vendorToolRequired,
                about: "This folder stores Arturia resources, presets, sound banks, or instrument support content.",
                whyItExists: "Arturia instruments and effects use these resources to load sounds, presets, and product data.",
                recommendedMethod: "Use Arturia Software Center or Arturia's documented resource-location workflow.",
                riskSummary: "Moving Arturia resources manually may break preset or sound-bank discovery.",
                documentationTitle: "Arturia Support",
                documentationURLString: "https://support.arturia.com/hc/en-us",
                notes: nil
            )
        ),
        KnownGuide(
            folderPatterns: ["spectrasonics", "/steam", "omnisphere", "keyscape", "trilian"],
            guide: VendorGuide(
                vendorName: "Spectrasonics",
                folderPattern: "Spectrasonics / STEAM / Omnisphere / Keyscape",
                relocationSupport: .officialSupported,
                about: "This folder stores Spectrasonics STEAM content used by Omnisphere, Keyscape, Trilian, and related libraries.",
                whyItExists: "Spectrasonics instruments stream and index STEAM content while sessions are open.",
                recommendedMethod: "Use Spectrasonics' documented STEAM folder relocation workflow.",
                riskSummary: "Move only the supported content location. Plugin binaries and supporting application files should remain installed normally.",
                documentationTitle: "Spectrasonics Support",
                documentationURLString: "https://support.spectrasonics.net",
                notes: nil
            )
        ),
        KnownGuide(
            folderPatterns: ["toontrack", "superior drummer", "ezdrummer", "ezkeys"],
            guide: VendorGuide(
                vendorName: "Toontrack",
                folderPattern: "Toontrack / Superior Drummer / EZdrummer",
                relocationSupport: .vendorToolRequired,
                about: "This folder stores Toontrack sample libraries and expansion content.",
                whyItExists: "Toontrack instruments stream drum, percussion, and instrument samples from these libraries.",
                recommendedMethod: "Use Toontrack Product Manager or Toontrack's documented library path tools.",
                riskSummary: "Manual moves can leave Toontrack products unable to locate installed sound libraries.",
                documentationTitle: "Toontrack Support",
                documentationURLString: "https://www.toontrack.com/faq/",
                notes: nil
            )
        ),
        KnownGuide(
            folderPatterns: ["eastwest", "soundsonline", "/opus"],
            guide: VendorGuide(
                vendorName: "EastWest",
                folderPattern: "EastWest / Soundsonline / Opus",
                relocationSupport: .vendorToolRequired,
                about: "This folder stores EastWest instrument libraries and sample content.",
                whyItExists: "EastWest instruments stream large sample libraries from disk during playback.",
                recommendedMethod: "Use EastWest Installation Center or Opus library tools to manage library locations.",
                riskSummary: "Do not move library folders manually unless EastWest documents the process for that product.",
                documentationTitle: "EastWest Support",
                documentationURLString: "https://www.soundsonline.com/support",
                notes: nil
            )
        ),
        KnownGuide(
            folderPatterns: ["spitfire audio", "/spitfire"],
            guide: VendorGuide(
                vendorName: "Spitfire Audio",
                folderPattern: "Spitfire Audio",
                relocationSupport: .vendorToolRequired,
                about: "This folder stores Spitfire Audio sample libraries and product content.",
                whyItExists: "Spitfire instruments stream sample content from these installed libraries.",
                recommendedMethod: "Use the Spitfire Audio app or documented repair/locate workflow.",
                riskSummary: "Moving libraries manually can cause products to appear missing until repaired in the vendor app.",
                documentationTitle: "Spitfire Audio Support",
                documentationURLString: "https://spitfireaudio.zendesk.com/hc/en-us",
                notes: nil
            )
        ),
        KnownGuide(
            folderPatterns: ["izotope"],
            guide: VendorGuide(
                vendorName: "iZotope",
                folderPattern: "iZotope",
                relocationSupport: .reviewFirst,
                about: "This folder stores iZotope application support, presets, analysis data, or product resources.",
                whyItExists: "iZotope software expects support files and presets to remain available for plugins and standalone apps.",
                recommendedMethod: "Review iZotope documentation for the specific product before moving anything.",
                riskSummary: "Many iZotope support folders are not sample libraries. Moving them manually may break presets, authorization, or product data.",
                documentationTitle: "iZotope Support",
                documentationURLString: "https://support.izotope.com/hc/en-us",
                notes: nil
            )
        ),
        KnownGuide(
            folderPatterns: ["slate digital", "slate trigger"],
            guide: VendorGuide(
                vendorName: "Slate Digital",
                folderPattern: "Slate Digital / Slate Trigger",
                relocationSupport: .reviewFirst,
                about: "This folder may contain Slate Digital plugin resources, presets, samples, or product support files.",
                whyItExists: "Slate plugins use these resources to load factory content and product data.",
                recommendedMethod: "Use Slate Digital documentation or product settings when relocation is supported.",
                riskSummary: "Some Slate folders are plugin resources that should remain in place. Review before moving manually.",
                documentationTitle: "Slate Digital Support",
                documentationURLString: "https://support.slatedigital.com/hc/en-us",
                notes: nil
            )
        ),
        KnownGuide(
            folderPatterns: ["plugin alliance", "brainworx", "bx_"],
            guide: VendorGuide(
                vendorName: "Plugin Alliance",
                folderPattern: "Plugin Alliance / Brainworx",
                relocationSupport: .leaveInPlace,
                about: "This folder stores plugin resources, presets, authorization data, or supporting files for Plugin Alliance products.",
                whyItExists: "Installed plugins expect these files in standard application support locations.",
                recommendedMethod: "Leave this folder in place unless Plugin Alliance documents a product-specific relocation workflow.",
                riskSummary: "Moving application support resources manually may prevent plugins from loading correctly.",
                documentationTitle: "Plugin Alliance Support",
                documentationURLString: "https://support.plugin-alliance.com/hc/en-us",
                notes: nil
            )
        ),
        KnownGuide(
            folderPatterns: ["universal audio", "/uad", "ua connect"],
            guide: VendorGuide(
                vendorName: "Universal Audio",
                folderPattern: "Universal Audio / UAD",
                relocationSupport: .reviewFirst,
                about: "This folder stores Universal Audio application support, plugin resources, or installed product content.",
                whyItExists: "UAD software uses these files for plugins, product management, and supporting resources.",
                recommendedMethod: "Review Universal Audio documentation for the specific product before moving content.",
                riskSummary: "Plugin binaries and support resources should remain installed in their expected locations.",
                documentationTitle: "Universal Audio Support",
                documentationURLString: "https://help.uaudio.com/hc/en-us",
                notes: nil
            )
        )
    ]
}
