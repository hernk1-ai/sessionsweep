import Foundation

enum DuplicateSafetyClassification: Sendable {
    case actionable
    case protectedPluginResource
    case applicationInfrastructure

    nonisolated var isNeverRecommend: Bool {
        switch self {
        case .actionable:
            return false
        case .protectedPluginResource, .applicationInfrastructure:
            return true
        }
    }

    nonisolated var label: String {
        switch self {
        case .actionable:
            return ""
        case .protectedPluginResource:
            return "Protected Plugin Resource"
        case .applicationInfrastructure:
            return "Application Infrastructure"
        }
    }

    nonisolated var description: String {
        switch self {
        case .actionable:
            return ""
        case .protectedPluginResource:
            return "Used by installed audio software. Duplicate copies are often intentional and should not be cleaned automatically."
        case .applicationInfrastructure:
            return "Used by installed applications, frameworks, plug-ins, or licensing tools. These files should not be cleaned automatically."
        }
    }
}

enum DuplicateSafetyClassifier {
    static nonisolated func classify(path originalPath: String) -> DuplicateSafetyClassification {
        let url = URL(fileURLWithPath: originalPath).standardizedFileURL
        let path = url.path.lowercased()
        let components = pathComponents(for: path)

        if isApplicationInfrastructure(path: path, components: components) {
            return .applicationInfrastructure
        }

        if isKnownVendorPath(components: components), isPluginResourcePath(path) {
            return .protectedPluginResource
        }

        return .actionable
    }

    static nonisolated func isNeverRecommend(path: String) -> Bool {
        classify(path: path).isNeverRecommend
    }

    private static nonisolated func isApplicationInfrastructure(
        path: String,
        components: [String]
    ) -> Bool {
        if isInsideApplicationPackage(components) { return true }
        if isVersionedFrameworkLayout(components) { return true }
        if isApplicationInfrastructurePath(path: path, components: components) { return true }
        return false
    }

    private static nonisolated func isInsideApplicationPackage(_ components: [String]) -> Bool {
        let packageExtensions: Set<String> = [
            "app",
            "framework",
            "bundle",
            "plugin",
            "component",
            "vst",
            "vst3",
            "au",
            "kext",
        ]

        return components.dropLast().contains { component in
            packageExtensions.contains((component as NSString).pathExtension.lowercased())
        }
    }

    private static nonisolated func isVersionedFrameworkLayout(_ components: [String]) -> Bool {
        guard components.contains(where: { ($0 as NSString).pathExtension.lowercased() == "framework" }),
              let versionsIndex = components.firstIndex(of: "versions"),
              components.count > versionsIndex + 1 else {
            return false
        }

        return true
    }

    private static nonisolated func isApplicationInfrastructurePath(
        path: String,
        components: [String]
    ) -> Bool {
        if path.contains("/contents/macos/")
            || path.contains("/contents/frameworks/")
            || path.contains("/contents/helpers/")
            || path.contains("/contents/library/")
            || path.contains("/contents/plugins/")
            || path.contains("/contents/plug-ins/")
            || path.contains("/contents/xpcservices/")
            || path.contains("/contents/loginitems/") {
            return true
        }

        let infrastructureMarkers = [
            "adobe core sync",
            "adobe creative cloud",
            "coresync",
            "coresynccustomhook",
            "elicenser",
            "frameworks",
            "helper",
            "helpers",
            "ilok",
            "license support",
            "licenser",
            "licensing",
            "pace anti-piracy",
            "steinberg activation manager",
            "steinberg licensing",
            "support tools",
            "xpcservices",
        ]

        guard components.contains("application support")
                || components.contains("applications")
                || components.contains("library")
                || components.contains("private") else {
            return false
        }

        return infrastructureMarkers.contains { marker in
            path.contains(marker) || components.contains(marker)
        }
    }

    private static nonisolated func isKnownVendorPath(components: [String]) -> Bool {

        let vendorMarkers = [
            "arturia",
            "fabfilter",
            "izotope",
            "kush",
            "kush audio",
            "logic",
            "native access",
            "native instruments",
            "overloud",
            "plugin alliance",
            "slate",
            "slate digital",
            "soundtoys",
            "spitfire",
            "spitfire audio",
            "thu",
            "th-u",
            "universal audio",
            "waves",
            "xln",
            "xln audio",
        ]

        return vendorMarkers.contains { marker in
            components.contains { component in
                component == marker
                    || component.hasPrefix("\(marker) ")
                    || component.hasPrefix("\(marker)-")
                    || component.hasPrefix("\(marker)_")
                    || component.contains(".\(marker).")
                    || component.contains(".\(marker)-")
                    || component.contains(".\(marker)_")
            }
        }
    }

    private static nonisolated func isPluginResourcePath(_ path: String) -> Bool {
        let pluginResourceMarkers = [
            "/application support/",
            "/audio/plug-ins/",
            "/factory content/",
            "/factory/",
            "/library/application support/",
            "/library/audio/",
            "/library/audio/plug-ins/",
            "/library/audio/presets/",
            "/plug-ins/",
            "/plugins/",
            "/preset/",
            "/presets/",
            "/resource/",
            "/resources/",
            "/service center/",
        ]
        return pluginResourceMarkers.contains { path.contains($0) }
    }

    private static nonisolated func pathComponents(for path: String) -> [String] {
        path.split(separator: "/").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

enum ProtectedVendorResourceClassifier {
    static nonisolated func isProtected(path originalPath: String) -> Bool {
        DuplicateSafetyClassifier.isNeverRecommend(path: originalPath)
    }
}
