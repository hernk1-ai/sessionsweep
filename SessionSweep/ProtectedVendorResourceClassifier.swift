import Foundation

enum ProtectedVendorResourceClassifier {
    static nonisolated func isProtected(path originalPath: String) -> Bool {
        let url = URL(fileURLWithPath: originalPath).standardizedFileURL
        let path = url.path.lowercased()
        guard isKnownVendorPath(path), isPluginResourcePath(path) else { return false }

        return true
    }

    private static nonisolated func isKnownVendorPath(_ path: String) -> Bool {
        let components = path
            .split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

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
}
