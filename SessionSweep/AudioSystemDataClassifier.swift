import Foundation

enum AudioSystemDataCategory: String, CaseIterable, Sendable, Hashable {
    case plugins = "Plugins"
    case presets = "Presets"
    case impulseResponses = "Impulse Responses"
    case pluginContent = "Plugin Content"
    case cachesDownloads = "Caches / Downloads"
}

enum AudioSystemDataSafetyStatus: String, Sendable, Hashable {
    case essential = "Essential"
    case review = "Review"
    case likelyCache = "Likely cache"
    case unknown = "Unknown"
}

struct AudioSystemDataItem: Identifiable, Sendable {
    let id = UUID()
    let friendlyName: String
    let path: String
    let size: Int64
    let category: AudioSystemDataCategory
    let safetyStatus: AudioSystemDataSafetyStatus
}

struct AudioSystemDataSummary: Sendable {
    var items: [AudioSystemDataItem] = []
    var categoryTotals: [AudioSystemDataCategory: Int64] = [:]

    var totalSize: Int64 {
        categoryTotals.values.reduce(0, +)
    }

    var topFolders: [AudioSystemDataItem] {
        Array(items.sorted { $0.size > $1.size }.prefix(5))
    }

    var isEmpty: Bool {
        items.isEmpty
    }
}

enum AudioSystemDataClassifier {
    private static let pluginFolderNames: [String: String] = [
        "vst": "VST Plug-Ins",
        "vst3": "VST3 Plug-Ins",
        "components": "Audio Units",
        "component": "Audio Units",
        "clap": "CLAP Plug-Ins",
        "aax": "AAX Plug-Ins",
        "aaxplug-ins": "AAX Plug-Ins",
        "aax plugins": "AAX Plug-Ins",
    ]

    private static let presetVendorNames: [String: String] = [
        "refx": "reFX",
        "xfer records": "Xfer Records",
        "plugin alliance": "Plugin Alliance",
        "u-he": "u-he",
        "uhe": "u-he",
        "slate digital": "Slate Digital",
    ]

    private static let impulseResponseVendorNames: [String: String] = [
        "slate digital": "Slate Digital",
        "apple": "Apple",
    ]

    private static let applicationSupportVendorNames: [String: String] = [
        "izotope": "iZotope",
        "waves": "Waves",
        "waves audio": "Waves Audio",
        "slate digital": "Slate Digital",
        "native instruments": "Native Instruments",
        "xln audio": "XLN Audio",
        "ujam": "UJAM",
        "output": "Output",
        "kush audio": "Kush Audio",
        "overloud": "Overloud",
        "logic": "Logic",
        "ableton": "Ableton",
        "adobe": "Adobe",
    ]

    static func summarize(folderSizes: [String: Int64]) -> AudioSystemDataSummary {
        var candidates: [AudioSystemDataItem] = []

        for (path, size) in folderSizes where size > 0 {
            if let item = classify(path: path, size: size) {
                candidates.append(item)
            }
        }

        let items = candidates
            .sorted { lhs, rhs in
                if lhs.path.count == rhs.path.count { return lhs.path < rhs.path }
                return lhs.path.count > rhs.path.count
            }
            .reduce(into: [AudioSystemDataItem]()) { selected, item in
                let overlaps = selected.contains { existing in
                    pathsOverlap(existing.path, item.path)
                }
                if !overlaps {
                    selected.append(item)
                }
            }
            .sorted { $0.size > $1.size }

        var summary = AudioSystemDataSummary()
        summary.items = items
        summary.categoryTotals = Dictionary(grouping: items, by: \.category)
            .mapValues { $0.reduce(Int64(0)) { $0 + $1.size } }
        return summary
    }

    static func classify(path: String, size: Int64 = 0) -> AudioSystemDataItem? {
        let normalizedPath = normalize(path)
        let lowerPath = normalizedPath.lowercased()
        let components = normalizedPath.split(separator: "/").map(String.init)
        let lowerComponents = components.map { $0.lowercased() }

        if let item = classifyKnownCache(
            path: normalizedPath,
            lowerPath: lowerPath,
            components: components,
            lowerComponents: lowerComponents,
            size: size
        ) {
            return item
        }

        if let pluginIndex = indexOfPath(["library", "audio", "plug-ins"], in: lowerComponents) {
            guard lowerComponents.count > pluginIndex + 3 else {
                return item(
                    "Audio Plug-Ins",
                    path: normalizedPath,
                    size: size,
                    category: .plugins,
                    safety: .essential
                )
            }
            guard lowerComponents.count == pluginIndex + 4 else { return nil }
            let format = lowerComponents[pluginIndex + 3]
            let name = pluginFolderNames[format] ?? "\(components[pluginIndex + 3]) Plug-Ins"
            return item(name, path: normalizedPath, size: size, category: .plugins, safety: .essential)
        }

        if let presetsIndex = indexOfPath(["library", "audio", "presets"], in: lowerComponents) {
            guard lowerComponents.count > presetsIndex + 3 else { return nil }
            guard lowerComponents.count == presetsIndex + 4 else { return nil }
            let vendor = components[presetsIndex + 3]
            let displayVendor = presetVendorNames[vendor.lowercased()] ?? vendor
            return item(
                "\(displayVendor) Presets",
                path: normalizedPath,
                size: size,
                category: .presets,
                safety: .essential
            )
        }

        if let irIndex = indexOfPath(["library", "audio", "impulse responses"], in: lowerComponents) {
            guard lowerComponents.count > irIndex + 3 else {
                return item(
                    "Impulse Responses",
                    path: normalizedPath,
                    size: size,
                    category: .impulseResponses,
                    safety: .essential
                )
            }
            guard lowerComponents.count == irIndex + 4 else { return nil }
            let vendor = components[irIndex + 3]
            let displayVendor = impulseResponseVendorNames[vendor.lowercased()] ?? vendor
            return item(
                "\(displayVendor) Impulse Responses",
                path: normalizedPath,
                size: size,
                category: .impulseResponses,
                safety: .essential
            )
        }

        if let supportIndex = indexOfPath(["library", "application support"], in: lowerComponents) {
            guard lowerComponents.count > supportIndex + 2 else { return nil }
            guard lowerComponents.count == supportIndex + 3 else { return nil }
            let vendor = components[supportIndex + 2]
            guard let displayVendor = applicationSupportVendorNames[vendor.lowercased()] else { return nil }
            return item(
                "\(displayVendor) Application Support",
                path: normalizedPath,
                size: size,
                category: .pluginContent,
                safety: .essential
            )
        }

        return nil
    }

    private static func classifyKnownCache(
        path: String,
        lowerPath: String,
        components: [String],
        lowerComponents: [String],
        size: Int64
    ) -> AudioSystemDataItem? {
        if lowerPath.hasSuffix("/library/caches/waves audio") {
            return item("Waves Audio Cache", path: path, size: size, category: .cachesDownloads, safety: .likelyCache)
        }

        if lowerPath.hasSuffix("/library/caches/ableton/packdownloads") {
            return item("Ableton Pack Downloads", path: path, size: size, category: .cachesDownloads, safety: .likelyCache)
        }

        if lowerPath.contains("/library/application support/com.splice.splice/") {
            let cacheNames: Set<String> = ["cache", "caches", "download", "downloads", "modified", "tmp", "temp"]
            if let matched = lowerComponents.last(where: { cacheNames.contains($0) }) {
                return item(
                    "Splice \(friendlyCacheName(matched))",
                    path: path,
                    size: size,
                    category: .cachesDownloads,
                    safety: .likelyCache
                )
            }
        }

        if lowerPath.contains("/library/caches/") &&
            (lowerPath.contains("installer") || lowerPath.contains("package") || lowerPath.contains("download")) {
            return item(
                friendlyNameFromPath(components, suffix: "Cache"),
                path: path,
                size: size,
                category: .cachesDownloads,
                safety: .likelyCache
            )
        }

        if lowerPath.contains("/library/application support/") &&
            (lowerPath.contains("/installer") || lowerPath.contains("/installers")
             || lowerPath.contains("/package downloads") || lowerPath.contains("/downloads")) {
            return item(
                friendlyNameFromPath(components, suffix: "Downloads"),
                path: path,
                size: size,
                category: .cachesDownloads,
                safety: .likelyCache
            )
        }

        return nil
    }

    private static func item(
        _ friendlyName: String,
        path: String,
        size: Int64,
        category: AudioSystemDataCategory,
        safety: AudioSystemDataSafetyStatus
    ) -> AudioSystemDataItem {
        AudioSystemDataItem(
            friendlyName: friendlyName,
            path: path,
            size: size,
            category: category,
            safetyStatus: safety
        )
    }

    private static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func indexOfPath(_ needle: [String], in components: [String]) -> Int? {
        guard !needle.isEmpty, components.count >= needle.count else { return nil }
        for start in 0...(components.count - needle.count) {
            if Array(components[start..<(start + needle.count)]) == needle {
                return start
            }
        }
        return nil
    }

    private static func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || lhs.hasPrefix(rhs + "/") || rhs.hasPrefix(lhs + "/")
    }

    private static func friendlyCacheName(_ value: String) -> String {
        switch value {
        case "tmp", "temp": return "Temporary Files"
        case "cache", "caches": return "Cache"
        case "download", "downloads": return "Downloads"
        case "modified": return "Modified Files"
        default: return value.capitalized
        }
    }

    private static func friendlyNameFromPath(_ components: [String], suffix: String) -> String {
        let name = components.last?.replacingOccurrences(of: "-", with: " ") ?? suffix
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().contains(suffix.lowercased()) {
            return trimmed
        }
        return "\(trimmed) \(suffix)"
    }
}
