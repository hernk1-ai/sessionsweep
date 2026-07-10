import Foundation

enum ApplicationClassificationKind: String, CaseIterable, Sendable {
    case audioWorkstation
    case audioEditor
    case audioRestoration
    case djApplication
    case audioUtility
    case pluginManager
    case audioProductionApplication
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
        case .djApplication:
            return "DJ Application"
        case .audioUtility:
            return "Audio Utility"
        case .pluginManager:
            return "Plugin Manager"
        case .audioProductionApplication:
            return "Audio Production Application"
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
        case .audioWorkstation, .audioEditor, .audioRestoration, .djApplication,
             .audioUtility, .pluginManager, .audioProductionApplication:
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
        case .djApplication:
            return "Used for DJ performance, library preparation, and live playback workflows."
        case .audioUtility:
            return "Supports audio workflows without being a primary DAW."
        case .pluginManager:
            return "Manages audio software, licenses, plug-ins, or sound libraries."
        case .audioProductionApplication:
            return "Used for music production or audio workflows."
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

#if DEBUG
struct ApplicationClassificationDebugInfo: Sendable {
    let normalizedName: String
    let bundleIdentifier: String
    let matchedRule: String
    let classification: ApplicationClassificationKind
}
#endif

enum ApplicationClassifier {
    static func classify(displayName: String, path: String) -> ApplicationClassification {
        ApplicationClassification(kind: classificationDetails(displayName: displayName, path: path).kind)
    }

#if DEBUG
    static func debugInfo(displayName: String, path: String) -> ApplicationClassificationDebugInfo {
        let details = classificationDetails(displayName: displayName, path: path)
        return ApplicationClassificationDebugInfo(
            normalizedName: details.normalizedName,
            bundleIdentifier: details.bundleIdentifier,
            matchedRule: details.matchedRule,
            classification: details.kind
        )
    }
#endif

    private struct ClassificationDetails {
        let kind: ApplicationClassificationKind
        let normalizedName: String
        let bundleIdentifier: String
        let matchedRule: String
    }

    private struct NameRule {
        let marker: String
        let kind: ApplicationClassificationKind
        let match: MatchStyle
    }

    private enum MatchStyle {
        case exact
        case prefix
        case contains
    }

    private static func classificationDetails(displayName: String, path: String) -> ClassificationDetails {
        let bundleIdentifier = normalizedBundleIdentifier(for: path)
        let normalizedName = normalized(displayName)

        if let bundleRule = bundleIdentifierRules.first(where: { bundleIdentifier.contains($0.marker) }) {
            return ClassificationDetails(
                kind: bundleRule.kind,
                normalizedName: normalizedName,
                bundleIdentifier: bundleIdentifier,
                matchedRule: "bundle:\(bundleRule.marker)"
            )
        }

        if let nameRule = nameRules.first(where: { matches(normalizedName, rule: $0) }) {
            return ClassificationDetails(
                kind: nameRule.kind,
                normalizedName: normalizedName,
                bundleIdentifier: bundleIdentifier,
                matchedRule: "name:\(nameRule.marker)"
            )
        }

        if let heuristic = pluginManagerHeuristicMatch(normalizedName) {
            return ClassificationDetails(
                kind: .pluginManager,
                normalizedName: normalizedName,
                bundleIdentifier: bundleIdentifier,
                matchedRule: heuristic
            )
        }

        return ClassificationDetails(
            kind: .otherApplication,
            normalizedName: normalizedName,
            bundleIdentifier: bundleIdentifier,
            matchedRule: "fallback:other"
        )
    }

    private static func normalizedBundleIdentifier(for path: String) -> String {
        Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier?.lowercased() ?? ""
    }

    private static func normalized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutAppSuffix = trimmed.lowercased().hasSuffix(".app")
            ? String(trimmed.dropLast(4))
            : trimmed
        return withoutAppSuffix
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func matches(_ normalizedName: String, rule: NameRule) -> Bool {
        switch rule.match {
        case .exact:
            return normalizedName == rule.marker
        case .prefix:
            return normalizedName == rule.marker || normalizedName.hasPrefix(rule.marker + " ")
        case .contains:
            return normalizedName.contains(rule.marker)
        }
    }

    private static func pluginManagerHeuristicMatch(_ normalizedName: String) -> String? {
        guard let vendor = audioVendorSignals.first(where: { containsSignal($0, in: normalizedName) }),
              let role = pluginManagerRoleTerms.first(where: { containsSignal($0, in: normalizedName) })
        else { return nil }
        return "heuristic:plugin-manager:\(vendor)+\(role)"
    }

    private static func containsSignal(_ signal: String, in normalizedName: String) -> Bool {
        if signal.count <= 3 {
            return normalizedName.split(separator: " ").contains(Substring(signal))
        }
        return normalizedName.contains(signal)
    }

    private static let bundleIdentifierRules: [NameRule] = [
        NameRule(marker: "com.apple.logic", kind: .audioWorkstation, match: .contains),
        NameRule(marker: "com.apple.garageband", kind: .audioWorkstation, match: .contains),
        NameRule(marker: "com.ableton.live", kind: .audioWorkstation, match: .contains),
        NameRule(marker: "com.algoriddim", kind: .djApplication, match: .contains),
        NameRule(marker: "com.splice", kind: .audioProductionApplication, match: .contains),
        NameRule(marker: "com.solidstatelogic.ssl360", kind: .audioUtility, match: .contains),
        NameRule(marker: "com.izotope.productportal", kind: .pluginManager, match: .contains),
        NameRule(marker: "com.izotope.rx", kind: .audioRestoration, match: .contains),
        NameRule(marker: "com.native-instruments.nativeaccess", kind: .pluginManager, match: .contains),
        NameRule(marker: "com.uaudio", kind: .pluginManager, match: .contains),
        NameRule(marker: "com.universalaudio", kind: .pluginManager, match: .contains),
        NameRule(marker: "com.wavesaudio", kind: .pluginManager, match: .contains),
        NameRule(marker: "com.apple.dt.xcode", kind: .developerTool, match: .contains)
    ]

    private static let nameRules: [NameRule] = [
        NameRule(marker: "izotope rx", kind: .audioRestoration, match: .prefix),
        NameRule(marker: "rx 10", kind: .audioRestoration, match: .prefix),
        NameRule(marker: "rx 11", kind: .audioRestoration, match: .prefix),
        NameRule(marker: "rx audio editor", kind: .audioRestoration, match: .prefix),
        NameRule(marker: "spectralayers", kind: .audioRestoration, match: .prefix),

        NameRule(marker: "adobe audition", kind: .audioEditor, match: .prefix),
        NameRule(marker: "melodyne", kind: .audioEditor, match: .prefix),
        NameRule(marker: "sound forge", kind: .audioEditor, match: .prefix),
        NameRule(marker: "wavelab", kind: .audioEditor, match: .prefix),

        NameRule(marker: "ableton live", kind: .audioWorkstation, match: .prefix),
        NameRule(marker: "bitwig studio", kind: .audioWorkstation, match: .prefix),
        NameRule(marker: "cubase", kind: .audioWorkstation, match: .prefix),
        NameRule(marker: "digital performer", kind: .audioWorkstation, match: .prefix),
        NameRule(marker: "fl studio", kind: .audioWorkstation, match: .prefix),
        NameRule(marker: "garageband", kind: .audioWorkstation, match: .exact),
        NameRule(marker: "logic pro", kind: .audioWorkstation, match: .prefix),
        NameRule(marker: "luna", kind: .audioWorkstation, match: .prefix),
        NameRule(marker: "mainstage", kind: .audioWorkstation, match: .prefix),
        NameRule(marker: "nuendo", kind: .audioWorkstation, match: .prefix),
        NameRule(marker: "pro tools", kind: .audioWorkstation, match: .prefix),
        NameRule(marker: "reason", kind: .audioWorkstation, match: .prefix),
        NameRule(marker: "reaper", kind: .audioWorkstation, match: .prefix),
        NameRule(marker: "studio one", kind: .audioWorkstation, match: .prefix),

        NameRule(marker: "djay", kind: .djApplication, match: .prefix),
        NameRule(marker: "djay pro", kind: .djApplication, match: .prefix),
        NameRule(marker: "engine dj", kind: .djApplication, match: .prefix),
        NameRule(marker: "mixxx", kind: .djApplication, match: .exact),
        NameRule(marker: "rekordbox", kind: .djApplication, match: .prefix),
        NameRule(marker: "serato dj", kind: .djApplication, match: .prefix),
        NameRule(marker: "traktor pro", kind: .djApplication, match: .prefix),
        NameRule(marker: "virtualdj", kind: .djApplication, match: .prefix),

        NameRule(marker: "arturia software center", kind: .pluginManager, match: .exact),
        NameRule(marker: "eastwest installation center", kind: .pluginManager, match: .exact),
        NameRule(marker: "ik product manager", kind: .pluginManager, match: .exact),
        NameRule(marker: "ilok license manager", kind: .pluginManager, match: .exact),
        NameRule(marker: "izotope product portal", kind: .pluginManager, match: .exact),
        NameRule(marker: "native access", kind: .pluginManager, match: .exact),
        NameRule(marker: "plugin alliance installation manager", kind: .pluginManager, match: .exact),
        NameRule(marker: "refx cloud", kind: .pluginManager, match: .exact),
        NameRule(marker: "slate digital connect", kind: .pluginManager, match: .exact),
        NameRule(marker: "softube central", kind: .pluginManager, match: .exact),
        NameRule(marker: "spitfire audio", kind: .pluginManager, match: .exact),
        NameRule(marker: "ssl download manager", kind: .pluginManager, match: .exact),
        NameRule(marker: "toontrack product manager", kind: .pluginManager, match: .exact),
        NameRule(marker: "ua connect", kind: .pluginManager, match: .exact),
        NameRule(marker: "universal audio connect", kind: .pluginManager, match: .exact),
        NameRule(marker: "waves central", kind: .pluginManager, match: .exact),
        NameRule(marker: "xln online installer", kind: .pluginManager, match: .exact),

        NameRule(marker: "audio midi setup", kind: .audioUtility, match: .exact),
        NameRule(marker: "kontakt", kind: .audioUtility, match: .prefix),
        NameRule(marker: "komplete kontrol", kind: .audioUtility, match: .prefix),
        NameRule(marker: "maschine", kind: .audioUtility, match: .prefix),
        NameRule(marker: "soundid reference", kind: .audioUtility, match: .prefix),
        NameRule(marker: "splice", kind: .audioProductionApplication, match: .exact),
        NameRule(marker: "ssl 360", kind: .audioUtility, match: .exact),

        NameRule(marker: "adobe after effects", kind: .videoProduction, match: .prefix),
        NameRule(marker: "adobe media encoder", kind: .videoProduction, match: .prefix),
        NameRule(marker: "adobe premiere", kind: .videoProduction, match: .prefix),
        NameRule(marker: "after effects", kind: .videoProduction, match: .prefix),
        NameRule(marker: "capcut", kind: .videoProduction, match: .prefix),
        NameRule(marker: "davinci resolve", kind: .videoProduction, match: .prefix),
        NameRule(marker: "final cut pro", kind: .videoProduction, match: .prefix),
        NameRule(marker: "media encoder", kind: .videoProduction, match: .prefix),
        NameRule(marker: "premiere pro", kind: .videoProduction, match: .prefix),

        NameRule(marker: "android studio", kind: .developerTool, match: .exact),
        NameRule(marker: "cursor", kind: .developerTool, match: .exact),
        NameRule(marker: "github desktop", kind: .developerTool, match: .exact),
        NameRule(marker: "sublime text", kind: .developerTool, match: .prefix),
        NameRule(marker: "visual studio code", kind: .developerTool, match: .exact),
        NameRule(marker: "vs code", kind: .developerTool, match: .exact),
        NameRule(marker: "xcode", kind: .developerTool, match: .exact),

        NameRule(marker: "arc", kind: .webBrowser, match: .exact),
        NameRule(marker: "brave browser", kind: .webBrowser, match: .exact),
        NameRule(marker: "firefox", kind: .webBrowser, match: .exact),
        NameRule(marker: "google chrome", kind: .webBrowser, match: .exact),
        NameRule(marker: "microsoft edge", kind: .webBrowser, match: .exact),
        NameRule(marker: "safari", kind: .webBrowser, match: .exact),

        NameRule(marker: "chatgpt", kind: .aiApplication, match: .exact),
        NameRule(marker: "claude", kind: .aiApplication, match: .exact),
        NameRule(marker: "gemini", kind: .aiApplication, match: .exact),
        NameRule(marker: "perplexity", kind: .aiApplication, match: .exact),
        NameRule(marker: "poe", kind: .aiApplication, match: .exact),

        NameRule(marker: "discord", kind: .communication, match: .exact),
        NameRule(marker: "microsoft teams", kind: .communication, match: .exact),
        NameRule(marker: "slack", kind: .communication, match: .exact),
        NameRule(marker: "zoom", kind: .communication, match: .exact),

        NameRule(marker: "acrobat", kind: .productivity, match: .prefix),
        NameRule(marker: "adobe acrobat", kind: .productivity, match: .prefix),
        NameRule(marker: "dropbox", kind: .productivity, match: .exact),
        NameRule(marker: "keynote", kind: .productivity, match: .exact),
        NameRule(marker: "notion", kind: .productivity, match: .exact),
        NameRule(marker: "numbers", kind: .productivity, match: .exact),
        NameRule(marker: "pages", kind: .productivity, match: .exact),

        NameRule(marker: "adobe creative cloud", kind: .creativeApplication, match: .exact),
        NameRule(marker: "adobe illustrator", kind: .creativeApplication, match: .prefix),
        NameRule(marker: "adobe indesign", kind: .creativeApplication, match: .prefix),
        NameRule(marker: "adobe lightroom", kind: .creativeApplication, match: .prefix),
        NameRule(marker: "adobe photoshop", kind: .creativeApplication, match: .prefix),
        NameRule(marker: "illustrator", kind: .creativeApplication, match: .prefix),
        NameRule(marker: "indesign", kind: .creativeApplication, match: .prefix),
        NameRule(marker: "lightroom", kind: .creativeApplication, match: .prefix),
        NameRule(marker: "photoshop", kind: .creativeApplication, match: .prefix)
    ]

    private static let audioVendorSignals = [
        "ableton",
        "algoriddim",
        "apple logic",
        "arturia",
        "avid",
        "bitwig",
        "cockos",
        "eastwest",
        "image-line",
        "ik",
        "ilok",
        "izotope",
        "native instruments",
        "plugin alliance",
        "presonus",
        "refx",
        "slate digital",
        "softube",
        "solid state logic",
        "spitfire",
        "ssl",
        "steinberg",
        "toontrack",
        "ua",
        "universal audio",
        "waves",
        "xln audio"
    ]

    private static let pluginManagerRoleTerms = [
        "access",
        "central",
        "cloud",
        "connect",
        "download manager",
        "installation center",
        "installation manager",
        "installer",
        "license manager",
        "manager",
        "online installer",
        "portal",
        "product manager"
    ]
}
