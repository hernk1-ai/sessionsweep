import Foundation

enum ApplicationClassificationKind: String, CaseIterable, Sendable {
    case audioWorkstation
    case audioEditor
    case audioRestoration
    case audioUtility
    case pluginManager
    case videoProduction
    case developerTool
    case webBrowser
    case creativeApplication
    case communication
    case productivity
    case aiApplication
    case otherApplication

    var displayTitle: String {
        switch self {
        case .audioWorkstation:
            return "Audio Workstation"
        case .audioEditor:
            return "Audio Editor"
        case .audioRestoration:
            return "Audio Restoration"
        case .audioUtility:
            return "Audio Utility"
        case .pluginManager:
            return "Plugin Manager"
        case .videoProduction:
            return "Video Production"
        case .developerTool:
            return "Developer Tool"
        case .webBrowser:
            return "Web Browser"
        case .creativeApplication:
            return "Creative Application"
        case .communication:
            return "Communication"
        case .productivity:
            return "Productivity"
        case .aiApplication:
            return "AI Application"
        case .otherApplication:
            return "Other Application"
        }
    }

    var isAudioApplication: Bool {
        switch self {
        case .audioWorkstation, .audioEditor, .audioRestoration, .audioUtility, .pluginManager:
            return true
        case .videoProduction, .developerTool, .webBrowser, .creativeApplication,
             .communication, .productivity, .aiApplication, .otherApplication:
            return false
        }
    }

    var description: String {
        switch self {
        case .audioWorkstation:
            return "Used for music production, recording, editing, mixing, or mastering."
        case .audioEditor:
            return "Used for detailed audio editing or post-production."
        case .audioRestoration:
            return "Used for repair, cleanup, restoration, or spectral audio work."
        case .audioUtility:
            return "Supports audio workflows without being a primary DAW."
        case .pluginManager:
            return "Manages audio software, licenses, plug-ins, or sound libraries."
        case .videoProduction:
            return "Used for video editing, encoding, motion graphics, or delivery."
        case .developerTool:
            return "Used for software development or code editing."
        case .webBrowser:
            return "Used for browsing the web."
        case .creativeApplication:
            return "Used for creative media work outside core audio production."
        case .communication:
            return "Used for messaging, meetings, or collaboration."
        case .productivity:
            return "Used for documents, notes, planning, or office work."
        case .aiApplication:
            return "Used for AI chat, assistance, or AI-powered workflows."
        case .otherApplication:
            return "Installed application that was not confidently classified."
        }
    }
}

struct ApplicationClassification: Sendable {
    let kind: ApplicationClassificationKind

    var displayTitle: String { kind.displayTitle }
    var isAudioApplication: Bool { kind.isAudioApplication }
    var description: String { kind.description }
}

enum ApplicationClassifier {
    static func classify(displayName: String, path: String) -> ApplicationClassification {
        let bundleIdentifier = bundleIdentifier(for: path)?.lowercased() ?? ""
        let normalizedName = normalized(displayName)
        let normalizedPath = normalized(path)
        let searchable = [normalizedName, bundleIdentifier, normalizedPath].joined(separator: " ")

        if matches(searchable, anyOf: audioRestorationMarkers) {
            return ApplicationClassification(kind: .audioRestoration)
        }
        if matches(searchable, anyOf: audioEditorMarkers) {
            return ApplicationClassification(kind: .audioEditor)
        }
        if matches(searchable, anyOf: audioWorkstationMarkers) {
            return ApplicationClassification(kind: .audioWorkstation)
        }
        if matches(searchable, anyOf: pluginManagerMarkers) {
            return ApplicationClassification(kind: .pluginManager)
        }
        if matches(searchable, anyOf: audioUtilityMarkers) {
            return ApplicationClassification(kind: .audioUtility)
        }
        if matches(searchable, anyOf: videoProductionMarkers) {
            return ApplicationClassification(kind: .videoProduction)
        }
        if matches(searchable, anyOf: developerToolMarkers) {
            return ApplicationClassification(kind: .developerTool)
        }
        if matches(searchable, anyOf: webBrowserMarkers) {
            return ApplicationClassification(kind: .webBrowser)
        }
        if matches(searchable, anyOf: aiApplicationMarkers) {
            return ApplicationClassification(kind: .aiApplication)
        }
        if matches(searchable, anyOf: communicationMarkers) {
            return ApplicationClassification(kind: .communication)
        }
        if matches(searchable, anyOf: productivityMarkers) {
            return ApplicationClassification(kind: .productivity)
        }
        if matches(searchable, anyOf: creativeApplicationMarkers) {
            return ApplicationClassification(kind: .creativeApplication)
        }

        return ApplicationClassification(kind: .otherApplication)
    }

    private static func bundleIdentifier(for path: String) -> String? {
        Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
    }

    private static func normalized(_ value: String) -> String {
        let lowercased = value.lowercased()
        return lowercased.hasSuffix(".app")
            ? String(lowercased.dropLast(4))
            : lowercased
    }

    private static func matches(_ searchable: String, anyOf markers: [String]) -> Bool {
        markers.contains { searchable.contains($0) }
    }

    private static let audioWorkstationMarkers = [
        "ableton live",
        "bitwig studio",
        "com.ableton.live",
        "com.apple.logic",
        "com.apple.garageband",
        "cubase",
        "digital performer",
        "fl studio",
        "garageband",
        "logic pro",
        "luna",
        "mainstage",
        "nuendo",
        "pro tools",
        "reason",
        "reaper",
        "studio one"
    ]

    private static let audioEditorMarkers = [
        "adobe audition",
        "audition",
        "melodyne",
        "sound forge",
        "wavelab"
    ]

    private static let audioRestorationMarkers = [
        "izotope rx",
        "rx 10",
        "rx 11",
        "rx audio editor",
        "spectralayers"
    ]

    private static let pluginManagerMarkers = [
        "arturia software center",
        "eastwest installation center",
        "ilok license manager",
        "native access",
        "refx cloud",
        "splice",
        "waves central"
    ]

    private static let audioUtilityMarkers = [
        "audio midi setup",
        "kontakt",
        "komplete kontrol",
        "maschine",
        "soundid reference"
    ]

    private static let videoProductionMarkers = [
        "adobe after effects",
        "adobe media encoder",
        "adobe premiere",
        "after effects",
        "capcut",
        "davinci resolve",
        "final cut pro",
        "media encoder",
        "premiere pro"
    ]

    private static let developerToolMarkers = [
        "android studio",
        "com.apple.dt.xcode",
        "cursor",
        "sublime text",
        "visual studio code",
        "vs code",
        "xcode"
    ]

    private static let webBrowserMarkers = [
        "arc",
        "brave browser",
        "firefox",
        "google chrome",
        "microsoft edge",
        "safari"
    ]

    private static let aiApplicationMarkers = [
        "chatgpt",
        "claude",
        "gemini",
        "perplexity",
        "poe"
    ]

    private static let communicationMarkers = [
        "discord",
        "microsoft teams",
        "slack",
        "zoom"
    ]

    private static let productivityMarkers = [
        "acrobat",
        "adobe acrobat",
        "keynote",
        "notion",
        "numbers",
        "pages"
    ]

    private static let creativeApplicationMarkers = [
        "adobe creative cloud",
        "adobe illustrator",
        "adobe indesign",
        "adobe lightroom",
        "adobe photoshop",
        "illustrator",
        "indesign",
        "lightroom",
        "photoshop"
    ]
}
