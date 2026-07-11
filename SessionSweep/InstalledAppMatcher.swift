import Foundation

// Matches installer files (.dmg, .pkg) against apps already present in
// /Applications, so SessionSweep can flag installers that are almost
// certainly safe to remove — the app they installed is already there.
nonisolated enum InstalledAppMatcher {
    static func isLikelyAlreadyInstalled(installerURL: URL) -> Bool {
        let name = installerURL.deletingPathExtension().lastPathComponent
        // Strip common version/arch suffixes: "-1.40.0-arm64", "-universal", "-2", etc.
        let cleaned = name
            .replacingOccurrences(of: #"-[\d.]+(-\w+)?$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"-(universal|arm64|darwin|x64)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        let candidates = [name, cleaned]
        let appsDir = URL(fileURLWithPath: "/Applications")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: appsDir, includingPropertiesForKeys: nil
        ) else { return false }

        let installedNames = Set(contents
            .filter { $0.pathExtension == "app" }
            .map { $0.deletingPathExtension().lastPathComponent.lowercased() })

        return candidates.contains { installedNames.contains($0.lowercased()) }
    }
}
