import Foundation

enum StorageRecommendationKind: Int, CaseIterable, Sendable {
    case safeCleanup = 0
    case archiveCandidates = 1
    case libraryRelocation = 2
    case largeApplications = 3
    case leaveInPlace = 4
    case keepSafe = 5
}

enum StorageRecommendationDestination: Sendable {
    case safeCleanup
    case archiveCandidates
    case libraryRelocation
    case applications
    case leaveInPlace
    case keepSafe
}

struct StorageRecommendation: Identifiable, Sendable {
    let id: StorageRecommendationKind
    let kind: StorageRecommendationKind
    let iconName: String
    let title: String
    let estimate: String
    let explanation: String
    let confidence: String?
    let actionTitle: String
    let destination: StorageRecommendationDestination?
}

struct RelocationCandidateSummary: Sendable {
    let path: String
    let size: Int64
}

struct RecommendationInputSummary: Sendable {
    let duplicateActionableBytes: Int64
    let installerActionableBytes: Int64
    let archiveCandidateBytes: Int64
    let relocationCandidates: [RelocationCandidateSummary]
    let largeOtherApplicationBytes: Int64
    let hasVeryLargeOtherApplication: Bool
    let protectedInfrastructureBytes: Int64
    let protectedItemCount: Int
}

enum StorageRecommendationEngine {
    static nonisolated func recommendations(from summary: RecommendationInputSummary) -> [StorageRecommendation] {
        var timer = StorageRecommendationPerformanceTimer()
        var recommendations: [StorageRecommendation] = []

        if let safeCleanup = safeCleanupRecommendation(
            duplicateBytes: summary.duplicateActionableBytes,
            installerBytes: summary.installerActionableBytes
        ) {
            recommendations.append(safeCleanup)
        }
        timer.mark("Safe cleanup")

        if let archive = archiveRecommendation(archiveCandidateBytes: summary.archiveCandidateBytes) {
            recommendations.append(archive)
        }
        timer.mark("Archive candidates")

        if let relocation = libraryRelocationRecommendation(candidates: summary.relocationCandidates) {
            recommendations.append(relocation)
        }
        timer.mark("Vendor relocation")

        if let applications = largeApplicationsRecommendation(
            total: summary.largeOtherApplicationBytes,
            hasVeryLargeApplication: summary.hasVeryLargeOtherApplication
        ) {
            recommendations.append(applications)
        }
        timer.mark("Large applications")

        if let leaveInPlace = leaveInPlaceRecommendation(protectedInfrastructureBytes: summary.protectedInfrastructureBytes) {
            recommendations.append(leaveInPlace)
        }
        timer.mark("Leave in place")

        if let keepSafe = keepSafeRecommendation(protectedItemCount: summary.protectedItemCount) {
            recommendations.append(keepSafe)
        }
        timer.mark("Keep Safe")

        let sorted = recommendations.sorted { $0.kind.rawValue < $1.kind.rawValue }
        timer.finish("Recommendation generation")
        return sorted
    }

    static nonisolated func recommendations(
        for result: ScanResult,
        protectedItems: [KeepSafeItem]
    ) -> [StorageRecommendation] {
        let protectedPaths = protectedPathSet(from: protectedItems)
        var recommendations: [StorageRecommendation] = []

        if let safeCleanup = safeCleanupRecommendation(for: result, protectedPaths: protectedPaths) {
            recommendations.append(safeCleanup)
        }
        if let archive = archiveRecommendation(for: result) {
            recommendations.append(archive)
        }
        if let relocation = libraryRelocationRecommendation(for: result) {
            recommendations.append(relocation)
        }
        if let applications = largeApplicationsRecommendation(for: result) {
            recommendations.append(applications)
        }
        if let leaveInPlace = leaveInPlaceRecommendation(for: result) {
            recommendations.append(leaveInPlace)
        }
        if let keepSafe = keepSafeRecommendation(protectedItems) {
            recommendations.append(keepSafe)
        }

        return recommendations.sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    private static nonisolated func safeCleanupRecommendation(
        duplicateBytes: Int64,
        installerBytes: Int64
    ) -> StorageRecommendation? {
        let total = duplicateBytes + installerBytes
        guard total > 0 else { return nil }

        return StorageRecommendation(
            id: .safeCleanup,
            kind: .safeCleanup,
            iconName: "checkmark.circle.fill",
            title: "Safe Cleanup",
            estimate: formatBytes(total),
            explanation: "Duplicate files and installers appear safe to stage for review. SessionSweep keeps this recoverable by moving files to Staging first.",
            confidence: "High Confidence",
            actionTitle: "Review Files",
            destination: .safeCleanup
        )
    }

    private static nonisolated func archiveRecommendation(
        archiveCandidateBytes total: Int64
    ) -> StorageRecommendation? {
        guard total >= 1_048_576_000 else { return nil }

        return StorageRecommendation(
            id: .archiveCandidates,
            kind: .archiveCandidates,
            iconName: "archivebox",
            title: "Archive Candidates",
            estimate: "Approximately \(formatBytes(total))",
            explanation: "Older project folders may be good archive candidates. SessionSweep cannot know whether a session is complete, so review before moving anything.",
            confidence: "Medium Confidence",
            actionTitle: "Review Folders",
            destination: .archiveCandidates
        )
    }

    private static nonisolated func libraryRelocationRecommendation(
        candidates: [RelocationCandidateSummary]
    ) -> StorageRecommendation? {
        let total = candidates.reduce(Int64(0)) { $0 + $1.size }
        guard total >= 1_048_576_000 else { return nil }

        return StorageRecommendation(
            id: .libraryRelocation,
            kind: .libraryRelocation,
            iconName: "externaldrive",
            title: "Vendor Library Relocation",
            estimate: "Approximately \(formatBytes(total))",
            explanation: "Some sample libraries appear to support relocation using official vendor tools or settings. Review vendor guidance before moving content.",
            confidence: "Review Recommended",
            actionTitle: "Learn More",
            destination: .libraryRelocation
        )
    }

    private static nonisolated func largeApplicationsRecommendation(
        total: Int64,
        hasVeryLargeApplication: Bool
    ) -> StorageRecommendation? {
        guard total >= 5_000_000_000 || hasVeryLargeApplication else { return nil }

        return StorageRecommendation(
            id: .largeApplications,
            kind: .largeApplications,
            iconName: "app.badge",
            title: "Large Applications",
            estimate: formatBytes(total),
            explanation: "Several large applications are using significant storage. This is shown for awareness only; SessionSweep does not recommend deleting apps automatically.",
            confidence: "Informational",
            actionTitle: "View Applications",
            destination: .applications
        )
    }

    private static nonisolated func leaveInPlaceRecommendation(
        protectedInfrastructureBytes total: Int64
    ) -> StorageRecommendation? {
        guard total > 0 else { return nil }

        return StorageRecommendation(
            id: .leaveInPlace,
            kind: .leaveInPlace,
            iconName: "lock.shield",
            title: "Leave In Place",
            estimate: "\(formatBytes(total)) protected infrastructure",
            explanation: "Plugin binaries and audio system folders appear essential to installed production software. No action is required.",
            confidence: nil,
            actionTitle: "Why?",
            destination: .leaveInPlace
        )
    }

    private static nonisolated func keepSafeRecommendation(
        protectedItemCount count: Int
    ) -> StorageRecommendation? {
        guard count > 0 else { return nil }

        return StorageRecommendation(
            id: .keepSafe,
            kind: .keepSafe,
            iconName: "lock.fill",
            title: "Protected Files",
            estimate: "\(count) protected item\(count == 1 ? "" : "s")",
            explanation: "These items are currently excluded from SessionSweep cleanup recommendations until protection is removed.",
            confidence: nil,
            actionTitle: "View Protected Files",
            destination: .keepSafe
        )
    }

    private static nonisolated func safeCleanupRecommendation(
        for result: ScanResult,
        protectedPaths: Set<String>
    ) -> StorageRecommendation? {
        let duplicateBytes = result.duplicateGroups.reduce(Int64(0)) { total, group in
            total + actionableDuplicateBytes(in: group, protectedPaths: protectedPaths)
        }
        let installerBytes = result.installerFiles
            .filter { !isProtected($0.url.path, protectedPaths: protectedPaths) }
            .reduce(Int64(0)) { $0 + $1.size }
        let total = duplicateBytes + installerBytes
        guard total > 0 else { return nil }

        return StorageRecommendation(
            id: .safeCleanup,
            kind: .safeCleanup,
            iconName: "checkmark.circle.fill",
            title: "Safe Cleanup",
            estimate: formatBytes(total),
            explanation: "Duplicate files and installers appear safe to stage for review. SessionSweep keeps this recoverable by moving files to Staging first.",
            confidence: "High Confidence",
            actionTitle: "Review Files",
            destination: .safeCleanup
        )
    }

    private static nonisolated func archiveRecommendation(for result: ScanResult) -> StorageRecommendation? {
        let paths = projectFolderPaths(in: result)
        let total = nonOverlappingTotal(paths: paths, in: result)
        guard total >= 1_048_576_000 else { return nil }

        return StorageRecommendation(
            id: .archiveCandidates,
            kind: .archiveCandidates,
            iconName: "archivebox",
            title: "Archive Candidates",
            estimate: "Approximately \(formatBytes(total))",
            explanation: "Older project folders may be good archive candidates. SessionSweep cannot know whether a session is complete, so review before moving anything.",
            confidence: "Medium Confidence",
            actionTitle: "Review Folders",
            destination: .archiveCandidates
        )
    }

    private static nonisolated func libraryRelocationRecommendation(for result: ScanResult) -> StorageRecommendation? {
        let audioSystemPaths = result.audioSystemData.items.compactMap { item -> String? in
            let guidance = AudioFolderGuidanceClassifier.guidance(for: item)
            guard guidance.vendorRelocationMayBePossible,
                  !guidance.expectedToRemainInPlace,
                  relocationGuidanceKinds.contains(guidance.kind)
            else { return nil }
            return item.path
        }

        let libraryFolderPaths = result.folderSizes.keys.filter(isLikelyRelocatableLibraryPath)
        let paths = Array(audioSystemPaths + libraryFolderPaths)
        let total = nonOverlappingTotal(paths: paths, in: result)
        guard total >= 1_048_576_000 else { return nil }

        return StorageRecommendation(
            id: .libraryRelocation,
            kind: .libraryRelocation,
            iconName: "externaldrive",
            title: "Vendor Library Relocation",
            estimate: "Approximately \(formatBytes(total))",
            explanation: "Some sample libraries appear to support relocation using official vendor tools or settings. Review vendor guidance before moving content.",
            confidence: "Review Recommended",
            actionTitle: "Learn More",
            destination: .libraryRelocation
        )
    }

    private static nonisolated func largeApplicationsRecommendation(for result: ScanResult) -> StorageRecommendation? {
        let nonAudioApps = result.topFiles.filter { item in
            guard item.category == .applications else { return false }
            let displayName = applicationDisplayName(item.url.lastPathComponent)
            return !ApplicationClassifier.classify(displayName: displayName, path: item.url.path).isAudioApplication
        }
        let total = nonAudioApps.reduce(Int64(0)) { $0 + $1.size }
        guard total >= 5_000_000_000 || nonAudioApps.contains(where: { $0.size >= 2_000_000_000 }) else {
            return nil
        }

        return StorageRecommendation(
            id: .largeApplications,
            kind: .largeApplications,
            iconName: "app.badge",
            title: "Large Applications",
            estimate: formatBytes(total),
            explanation: "Several large applications are using significant storage. This is shown for awareness only; SessionSweep does not recommend deleting apps automatically.",
            confidence: "Informational",
            actionTitle: "View Applications",
            destination: .applications
        )
    }

    private static nonisolated func leaveInPlaceRecommendation(for result: ScanResult) -> StorageRecommendation? {
        let paths = result.audioSystemData.items.compactMap { item -> String? in
            let guidance = AudioFolderGuidanceClassifier.guidance(for: item)
            guard guidance.expectedToRemainInPlace,
                  item.safetyStatus == .essential,
                  leaveInPlaceCategories.contains(item.category)
            else { return nil }
            return item.path
        }
        let total = nonOverlappingTotal(paths: paths, in: result)
        guard total > 0 else { return nil }

        return StorageRecommendation(
            id: .leaveInPlace,
            kind: .leaveInPlace,
            iconName: "lock.shield",
            title: "Leave In Place",
            estimate: "\(formatBytes(total)) protected infrastructure",
            explanation: "Plugin binaries and audio system folders appear essential to installed production software. No action is required.",
            confidence: nil,
            actionTitle: "Why?",
            destination: .leaveInPlace
        )
    }

    private static nonisolated func keepSafeRecommendation(_ protectedItems: [KeepSafeItem]) -> StorageRecommendation? {
        let count = protectedItems.count
        guard count > 0 else { return nil }

        return StorageRecommendation(
            id: .keepSafe,
            kind: .keepSafe,
            iconName: "lock.fill",
            title: "Protected Files",
            estimate: "\(count) protected item\(count == 1 ? "" : "s")",
            explanation: "These items are currently excluded from SessionSweep cleanup recommendations until protection is removed.",
            confidence: nil,
            actionTitle: "View Protected Files",
            destination: .keepSafe
        )
    }

    private static nonisolated func actionableDuplicateBytes(
        in group: DuplicateGroup,
        protectedPaths: Set<String>
    ) -> Int64 {
        let keeper = recommendedKeeper(in: group)
        let count = group.paths.filter { path in
            path != keeper && isStageableDuplicatePath(path, protectedPaths: protectedPaths)
        }.count
        return Int64(count) * group.fileSize
    }

    private static nonisolated func recommendedKeeper(in group: DuplicateGroup) -> String? {
        group.paths.max { lhs, rhs in
            isBetterKeeper(rhs, than: lhs)
        }
    }

    private static nonisolated func isBetterKeeper(_ lhs: String, than rhs: String) -> Bool {
        let lhsScore = locationScore(for: lhs)
        let rhsScore = locationScore(for: rhs)
        if lhsScore != rhsScore { return lhsScore > rhsScore }

        let lhsModified = modificationDate(for: lhs)
        let rhsModified = modificationDate(for: rhs)
        if lhsModified != rhsModified { return lhsModified > rhsModified }

        let lhsDepth = lhs.split(separator: "/").count
        let rhsDepth = rhs.split(separator: "/").count
        if lhsDepth != rhsDepth { return lhsDepth < rhsDepth }

        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private static nonisolated func locationScore(for path: String) -> Int {
        let lower = path.lowercased()
        var score = 10
        if lower.contains("/music/") || lower.contains("/documents/")
            || lower.contains("/projects/") || lower.contains("/sessions/") {
            score += 8
        }
        if lower.contains("/downloads/") || lower.contains("/desktop/")
            || lower.contains("/trash/") || lower.contains("/caches/")
            || lower.contains("/tmp/") || lower.contains("/temp/")
            || lower.contains("backup") || lower.contains(" copy") {
            score -= 8
        }
        return score
    }

    private static nonisolated func modificationDate(for path: String) -> TimeInterval {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
    }

    private static nonisolated func isStageableDuplicatePath(
        _ path: String,
        protectedPaths: Set<String>
    ) -> Bool {
        !isProtected(path, protectedPaths: protectedPaths)
            && !DuplicateSafetyClassifier.isNeverRecommend(path: path)
    }

    private static nonisolated func isProtected(_ path: String, protectedPaths: Set<String>) -> Bool {
        let normalized = normalize(path)
        return protectedPaths.contains(normalized)
    }

    private static nonisolated func protectedPathSet(from items: [KeepSafeItem]) -> Set<String> {
        Set(items.flatMap { [normalize($0.originalPath), normalize($0.resolvedPath)] })
    }

    private static nonisolated func projectFolderPaths(in result: ScanResult) -> [String] {
        let home = normalize(NSHomeDirectory())
        let knownPaths = [
            "\(home)/Projects",
            "\(home)/Sessions",
            "\(home)/Documents/Projects",
            "\(home)/Documents/Sessions",
            "\(home)/Music/Projects",
            "\(home)/Music/Sessions",
        ]
        let detectedPaths = result.folderSizes.keys.filter { path in
            let lower = normalize(path).lowercased()
            guard !lower.contains("/library/application support/"),
                  !lower.contains("/library/audio/")
            else { return false }
            return lower.contains("/projects/") || lower.contains("/sessions/")
                || lower.contains("/daw projects/") || lower.contains("/logic projects/")
        }
        return Array(knownPaths + detectedPaths)
            .map(normalize)
            .filter { size(ofPath: $0, in: result) > 0 }
    }

    private static nonisolated func nonOverlappingTotal(paths: [String], in result: ScanResult) -> Int64 {
        let sorted = paths
            .map(normalize)
            .filter { size(ofPath: $0, in: result) > 0 }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count < rhs.count }
                return lhs < rhs
            }

        var selected: [String] = []
        for path in sorted {
            if selected.contains(where: { pathsOverlap($0, path) }) { continue }
            selected.append(path)
        }

        return selected.reduce(Int64(0)) { $0 + size(ofPath: $1, in: result) }
    }

    private static nonisolated func size(ofPath path: String, in result: ScanResult) -> Int64 {
        let normalized = normalize(path)
        if let size = result.folderSizes[normalized] { return size }
        if normalized == normalize(result.rootPath) { return result.totalSize }
        return 0
    }

    private static nonisolated func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        pathContains(lhs, candidate: rhs) || pathContains(rhs, candidate: lhs)
    }

    private static nonisolated func pathContains(_ path: String, candidate: String) -> Bool {
        let parent = normalize(path)
        let child = normalize(candidate)
        if parent == "/" { return child.hasPrefix("/") }
        return parent == child || child.hasPrefix(parent + "/")
    }

    private static nonisolated func isLikelyRelocatableLibraryPath(_ path: String) -> Bool {
        let lower = normalize(path).lowercased()
        guard lower.contains("/sample") || lower.contains("/library") || lower.contains("/libraries")
            || lower.contains("/content") || lower.contains("/expansion") || lower.contains("/loops")
            || lower.contains("/steam") || lower.contains("/kontakt") || lower.contains("/toontrack")
        else { return false }

        return relocatableVendorMarkers.contains { lower.contains($0) }
            || lower.contains("/sample libraries/")
            || lower.contains("/sample library/")
    }

    private static nonisolated func applicationDisplayName(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private static nonisolated func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static nonisolated func formatBytes(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    private nonisolated static let relocationGuidanceKinds: Set<AudioFolderGuidanceKind> = [
        .contentLibrary,
        .sampleLibrary,
        .impulseResponseLibrary,
    ]

    private nonisolated static let leaveInPlaceCategories: Set<AudioSystemDataCategory> = [
        .plugins,
        .presets,
        .pluginContent,
    ]

    private nonisolated static let relocatableVendorMarkers = [
        "native instruments",
        "kontakt",
        "nexus",
        "refx",
        "omnisphere",
        "spectrasonics",
        "steam",
        "xln audio",
        "toontrack",
        "superior drummer",
        "ezdrummer",
        "slate trigger",
        "eastwest",
        "spitfire",
        "output",
        "uvi",
    ]
}

private nonisolated struct StorageRecommendationPerformanceTimer {
    private var checkpoints: [(String, Double)] = []
    private let start = CFAbsoluteTimeGetCurrent()
    private var last = CFAbsoluteTimeGetCurrent()

    mutating func mark(_ label: String) {
        #if DEBUG
        let now = CFAbsoluteTimeGetCurrent()
        checkpoints.append((label, (now - last) * 1000))
        last = now
        #endif
    }

    func finish(_ label: String) {
        #if DEBUG
        let total = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let details = checkpoints
            .map { "  - \($0.0): \(Int($0.1.rounded())) ms" }
            .joined(separator: "\n")
        if details.isEmpty {
            print("\(label) built in \(Int(total.rounded())) ms")
        } else {
            print("\(label) built in \(Int(total.rounded())) ms\n\(details)")
        }
        #endif
    }
}
