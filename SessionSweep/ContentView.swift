import SwiftUI
import AppKit
import Combine

extension Category {
    var color: Color {
        switch self {
        case .projects:        return .purple
        case .plugins:         return .indigo
        case .pluginData:      return .blue
        case .sampleLibraries: return .mint
        case .audioFiles:      return .cyan
        case .applications:    return .brown
        case .media:           return .orange
        case .installers:      return .pink
        case .archives:        return .yellow
        case .other:           return .gray
        }
    }
}

extension AudioSystemDataCategory {
    var color: Color {
        switch self {
        case .plugins: return .indigo
        case .presets: return .blue
        case .impulseResponses: return .mint
        case .pluginContent: return .teal
        case .cachesDownloads: return .orange
        }
    }
}

extension AudioSystemDataSafetyStatus {
    var color: Color {
        switch self {
        case .essential: return .secondary
        case .review: return .yellow
        case .likelyCache: return .orange
        case .unknown: return .gray
        }
    }

    var explanatoryCopy: String {
        switch self {
        case .essential:
            return "Required for installed audio software. Deleting these files may cause plugins or applications to stop working."
        case .review:
            return "Review before making changes."
        case .likelyCache:
            return "Temporary or regenerable files. Review before deleting."
        case .unknown:
            return "SessionSweep couldn't confidently identify this folder. Review manually before making changes."
        }
    }
}

@MainActor
final class ScanController: ObservableObject {
    @Published var isScanning = false
    @Published var phase: ScanPhase = .scanning
    @Published var liveCount = 0
    @Published var liveBytes: Int64 = 0
    @Published var liveItems = 0
    @Published var liveLabel = ""
    @Published var dupChecked = 0
    @Published var dupTotal = 0
    @Published var result: ScanResult?
    @Published var scannedPath = ""
    @Published var currentPath = ""
    private var cancelToken: CancelToken?

    func cancel() { cancelToken?.cancel() }
    func navigate(to path: String) { currentPath = path }

    func start(url: URL) {
        let std = url.standardizedFileURL
        let token = CancelToken()
        cancelToken = token
        isScanning = true; result = nil
        phase = .scanning; liveCount = 0; liveBytes = 0; liveLabel = ""
        liveItems = 0; dupChecked = 0; dupTotal = 0
        scannedPath = std.path

        Task {
            let r = await Task.detached(priority: .userInitiated) {
                Scanner.scan(root: std, cancel: token) { p in
                    DispatchQueue.main.async {
                        self.phase = p.phase
                        self.liveLabel = p.label
                        if p.phase == .scanning {
                            self.liveCount = p.count
                            self.liveBytes = p.total
                            self.liveItems = p.itemsSeen
                        } else {
                            self.dupChecked = p.count
                            self.dupTotal = Int(p.total)
                        }
                    }
                }
            }.value
            self.result = r
            self.currentPath = r.rootPath
            self.isScanning = false
            self.cancelToken = nil
        }
    }

    func children(of path: String) -> [SizedItem] {
        guard let result else { return [] }
        let paths = result.folderChildren[path] ?? []
        return paths
            .map { SizedItem(url: URL(fileURLWithPath: $0), size: result.folderSizes[$0] ?? 0) }
            .sorted { $0.size > $1.size }
    }

    func size(of path: String) -> Int64 { result?.folderSizes[path] ?? 0 }
    func hasChildren(_ path: String) -> Bool { !(result?.folderChildren[path]?.isEmpty ?? true) }
}

private nonisolated enum StorageExplorerAudioCategory: String, CaseIterable, Hashable {
    case plugins = "Plugins"
    case pluginContent = "Plugin Content"
    case presets = "Presets"
    case sampleLibraries = "Sample Libraries"
    case impulseResponses = "Impulse Responses"
    case audioProjects = "Audio Projects"
    case audioFiles = "Audio Files"
    case cachesDownloads = "Caches / Downloads"
    case otherAudioStorage = "Other Audio Storage"

    var description: String {
        switch self {
        case .plugins:
            return "Installed plug-in formats and audio units."
        case .pluginContent:
            return "Support files, factory content, databases, and vendor resources."
        case .presets:
            return "Preset folders used by instruments, effects, and DAWs."
        case .sampleLibraries:
            return "Sample packs, sound libraries, loops, and instrument libraries."
        case .impulseResponses:
            return "IR libraries for reverbs, cabinets, and acoustic processors."
        case .audioProjects:
            return "DAW sessions, projects, and production folders."
        case .audioFiles:
            return "Bounces, stems, mixes, renders, and standalone audio files."
        case .cachesDownloads:
            return "Audio software caches, pack downloads, and temporary content."
        case .otherAudioStorage:
            return "Audio-related storage that does not fit another category."
        }
    }

    var iconName: String {
        switch self {
        case .plugins: return "puzzlepiece.extension.fill"
        case .pluginContent: return "shippingbox.fill"
        case .presets: return "slider.horizontal.3"
        case .sampleLibraries: return "waveform"
        case .impulseResponses: return "dot.radiowaves.left.and.right"
        case .audioProjects: return "music.note.list"
        case .audioFiles: return "waveform.path"
        case .cachesDownloads: return "arrow.down.circle.fill"
        case .otherAudioStorage: return "folder.fill"
        }
    }
}

private nonisolated enum StorageExplorerPersonalFolder: String, CaseIterable, Hashable {
    case desktop = "Desktop"
    case documents = "Documents"
    case downloads = "Downloads"
    case music = "Music"
    case movies = "Movies"
    case projects = "Projects"
    case other = "Other Personal Files"

    var description: String {
        switch self {
        case .desktop:
            return "Files saved on your Desktop."
        case .documents:
            return "Documents and user-created folders."
        case .downloads:
            return "Downloaded files, installers, archives, and transfers."
        case .music:
            return "Music folder content outside audio-system locations."
        case .movies:
            return "Video and media files in your Movies folder."
        case .projects:
            return "Project and session folders in common user locations."
        case .other:
            return "Other user-level storage not already shown above."
        }
    }
}

private nonisolated enum StorageExplorerSource: Hashable {
    case audio(StorageExplorerAudioCategory, basePath: String)
    case applications(basePath: String)
    case personal(StorageExplorerPersonalFolder, basePath: String)
    case otherMac(basePath: String)
}

private nonisolated enum StorageExplorerRoute: Hashable {
    case root
    case audioProduction
    case audioCategory(StorageExplorerAudioCategory)
    case applications
    case personalFiles
    case rawFolder(path: String, source: StorageExplorerSource)
}

private nonisolated struct StorageExplorerNode: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let path: String?
    let size: Int64
    let iconName: String
    let color: Color
    let route: StorageExplorerRoute?
}

private nonisolated struct ApplicationExplorerItem: Identifiable {
    let node: StorageExplorerNode
    let classification: ApplicationClassification

    var id: String { node.id }
}

private nonisolated struct StorageExplorerContributor: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let path: String
    let size: Int64
    let category: StorageExplorerAudioCategory
    let priority: Int
}

private nonisolated struct StorageExplorerBreadcrumb: Identifiable {
    let id: String
    let title: String
    let route: StorageExplorerRoute
}

private nonisolated struct CategoryPresentationRow {
    let category: Category
    let size: Int64
}

private nonisolated struct AudioCategoryPresentationRow {
    let category: AudioSystemDataCategory
    let size: Int64
}

private nonisolated struct AudioFolderPresentationRow: Identifiable {
    let item: AudioSystemDataItem
    let guidance: AudioFolderGuidance

    var id: String { item.path }
}

private nonisolated struct DuplicatePathPresentationRow: Identifiable {
    let path: String
    let pathKey: String
    let fileSize: Int64
    let isKeeper: Bool
    let safetyClassification: DuplicateSafetyClassification
    let keepSafeItem: KeepSafeItem?

    var id: String { path }
    var isNeverRecommend: Bool { safetyClassification.isNeverRecommend }
    var isKeepSafe: Bool { keepSafeItem != nil }
    var isStageable: Bool { !isNeverRecommend && !isKeepSafe }
}

private nonisolated struct DuplicateGroupPresentationRow: Identifiable {
    let group: DuplicateGroup
    let keeper: String?
    let actionableBytes: Int64
    let paths: [DuplicatePathPresentationRow]

    var id: DuplicateGroup.ID { group.id }
}

private nonisolated struct IdenticalContentGroupPresentation: Identifiable {
    let group: DuplicateGroup
    let classification: DifferentNameMatchClassification
    let sharedParent: String?

    var id: DuplicateGroup.ID { group.id }
    var representedStorageBytes: Int64 { group.fileSize * Int64(group.count) }
    var largestFileBytes: Int64 { group.fileSize }
    var filename: String { group.displayName }
}

private nonisolated struct InstallerPresentationRow: Identifiable {
    let item: SizedItem
    let path: String
    let pathKey: String
    let displayName: String
    let parentPath: String
    let keepSafeItem: KeepSafeItem?
    let alreadyInstalled: Bool

    var id: String { path }
    var isKeepSafe: Bool { keepSafeItem != nil }
    var isStageable: Bool { !isKeepSafe }
}

private nonisolated struct DuplicatePathScanPresentationRow {
    let path: String
    let pathKey: String
    let fileSize: Int64
    let isKeeper: Bool
    let safetyClassification: DuplicateSafetyClassification
}

private nonisolated struct DuplicateGroupScanPresentationRow {
    let group: DuplicateGroup
    let keeper: String?
    let paths: [DuplicatePathScanPresentationRow]
}

private nonisolated struct InstallerScanPresentationRow {
    let item: SizedItem
    let path: String
    let pathKey: String
    let displayName: String
    let parentPath: String
    let alreadyInstalled: Bool
}

private nonisolated struct StorageExplorerRoutePresentation {
    let route: StorageExplorerRoute
    let nodes: [StorageExplorerNode]
    let total: Int64
    let residual: (title: String, size: Int64)?
    let breadcrumbs: [StorageExplorerBreadcrumb]
}

// Immutable reference storage keeps large scan-derived arrays and dictionaries out of
// SwiftUI's value-copy path when small local UI state, such as selection, changes.
private nonisolated final class ScanDerivedPresentationData: @unchecked Sendable {
    let reuseToken: UUID
    let totalSize: Int64
    let categoryRows: [CategoryPresentationRow]
    let audioCategoryRows: [AudioCategoryPresentationRow]
    let topAudioFolders: [AudioFolderPresentationRow]
    let detectedAudioFolders: [AudioFolderPresentationRow]
    let firstRelocationCandidatePath: String?
    let identicalContentGroups: [IdenticalContentGroupPresentation]
    let largestAudioAssets: [SizedItem]
    let otherLargeApplications: [SizedItem]
    let duplicateGroups: [DuplicateGroupScanPresentationRow]
    let installerRows: [InstallerScanPresentationRow]
    let recommendationBaseSummary: RecommendationInputSummary
    let result: ScanResult
    let audioContributors: [StorageExplorerContributor]

    init(
        reuseToken: UUID,
        totalSize: Int64,
        categoryRows: [CategoryPresentationRow],
        audioCategoryRows: [AudioCategoryPresentationRow],
        topAudioFolders: [AudioFolderPresentationRow],
        detectedAudioFolders: [AudioFolderPresentationRow],
        firstRelocationCandidatePath: String?,
        identicalContentGroups: [IdenticalContentGroupPresentation],
        largestAudioAssets: [SizedItem],
        otherLargeApplications: [SizedItem],
        duplicateGroups: [DuplicateGroupScanPresentationRow],
        installerRows: [InstallerScanPresentationRow],
        recommendationBaseSummary: RecommendationInputSummary,
        result: ScanResult,
        audioContributors: [StorageExplorerContributor]
    ) {
        self.reuseToken = reuseToken
        self.totalSize = totalSize
        self.categoryRows = categoryRows
        self.audioCategoryRows = audioCategoryRows
        self.topAudioFolders = topAudioFolders
        self.detectedAudioFolders = detectedAudioFolders
        self.firstRelocationCandidatePath = firstRelocationCandidatePath
        self.identicalContentGroups = identicalContentGroups
        self.largestAudioAssets = largestAudioAssets
        self.otherLargeApplications = otherLargeApplications
        self.duplicateGroups = duplicateGroups
        self.installerRows = installerRows
        self.recommendationBaseSummary = recommendationBaseSummary
        self.result = result
        self.audioContributors = audioContributors
    }
}

// Immutable reference storage for protection projections prevents local interaction
// updates from structurally copying large duplicate and installer row arrays.
private nonisolated final class ProtectionDerivedPresentationData: @unchecked Sendable {
    let keepSafeRevision: String
    let keepSafeIndex: KeepSafeIndex
    let recommendations: [StorageRecommendation]
    let duplicateGroups: [DuplicateGroupPresentationRow]
    let duplicateActionableTotal: Int64
    let duplicateStageablePaths: Set<String>
    let duplicatePathSizes: [String: Int64]
    let recommendedDuplicateSelection: Set<String>
    let installerRows: [InstallerPresentationRow]
    let stageableInstallerRows: [InstallerPresentationRow]
    let installerActionableTotal: Int64
    let installerStageablePaths: Set<String>
    let installerPathSizes: [String: Int64]
    let sortedKeepSafeItems: [KeepSafeItem]

    init(
        keepSafeRevision: String,
        keepSafeIndex: KeepSafeIndex,
        recommendations: [StorageRecommendation],
        duplicateGroups: [DuplicateGroupPresentationRow],
        duplicateActionableTotal: Int64,
        duplicateStageablePaths: Set<String>,
        duplicatePathSizes: [String: Int64],
        recommendedDuplicateSelection: Set<String>,
        installerRows: [InstallerPresentationRow],
        stageableInstallerRows: [InstallerPresentationRow],
        installerActionableTotal: Int64,
        installerStageablePaths: Set<String>,
        installerPathSizes: [String: Int64],
        sortedKeepSafeItems: [KeepSafeItem]
    ) {
        self.keepSafeRevision = keepSafeRevision
        self.keepSafeIndex = keepSafeIndex
        self.recommendations = recommendations
        self.duplicateGroups = duplicateGroups
        self.duplicateActionableTotal = duplicateActionableTotal
        self.duplicateStageablePaths = duplicateStageablePaths
        self.duplicatePathSizes = duplicatePathSizes
        self.recommendedDuplicateSelection = recommendedDuplicateSelection
        self.installerRows = installerRows
        self.stageableInstallerRows = stageableInstallerRows
        self.installerActionableTotal = installerActionableTotal
        self.installerStageablePaths = installerStageablePaths
        self.installerPathSizes = installerPathSizes
        self.sortedKeepSafeItems = sortedKeepSafeItems
    }

    nonisolated static func build(
        scanData: ScanDerivedPresentationData,
        keepSafeItems: [KeepSafeItem],
        keepSafeRevision: String
    ) -> ProtectionDerivedPresentationData {
        var timer = ResultsPerformanceTimer()

        let keepSafeIndex = KeepSafeIndex(items: keepSafeItems)
        timer.mark("Keep Safe index")

        let duplicateGroups = scanData.duplicateGroups.map { group -> DuplicateGroupPresentationRow in
            let pathRows = group.paths.map { row in
                DuplicatePathPresentationRow(
                    path: row.path,
                    pathKey: row.pathKey,
                    fileSize: row.fileSize,
                    isKeeper: row.isKeeper,
                    safetyClassification: row.safetyClassification,
                    keepSafeItem: keepSafeIndex.item(forNormalizedPath: row.pathKey)
                )
            }
            let actionableCount = pathRows.filter { !$0.isKeeper && $0.isStageable }.count
            return DuplicateGroupPresentationRow(
                group: group.group,
                keeper: group.keeper,
                actionableBytes: Int64(actionableCount) * group.group.fileSize,
                paths: pathRows
            )
        }
        let duplicateStageablePaths = Set(duplicateGroups.flatMap { $0.paths.filter(\.isStageable).map(\.path) })
        let duplicatePathSizes = Dictionary(uniqueKeysWithValues: duplicateGroups.flatMap { group in
            group.paths.map { ($0.path, $0.fileSize) }
        })
        let recommendedDuplicateSelection = Set(duplicateGroups.flatMap { group in
            group.paths.filter { !$0.isKeeper && $0.isStageable }.map(\.path)
        })
        let duplicateActionableTotal = duplicateGroups.reduce(Int64(0)) { $0 + $1.actionableBytes }
        timer.mark("Duplicate protection projection")

        let installerRows = scanData.installerRows.map { row in
            InstallerPresentationRow(
                item: row.item,
                path: row.path,
                pathKey: row.pathKey,
                displayName: row.displayName,
                parentPath: row.parentPath,
                keepSafeItem: keepSafeIndex.item(forNormalizedPath: row.pathKey),
                alreadyInstalled: row.alreadyInstalled
            )
        }
        let stageableInstallerRows = installerRows.filter(\.isStageable)
        let installerActionableTotal = stageableInstallerRows.reduce(Int64(0)) { $0 + $1.item.size }
        let installerStageablePaths = Set(stageableInstallerRows.map(\.path))
        let installerPathSizes = Dictionary(uniqueKeysWithValues: installerRows.map { ($0.path, $0.item.size) })
        timer.mark("Installer protection projection")

        let baseSummary = scanData.recommendationBaseSummary
        let recommendationSummary = RecommendationInputSummary(
            duplicateActionableBytes: duplicateActionableTotal,
            installerActionableBytes: installerActionableTotal,
            archiveCandidateBytes: baseSummary.archiveCandidateBytes,
            relocationCandidates: baseSummary.relocationCandidates,
            largeOtherApplicationBytes: baseSummary.largeOtherApplicationBytes,
            hasVeryLargeOtherApplication: baseSummary.hasVeryLargeOtherApplication,
            protectedInfrastructureBytes: baseSummary.protectedInfrastructureBytes,
            protectedItemCount: keepSafeItems.count
        )
        debugLog("Protected summary refresh for revision \(keepSafeRevision)")
        let recommendations = StorageRecommendationEngine.recommendations(from: recommendationSummary)
        timer.mark("Recommendations")

        let sortedKeepSafeItems = keepSafeItems.sorted { lhs, rhs in
            let lhsKnown = lhs.sizeAtProtection > 0
            let rhsKnown = rhs.sizeAtProtection > 0
            if lhsKnown != rhsKnown { return lhsKnown }
            if lhsKnown && rhsKnown && lhs.sizeAtProtection != rhs.sizeAtProtection {
                return lhs.sizeAtProtection > rhs.sizeAtProtection
            }
            if lhs.dateProtected != rhs.dateProtected {
                return lhs.dateProtected > rhs.dateProtected
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
        timer.mark("Protected item sorting")

        timer.finish("Protection-only presentation refresh")

        return ProtectionDerivedPresentationData(
            keepSafeRevision: keepSafeRevision,
            keepSafeIndex: keepSafeIndex,
            recommendations: recommendations,
            duplicateGroups: duplicateGroups,
            duplicateActionableTotal: duplicateActionableTotal,
            duplicateStageablePaths: duplicateStageablePaths,
            duplicatePathSizes: duplicatePathSizes,
            recommendedDuplicateSelection: recommendedDuplicateSelection,
            installerRows: installerRows,
            stageableInstallerRows: stageableInstallerRows,
            installerActionableTotal: installerActionableTotal,
            installerStageablePaths: installerStageablePaths,
            installerPathSizes: installerPathSizes,
            sortedKeepSafeItems: sortedKeepSafeItems
        )
    }
}

// Immutable reference model so refreshing local UI state does not copy the large
// scan-derived/protection-derived presentation payloads.
private nonisolated final class ResultsPresentationModel: @unchecked Sendable {
    let identity: String
    let scanData: ScanDerivedPresentationData
    let protectionData: ProtectionDerivedPresentationData

    init(
        identity: String,
        scanData: ScanDerivedPresentationData,
        protectionData: ProtectionDerivedPresentationData
    ) {
        self.identity = identity
        self.scanData = scanData
        self.protectionData = protectionData
    }

    var keepSafeRevision: String { protectionData.keepSafeRevision }
    var totalSize: Int64 { scanData.totalSize }
    var keepSafeIndex: KeepSafeIndex { protectionData.keepSafeIndex }
    var recommendations: [StorageRecommendation] { protectionData.recommendations }
    var categoryRows: [CategoryPresentationRow] { scanData.categoryRows }
    var audioCategoryRows: [AudioCategoryPresentationRow] { scanData.audioCategoryRows }
    var topAudioFolders: [AudioFolderPresentationRow] { scanData.topAudioFolders }
    var detectedAudioFolders: [AudioFolderPresentationRow] { scanData.detectedAudioFolders }
    var firstRelocationCandidatePath: String? { scanData.firstRelocationCandidatePath }
    var duplicateGroups: [DuplicateGroupPresentationRow] { protectionData.duplicateGroups }
    var duplicateActionableTotal: Int64 { protectionData.duplicateActionableTotal }
    var duplicateStageablePaths: Set<String> { protectionData.duplicateStageablePaths }
    var duplicatePathSizes: [String: Int64] { protectionData.duplicatePathSizes }
    var recommendedDuplicateSelection: Set<String> { protectionData.recommendedDuplicateSelection }
    var identicalContentGroups: [IdenticalContentGroupPresentation] { scanData.identicalContentGroups }
    var installerRows: [InstallerPresentationRow] { protectionData.installerRows }
    var stageableInstallerRows: [InstallerPresentationRow] { protectionData.stageableInstallerRows }
    var installerActionableTotal: Int64 { protectionData.installerActionableTotal }
    var installerStageablePaths: Set<String> { protectionData.installerStageablePaths }
    var installerPathSizes: [String: Int64] { protectionData.installerPathSizes }
    var largestAudioAssets: [SizedItem] { scanData.largestAudioAssets }
    var otherLargeApplications: [SizedItem] { scanData.otherLargeApplications }
    var sortedKeepSafeItems: [KeepSafeItem] { protectionData.sortedKeepSafeItems }

    private var result: ScanResult { scanData.result }
    private var audioContributors: [StorageExplorerContributor] { scanData.audioContributors }

    nonisolated static func build(
        result: ScanResult,
        keepSafeItems: [KeepSafeItem],
        identity: String,
        keepSafeRevision: String
    ) -> ResultsPresentationModel {
        debugLog("Starting full scan presentation build for identity \(identity)")
        var timer = ResultsPerformanceTimer()

        let categoryRows = Category.allCases
            .map { CategoryPresentationRow(category: $0, size: result.categoryTotals[$0] ?? 0) }
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }
        timer.mark("Storage chart rows")

        let audioCategoryRows = AudioSystemDataCategory.allCases
            .map { AudioCategoryPresentationRow(category: $0, size: result.audioSystemData.categoryTotals[$0] ?? 0) }
        let audioRowsByPath = Dictionary(uniqueKeysWithValues: result.audioSystemData.items.map { item in
            (item.path, AudioFolderPresentationRow(
                item: item,
                guidance: AudioFolderGuidanceClassifier.guidance(for: item)
            ))
        })
        let topAudioFolders = result.audioSystemData.topFolders.compactMap { audioRowsByPath[$0.path] }
        let detectedAudioFolders = result.audioSystemData.items.compactMap { audioRowsByPath[$0.path] }
        let relocationCandidateRows = detectedAudioFolders
            .filter {
                $0.guidance.vendorRelocationMayBePossible
                    && !$0.guidance.expectedToRemainInPlace
                    && relocationGuidanceKinds.contains($0.guidance.kind)
            }
            .sorted { lhs, rhs in
                let lhsRank = relocationSupportSortRank(lhs.guidance.relocationSupport)
                let rhsRank = relocationSupportSortRank(rhs.guidance.relocationSupport)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                if lhs.item.size != rhs.item.size { return lhs.item.size > rhs.item.size }
                return lhs.item.friendlyName.localizedStandardCompare(rhs.item.friendlyName) == .orderedAscending
            }
        let firstRelocationCandidatePath = relocationCandidateRows.first?.item.path
        let leaveInPlaceRows = detectedAudioFolders.filter {
            $0.guidance.expectedToRemainInPlace
                && $0.item.safetyStatus == .essential
                && leaveInPlaceCategories.contains($0.item.category)
        }
        timer.mark("Audio guidance")

        let duplicateGroups = result.duplicateGroups.map { group -> DuplicateGroupScanPresentationRow in
            let keeper = recommendedKeeper(in: group)
            let pathRows = group.paths.map { path in
                DuplicatePathScanPresentationRow(
                    path: path,
                    pathKey: KeepSafeStore.standardizedPath(path),
                    fileSize: group.fileSize,
                    isKeeper: path == keeper,
                    safetyClassification: DuplicateSafetyClassifier.classify(path: path)
                )
            }
            return DuplicateGroupScanPresentationRow(
                group: group,
                keeper: keeper,
                paths: pathRows
            )
        }
        timer.mark("Duplicate scan presentation")

        let identicalContentGroups = sortedIdenticalContentGroups(result.identicalContentGroups)
        timer.mark("Identical-content classification")

        let installerRows = result.installerFiles
            .sorted { $0.size > $1.size }
            .map { item in
                let path = item.url.path
                return InstallerScanPresentationRow(
                    item: item,
                    path: path,
                    pathKey: KeepSafeStore.standardizedPath(path),
                    displayName: item.displayName,
                    parentPath: item.parentPath,
                    alreadyInstalled: InstalledAppMatcher.isLikelyAlreadyInstalled(installerURL: item.url)
                )
            }
        timer.mark("Installer scan presentation")

        let largestAudioAssets = Self.largestAudioAssets(in: result)
        let otherLargeApplications = Self.otherLargeApplications(in: result)
        timer.mark("Largest assets")

        let audioContributors = audioProductionContributors(in: result)
        timer.mark("Storage Explorer contributors")

        var recommendationSummaryTimer = ResultsPerformanceTimer()
        let archiveCandidateBytes = archiveCandidateTotal(in: result)
        recommendationSummaryTimer.mark("Archive folders")
        let relocationCandidates = relocationCandidateSummaries(
            in: result,
            audioRows: relocationCandidateRows
        )
        recommendationSummaryTimer.mark("Relocation folders")
        let largeOtherApplicationBytes = otherLargeApplications.reduce(Int64(0)) { $0 + $1.size }
        let hasVeryLargeOtherApplication = otherLargeApplications.contains { $0.size >= 2_000_000_000 }
        recommendationSummaryTimer.mark("Application totals")
        let protectedInfrastructureBytes = nonOverlappingPathSummaries(
            paths: leaveInPlaceRows.map(\.item.path),
            in: result
        ).reduce(Int64(0)) { $0 + $1.size }
        recommendationSummaryTimer.mark("Protected infrastructure")
        let recommendationBaseSummary = RecommendationInputSummary(
            duplicateActionableBytes: 0,
            installerActionableBytes: 0,
            archiveCandidateBytes: archiveCandidateBytes,
            relocationCandidates: relocationCandidates,
            largeOtherApplicationBytes: largeOtherApplicationBytes,
            hasVeryLargeOtherApplication: hasVeryLargeOtherApplication,
            protectedInfrastructureBytes: protectedInfrastructureBytes,
            protectedItemCount: 0
        )
        recommendationSummaryTimer.finish("Recommendation summary")
        timer.mark("Scan-derived recommendation summary")

        let scanData = ScanDerivedPresentationData(
            reuseToken: UUID(),
            totalSize: result.totalSize,
            categoryRows: categoryRows,
            audioCategoryRows: audioCategoryRows,
            topAudioFolders: topAudioFolders,
            detectedAudioFolders: detectedAudioFolders,
            firstRelocationCandidatePath: firstRelocationCandidatePath,
            identicalContentGroups: identicalContentGroups,
            largestAudioAssets: largestAudioAssets,
            otherLargeApplications: otherLargeApplications,
            duplicateGroups: duplicateGroups,
            installerRows: installerRows,
            recommendationBaseSummary: recommendationBaseSummary,
            result: result,
            audioContributors: audioContributors
        )
        let protectionData = ProtectionDerivedPresentationData.build(
            scanData: scanData,
            keepSafeItems: keepSafeItems,
            keepSafeRevision: keepSafeRevision
        )
        timer.mark("Initial protection projection")
        timer.finish("Full scan presentation model")

        return ResultsPresentationModel(
            identity: identity,
            scanData: scanData,
            protectionData: protectionData
        )
    }

    nonisolated func refreshingProtection(
        keepSafeItems: [KeepSafeItem],
        keepSafeRevision: String
    ) -> ResultsPresentationModel {
        debugLog("Starting protection-only refresh for revision \(keepSafeRevision)")
        let protectionData = ProtectionDerivedPresentationData.build(
            scanData: scanData,
            keepSafeItems: keepSafeItems,
            keepSafeRevision: keepSafeRevision
        )
        return ResultsPresentationModel(
            identity: identity,
            scanData: scanData,
            protectionData: protectionData
        )
    }
}

nonisolated struct ResultsProtectionSnapshot {
    let scanDataObjectID: ObjectIdentifier
    let scanReuseToken: UUID
    let duplicateActionableTotal: Int64
    let installerActionableTotal: Int64
    let protectedItemCount: Int
    let recommendationKinds: [StorageRecommendationKind]
    let duplicateGroupIDs: [DuplicateGroup.ID]
    let duplicatePathIDs: [String]
    let installerRowIDs: [String]
    let storageExplorerRootNodeIDs: [String]
}

nonisolated enum ResultsProtectionProjectionTestHarness {
    static func refreshedSnapshot(
        result: ScanResult,
        initialKeepSafeItems: [KeepSafeItem],
        refreshedKeepSafeItems: [KeepSafeItem]
    ) -> (before: ResultsProtectionSnapshot, after: ResultsProtectionSnapshot) {
        let model = ResultsPresentationModel.build(
            result: result,
            keepSafeItems: initialKeepSafeItems,
            identity: "test-scan",
            keepSafeRevision: "initial"
        )
        let refreshed = model.refreshingProtection(
            keepSafeItems: refreshedKeepSafeItems,
            keepSafeRevision: "refreshed"
        )
        return (snapshot(from: model), snapshot(from: refreshed))
    }

    private static func snapshot(from model: ResultsPresentationModel) -> ResultsProtectionSnapshot {
        ResultsProtectionSnapshot(
            scanDataObjectID: ObjectIdentifier(model.scanData),
            scanReuseToken: model.scanData.reuseToken,
            duplicateActionableTotal: model.duplicateActionableTotal,
            installerActionableTotal: model.installerActionableTotal,
            protectedItemCount: model.sortedKeepSafeItems.count,
            recommendationKinds: model.recommendations.map(\.kind),
            duplicateGroupIDs: model.duplicateGroups.map(\.id),
            duplicatePathIDs: model.duplicateGroups.flatMap { $0.paths.map(\.id) },
            installerRowIDs: model.installerRows.map(\.id),
            storageExplorerRootNodeIDs: model.routePresentation(for: .root).nodes.map(\.id)
        )
    }
}

private nonisolated extension ResultsPresentationModel {
    func routePresentation(for route: StorageExplorerRoute) -> StorageExplorerRoutePresentation {
        let normalizedRoute = normalizedStorageExplorerRoute(route)
        let nodes = storageExplorerNodes(for: normalizedRoute)
        let total = max(storageExplorerTotal(for: normalizedRoute, nodes: nodes), 1)
        return StorageExplorerRoutePresentation(
            route: normalizedRoute,
            nodes: nodes,
            total: total,
            residual: storageExplorerResidual(for: normalizedRoute, nodes: nodes, parentTotal: total),
            breadcrumbs: storageExplorerBreadcrumbItems(for: normalizedRoute)
        )
    }

    private static func relocationSupportSortRank(_ support: RelocationSupport) -> Int {
        switch support {
        case .officialSupported: return 0
        case .vendorToolRequired: return 1
        case .manualPossible: return 2
        case .reviewFirst: return 3
        case .unknown: return 4
        case .leaveInPlace: return 5
        }
    }

    private static func recommendedKeeper(in group: DuplicateGroup) -> String? {
        group.paths.max { lhs, rhs in
            isBetterKeeper(rhs, than: lhs)
        }
    }

    private static func isBetterKeeper(_ lhs: String, than rhs: String) -> Bool {
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

    private static func locationScore(for path: String) -> Int {
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

    private static func modificationDate(for path: String) -> TimeInterval {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
    }

    private static func sortedIdenticalContentGroups(
        _ groups: [DuplicateGroup]
    ) -> [IdenticalContentGroupPresentation] {
        groups
            .map { group in
                IdenticalContentGroupPresentation(
                    group: group,
                    classification: DifferentNameMatchClassifier.classify(
                        paths: group.paths,
                        fileSize: group.fileSize
                    ),
                    sharedParent: DifferentNameMatchClassifier.sharedParent(paths: group.paths)
                )
            }
            .sorted { lhs, rhs in
                let lhsCategory = identicalContentCategorySortRank(lhs.classification.kind)
                let rhsCategory = identicalContentCategorySortRank(rhs.classification.kind)
                if lhsCategory != rhsCategory { return lhsCategory < rhsCategory }
                if lhs.representedStorageBytes != rhs.representedStorageBytes {
                    return lhs.representedStorageBytes > rhs.representedStorageBytes
                }
                if lhs.largestFileBytes != rhs.largestFileBytes {
                    return lhs.largestFileBytes > rhs.largestFileBytes
                }
                return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
            }
    }

    private static func identicalContentCategorySortRank(_ kind: DifferentNameMatchKind) -> Int {
        switch kind {
        case .repeatedExportCopies: return 0
        case .possibleAlternateVersions: return 1
        case .possibleDuplicateTracks: return 2
        case .unclear: return 3
        case .likelyConsolidatedStems: return 4
        case .possibleSilentFiles: return 5
        }
    }

    private func normalizedStorageExplorerRoute(_ route: StorageExplorerRoute) -> StorageExplorerRoute {
        switch route {
        case .rawFolder(let path, _):
            return size(ofPath: path) > 0 ? route : .root
        default:
            return route
        }
    }

    private func storageExplorerNodes(for route: StorageExplorerRoute) -> [StorageExplorerNode] {
        switch route {
        case .root:
            return storageExplorerRootNodes()
        case .audioProduction:
            return audioProductionCategoryNodes()
        case .audioCategory(let category):
            return audioProductionContributorNodes(for: category)
        case .applications:
            return applicationExplorerNodes()
        case .personalFiles:
            return personalExplorerNodes()
        case .rawFolder(let path, let source):
            return rawFolderExplorerNodes(path: path, source: source)
        }
    }

    private func storageExplorerTotal(for route: StorageExplorerRoute, nodes: [StorageExplorerNode]) -> Int64 {
        switch route {
        case .root:
            return max(scanRootSize, nodes.reduce(Int64(0)) { $0 + $1.size })
        case .audioProduction, .audioCategory, .personalFiles:
            return nodes.reduce(Int64(0)) { $0 + $1.size }
        case .applications:
            return max(applicationsTotal, nodes.reduce(Int64(0)) { $0 + $1.size })
        case .rawFolder(let path, _):
            return size(ofPath: path)
        }
    }

    private func storageExplorerResidual(
        for route: StorageExplorerRoute,
        nodes: [StorageExplorerNode],
        parentTotal: Int64
    ) -> (title: String, size: Int64)? {
        let shownSum = nodes.reduce(Int64(0)) { $0 + $1.size }
        let residual = max(0, parentTotal - shownSum)
        guard residual >= 1_048_576 else { return nil }
        switch route {
        case .applications:
            return ("Other applications and supporting files", residual)
        default:
            return ("Files & smaller items here", residual)
        }
    }

    private func storageExplorerRootNodes() -> [StorageExplorerNode] {
        let audioTotal = audioProductionTotal
        let appsTotal = applicationsTotal
        let personalTotal = personalExplorerNodes().reduce(Int64(0)) { $0 + $1.size }
        let otherTotal = max(0, scanRootSize - audioTotal - appsTotal - personalTotal)

        var nodes: [StorageExplorerNode] = []
        if audioTotal > 0 {
            nodes.append(StorageExplorerNode(
                id: "audio-production",
                title: "Audio Production",
                subtitle: "Plugins, presets, sample libraries, audio support files, and production content.",
                path: nil,
                size: audioTotal,
                iconName: "waveform",
                color: .teal,
                route: .audioProduction
            ))
        }
        if appsTotal > 0 {
            nodes.append(StorageExplorerNode(
                id: "applications",
                title: "Applications",
                subtitle: "Installed apps and their storage usage.",
                path: nil,
                size: appsTotal,
                iconName: "app.fill",
                color: .brown,
                route: .applications
            ))
        }
        if personalTotal > 0 {
            nodes.append(StorageExplorerNode(
                id: "personal-files",
                title: "Personal Files",
                subtitle: "Projects, documents, downloads, desktop files, and other user-created content.",
                path: nil,
                size: personalTotal,
                iconName: "person.crop.square.fill",
                color: .cyan,
                route: .personalFiles
            ))
        }
        if otherTotal >= 1_048_576 {
            let source = StorageExplorerSource.otherMac(basePath: result.rootPath)
            nodes.append(StorageExplorerNode(
                id: "other-mac-storage",
                title: "Other Mac Storage",
                subtitle: "Scanned storage that does not fit the studio, app, or personal groups.",
                path: nil,
                size: otherTotal,
                iconName: "internaldrive.fill",
                color: .secondary,
                route: .rawFolder(path: result.rootPath, source: source)
            ))
        }
        return nodes
    }

    private func audioProductionCategoryNodes() -> [StorageExplorerNode] {
        let totals = Dictionary(grouping: audioContributors, by: \.category)
            .mapValues { $0.reduce(Int64(0)) { $0 + $1.size } }
        return StorageExplorerAudioCategory.allCases.compactMap { category in
            guard let total = totals[category], total > 0 else { return nil }
            return StorageExplorerNode(
                id: "audio-category-\(category.rawValue)",
                title: category.rawValue,
                subtitle: category.description,
                path: nil,
                size: total,
                iconName: category.iconName,
                color: audioCategoryColor(category),
                route: .audioCategory(category)
            )
        }
    }

    private func audioProductionContributorNodes(for category: StorageExplorerAudioCategory) -> [StorageExplorerNode] {
        audioContributors
            .filter { $0.category == category }
            .sorted { $0.size > $1.size }
            .map { contributor in
                let source = StorageExplorerSource.audio(category, basePath: contributor.path)
                return StorageExplorerNode(
                    id: contributor.id,
                    title: contributor.title,
                    subtitle: contributor.subtitle,
                    path: contributor.path,
                    size: contributor.size,
                    iconName: category.iconName,
                    color: audioCategoryColor(category),
                    route: hasChildren(contributor.path) ? .rawFolder(path: contributor.path, source: source) : nil
                )
            }
    }

    private func applicationExplorerNodes() -> [StorageExplorerNode] {
        let appItems = result.topFiles
            .filter { $0.category == .applications }
            .sorted { $0.size > $1.size }

        if !appItems.isEmpty {
            return appItems.map { item in
                let title = Self.applicationDisplayName(item.displayName)
                let classification = ApplicationClassifier.classify(displayName: title, path: item.url.path)
                return StorageExplorerNode(
                    id: "app-\(item.url.path)",
                    title: title,
                    subtitle: classification.displayTitle,
                    path: item.url.path,
                    size: item.size,
                    iconName: "app.fill",
                    color: classification.isAudioApplication ? .teal : .brown,
                    route: hasChildren(item.url.path)
                        ? .rawFolder(path: item.url.path, source: .applications(basePath: item.url.path))
                        : nil
                )
            }
        }

        return applicationFolderPaths.map { path in
            StorageExplorerNode(
                id: "app-folder-\(path)",
                title: Self.displayName(forPath: path),
                subtitle: "Applications folder",
                path: path,
                size: size(ofPath: path),
                iconName: "folder.fill",
                color: .brown,
                route: .rawFolder(path: path, source: .applications(basePath: path))
            )
        }
    }

    private func personalExplorerNodes() -> [StorageExplorerNode] {
        let home = normalizedPath(NSHomeDirectory())
        let audioPaths = audioContributors.map(\.path)
        let projectPaths = personalProjectPaths
        let homeApplications = "\(home)/Applications"

        let folderSpecs: [(StorageExplorerPersonalFolder, String, [String])] = [
            (.desktop, "\(home)/Desktop", audioPaths),
            (.documents, "\(home)/Documents", audioPaths + projectPaths),
            (.downloads, "\(home)/Downloads", audioPaths),
            (.music, "\(home)/Music", audioPaths + projectPaths),
            (.movies, "\(home)/Movies", audioPaths),
        ]

        var nodes: [StorageExplorerNode] = folderSpecs.compactMap { spec in
            let (folder, path, exclusions) = spec
            let size = adjustedFolderSize(path, excluding: exclusions)
            guard size > 0 else { return nil }
            return personalNode(folder: folder, path: path, size: size)
        }

        let projectTotal = totalSize(ofPaths: projectPaths, excluding: audioPaths)
        if projectTotal > 0 {
            let routePath = projectPaths.first ?? "\(home)/Projects"
            nodes.append(personalNode(folder: .projects, path: routePath, size: projectTotal))
        }

        let homeSize = size(ofPath: home)
        if homeSize > 0 {
            let namedRawPaths = folderSpecs.map { $0.1 } + projectPaths + [homeApplications]
            let excludedTotal = totalSize(ofPaths: namedRawPaths + audioPaths)
            let other = max(0, homeSize - excludedTotal)
            if other >= 1_048_576 {
                nodes.append(StorageExplorerNode(
                    id: "personal-other",
                    title: StorageExplorerPersonalFolder.other.rawValue,
                    subtitle: StorageExplorerPersonalFolder.other.description,
                    path: home,
                    size: other,
                    iconName: "folder.fill",
                    color: .secondary,
                    route: .rawFolder(path: home, source: .personal(.other, basePath: home))
                ))
            }
        }

        return nodes
    }

    private func rawFolderExplorerNodes(path: String, source: StorageExplorerSource) -> [StorageExplorerNode] {
        let parentTotal = max(size(ofPath: path), 1)
        return (result.folderChildren[normalizedPath(path)] ?? [])
            .map { childPath in
                let childSize = size(ofPath: childPath)
                let proportion = Double(childSize) / Double(parentTotal)
                let subtitle = proportion >= 0.01
                    ? "\(Int((proportion * 100).rounded()))% of this level"
                    : "Less than 1% of this level"
                return StorageExplorerNode(
                    id: "raw-\(childPath)",
                    title: Self.displayName(forPath: childPath),
                    subtitle: subtitle,
                    path: childPath,
                    size: childSize,
                    iconName: "folder.fill",
                    color: .teal,
                    route: hasChildren(childPath) ? .rawFolder(path: childPath, source: source) : nil
                )
            }
            .sorted { lhs, rhs in
                if lhs.size != rhs.size { return lhs.size > rhs.size }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    private func personalNode(folder: StorageExplorerPersonalFolder, path: String, size: Int64) -> StorageExplorerNode {
        StorageExplorerNode(
            id: "personal-\(folder.rawValue)-\(path)",
            title: folder.rawValue,
            subtitle: folder.description,
            path: path,
            size: size,
            iconName: folder == .downloads ? "arrow.down.circle.fill" : "folder.fill",
            color: folder == .downloads ? .orange : .cyan,
            route: .rawFolder(path: path, source: .personal(folder, basePath: path))
        )
    }

    private func storageExplorerBreadcrumbItems(for route: StorageExplorerRoute) -> [StorageExplorerBreadcrumb] {
        var crumbs = [StorageExplorerBreadcrumb(id: "root", title: "Storage Explorer", route: .root)]
        switch route {
        case .root:
            return crumbs
        case .audioProduction:
            crumbs.append(StorageExplorerBreadcrumb(id: "audio-production", title: "Audio Production", route: .audioProduction))
        case .audioCategory(let category):
            crumbs.append(StorageExplorerBreadcrumb(id: "audio-production", title: "Audio Production", route: .audioProduction))
            crumbs.append(StorageExplorerBreadcrumb(id: "audio-\(category.rawValue)", title: category.rawValue, route: route))
        case .applications:
            crumbs.append(StorageExplorerBreadcrumb(id: "applications", title: "Applications", route: .applications))
        case .personalFiles:
            crumbs.append(StorageExplorerBreadcrumb(id: "personal-files", title: "Personal Files", route: .personalFiles))
        case .rawFolder(let path, let source):
            appendSourceBreadcrumb(source, crumbs: &crumbs)
            appendRawPathBreadcrumbs(path: path, source: source, crumbs: &crumbs)
        }
        return crumbs
    }

    private func appendSourceBreadcrumb(_ source: StorageExplorerSource, crumbs: inout [StorageExplorerBreadcrumb]) {
        switch source {
        case .audio(let category, _):
            crumbs.append(StorageExplorerBreadcrumb(id: "audio-production", title: "Audio Production", route: .audioProduction))
            crumbs.append(StorageExplorerBreadcrumb(id: "audio-\(category.rawValue)", title: category.rawValue, route: .audioCategory(category)))
        case .applications:
            crumbs.append(StorageExplorerBreadcrumb(id: "applications", title: "Applications", route: .applications))
        case .personal(let folder, _):
            crumbs.append(StorageExplorerBreadcrumb(id: "personal-files", title: "Personal Files", route: .personalFiles))
            if folder != .other {
                crumbs.append(StorageExplorerBreadcrumb(id: "personal-\(folder.rawValue)", title: folder.rawValue, route: .rawFolder(path: sourceBasePath(source), source: source)))
            }
        case .otherMac:
            crumbs.append(StorageExplorerBreadcrumb(id: "other-mac", title: "Other Mac Storage", route: .rawFolder(path: sourceBasePath(source), source: source)))
        }
    }

    private func appendRawPathBreadcrumbs(
        path: String,
        source: StorageExplorerSource,
        crumbs: inout [StorageExplorerBreadcrumb]
    ) {
        let base = sourceBasePath(source)
        let baseTitle = sourceBaseTitle(source)
        let currentPath = normalizedPath(path)
        let normalizedBase = normalizedPath(base)
        let baseAlreadyShown = sourceBaseIsAlreadyShown(source)

        guard currentPath == normalizedBase || pathContains(normalizedBase, candidate: currentPath) else {
            crumbs.append(StorageExplorerBreadcrumb(id: currentPath, title: Self.displayName(forPath: currentPath), route: .rawFolder(path: currentPath, source: source)))
            return
        }

        if !baseAlreadyShown {
            crumbs.append(StorageExplorerBreadcrumb(id: normalizedBase, title: baseTitle, route: .rawFolder(path: normalizedBase, source: source)))
        }

        guard currentPath != normalizedBase else { return }
        let relative = normalizedBase == "/"
            ? String(currentPath.dropFirst(1))
            : String(currentPath.dropFirst(normalizedBase.count + 1))
        var accumulated = normalizedBase
        for component in relative.split(separator: "/").map(String.init) {
            accumulated = accumulated == "/" ? "/\(component)" : "\(accumulated)/\(component)"
            crumbs.append(StorageExplorerBreadcrumb(
                id: accumulated,
                title: component,
                route: .rawFolder(path: accumulated, source: source)
            ))
        }
    }

    private var scanRootSize: Int64 {
        max(result.totalSize, size(ofPath: result.rootPath))
    }

    private var audioProductionTotal: Int64 {
        audioContributors.reduce(Int64(0)) { $0 + $1.size }
    }

    private var applicationsTotal: Int64 {
        let folderTotal = totalSize(ofPaths: applicationFolderPaths)
        let appItemsTotal = result.topFiles
            .filter { $0.category == .applications }
            .reduce(Int64(0)) { $0 + $1.size }
        return max(folderTotal, appItemsTotal)
    }

    private var applicationFolderPaths: [String] {
        let homeApplications = "\(normalizedPath(NSHomeDirectory()))/Applications"
        let candidates = ["/Applications", homeApplications, result.rootPath]
        return candidates
            .map { Self.normalizedPath($0) }
            .filter { path in
                size(ofPath: path) > 0
                    && (path.hasSuffix("/Applications") || path == "/Applications")
            }
            .removingDuplicates()
    }

    private var personalProjectPaths: [String] {
        let home = normalizedPath(NSHomeDirectory())
        let candidates = [
            "\(home)/Projects",
            "\(home)/Sessions",
            "\(home)/Documents/Projects",
            "\(home)/Documents/Sessions",
            "\(home)/Music/Projects",
            "\(home)/Music/Sessions",
        ]
        return candidates
            .map { Self.normalizedPath($0) }
            .filter { size(ofPath: $0) > 0 }
            .removingDuplicates()
    }

    private static func audioProductionContributors(in result: ScanResult) -> [StorageExplorerContributor] {
        var timer = ResultsPerformanceTimer()
        var candidates: [StorageExplorerContributor] = []

        for item in result.audioSystemData.items {
            let path = item.path
            candidates.append(StorageExplorerContributor(
                id: "audio-system-\(path)",
                title: item.friendlyName,
                subtitle: item.category.rawValue,
                path: path,
                size: item.size,
                category: audioCategory(for: item.category),
                priority: 100
            ))
        }
        timer.mark("Audio system items")

        for (path, size) in result.folderSizes where size >= 1_048_576 {
            let lower = path.lowercased()
            guard let category = audioCategory(forNormalizedLowerPath: lower),
                  AudioSystemDataClassifier.classify(path: path) == nil else { continue }
            candidates.append(StorageExplorerContributor(
                id: "audio-folder-\(path)",
                title: displayName(forPath: path),
                subtitle: category.rawValue,
                path: path,
                size: size,
                category: category,
                priority: 70
            ))
        }
        timer.mark("Folder candidate scan")

        for item in result.topFiles where item.category != .applications && isAudioAsset(item) {
            let path = item.url.path
            guard let category = audioCategory(for: item) else { continue }
            candidates.append(StorageExplorerContributor(
                id: "audio-item-\(path)",
                title: item.displayName,
                subtitle: item.category?.displayName ?? category.rawValue,
                path: path,
                size: item.size,
                category: category,
                priority: 40
            ))
        }
        timer.mark("Top-file contributors")

        let contributors = nonOverlappingContributors(candidates)
        timer.mark("Overlap pruning")
        timer.finish("Storage Explorer preparation")
        return contributors
    }

    private static func nonOverlappingContributors(
        _ candidates: [StorageExplorerContributor]
    ) -> [StorageExplorerContributor] {
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            if lhs.size != rhs.size { return lhs.size > rhs.size }
            return lhs.path < rhs.path
        }

        var selected: [StorageExplorerContributor] = []
        for candidate in sorted {
            if selected.contains(where: { pathsOverlapNormalized($0.path, candidate.path) }) { continue }
            selected.append(candidate)
        }
        return selected
    }

    private static func archiveCandidateTotal(in result: ScanResult) -> Int64 {
        nonOverlappingPathSummaries(paths: projectFolderPaths(in: result), in: result)
            .reduce(Int64(0)) { $0 + $1.size }
    }

    private static func relocationCandidateSummaries(
        in result: ScanResult,
        audioRows: [AudioFolderPresentationRow]
    ) -> [RelocationCandidateSummary] {
        let audioSystemPaths = audioRows.map(\.item.path)
        let libraryFolderPaths = result.folderSizes.keys.filter(isLikelyRelocatableLibraryPath)
        return nonOverlappingPathSummaries(
            paths: audioSystemPaths + libraryFolderPaths,
            in: result
        )
    }

    private static func projectFolderPaths(in result: ScanResult) -> [String] {
        let home = normalizedPath(NSHomeDirectory())
        let knownPaths = [
            "\(home)/Projects",
            "\(home)/Sessions",
            "\(home)/Documents/Projects",
            "\(home)/Documents/Sessions",
            "\(home)/Music/Projects",
            "\(home)/Music/Sessions",
        ]
        let detectedPaths = result.folderSizes.keys.filter { path in
            let lower = path.lowercased()
            guard !lower.contains("/library/application support/"),
                  !lower.contains("/library/audio/")
            else { return false }
            return lower.contains("/projects/") || lower.contains("/sessions/")
                || lower.contains("/daw projects/") || lower.contains("/logic projects/")
        }
        return knownPaths + detectedPaths
    }

    private static func nonOverlappingPathSummaries(
        paths: [String],
        in result: ScanResult
    ) -> [RelocationCandidateSummary] {
        let sorted = paths
            .map(normalizedPath)
            .filter { size(ofPath: $0, in: result) > 0 }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count < rhs.count }
                return lhs < rhs
            }

        var selected: [String] = []
        for path in sorted {
            if selected.contains(where: { pathsOverlapNormalized($0, path) }) { continue }
            selected.append(path)
        }

        return selected.map {
            RelocationCandidateSummary(path: $0, size: size(ofPath: $0, in: result))
        }
    }

    private static func size(ofPath path: String, in result: ScanResult) -> Int64 {
        if let size = result.folderSizes[path] { return size }
        let normalized = normalizedPath(path)
        if let size = result.folderSizes[normalized] { return size }
        if normalized == result.rootPath || normalized == normalizedPath(result.rootPath) {
            return result.totalSize
        }
        return 0
    }

    private static func largestAudioAssets(in result: ScanResult) -> [SizedItem] {
        result.topFiles
            .filter { Self.isAudioAsset($0) }
            .sorted { lhs, rhs in
                if lhs.size != rhs.size { return lhs.size > rhs.size }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    private static func otherLargeApplications(in result: ScanResult) -> [SizedItem] {
        result.topFiles
            .filter { item in
                guard item.category == .applications else { return false }
                return !isAudioApplication(item)
            }
            .sorted { $0.size > $1.size }
    }

    private static func isLikelyRelocatableLibraryPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        guard lower.contains("/sample") || lower.contains("/library") || lower.contains("/libraries")
            || lower.contains("/content") || lower.contains("/expansion") || lower.contains("/loops")
            || lower.contains("/steam") || lower.contains("/kontakt") || lower.contains("/toontrack")
        else { return false }

        return relocatableVendorMarkers.contains { lower.contains($0) }
            || lower.contains("/sample libraries/")
            || lower.contains("/sample library/")
    }

    private static func isAudioAsset(_ item: SizedItem) -> Bool {
        if item.category == .applications { return isAudioApplication(item) }
        guard let category = item.category else { return isAudioRelatedPath(item.url.path) }
        switch category {
        case .projects, .plugins, .pluginData, .sampleLibraries, .audioFiles, .installers, .archives:
            return true
        case .media, .other:
            return isAudioRelatedPath(item.url.path)
        case .applications:
            return isAudioApplication(item)
        }
    }

    private static func isAudioApplication(_ item: SizedItem) -> Bool {
        guard item.category == .applications else { return false }
        return ApplicationClassifier.classify(
            displayName: applicationDisplayName(item.displayName),
            path: item.url.path
        ).isAudioApplication
    }

    private static func audioCategory(for category: AudioSystemDataCategory) -> StorageExplorerAudioCategory {
        switch category {
        case .plugins: return .plugins
        case .presets: return .presets
        case .impulseResponses: return .impulseResponses
        case .pluginContent: return .pluginContent
        case .cachesDownloads: return .cachesDownloads
        }
    }

    private static func audioCategory(for item: SizedItem) -> StorageExplorerAudioCategory? {
        switch item.category {
        case .projects:
            return .audioProjects
        case .plugins:
            return .plugins
        case .pluginData:
            return .pluginContent
        case .sampleLibraries:
            return .sampleLibraries
        case .audioFiles:
            return .audioFiles
        case .installers, .archives:
            return audioCategory(forFolderPath: item.url.path) ?? .cachesDownloads
        case .media, .other, nil:
            return audioCategory(forFolderPath: item.url.path) ?? .otherAudioStorage
        case .applications:
            return nil
        }
    }

    private static func audioCategory(forFolderPath path: String) -> StorageExplorerAudioCategory? {
        audioCategory(forNormalizedLowerPath: normalizedPath(path).lowercased())
    }

    private static func audioCategory(forNormalizedLowerPath lower: String) -> StorageExplorerAudioCategory? {
        if lower.contains("/library/audio/plug-ins/") { return .plugins }
        if lower.contains("/library/audio/presets/") { return .presets }
        if lower.contains("/library/audio/impulse responses/") { return .impulseResponses }
        if lower.contains("/library/application support/") && isAudioRelatedPath(lower) { return .pluginContent }
        if lower.contains("/audio/") && lower.contains("/application support/") { return .pluginContent }
        if lower.contains("/packdownloads/") || lower.contains("/library/caches/") && isAudioRelatedPath(lower) {
            return .cachesDownloads
        }
        if lower.contains("/sample libraries/") || lower.contains("/sample library/")
            || lower.contains("/samples/") || lower.contains("/loops/")
            || lower.contains("/apple loops/") || lower.contains("sample librar") {
            return .sampleLibraries
        }
        if lower.contains("/sessions/") || lower.contains("/session files/")
            || lower.contains("/daw projects/") || lower.contains("/logic projects/") {
            return .audioProjects
        }
        if lower.contains("/bounces/") || lower.contains("/exports/")
            || lower.contains("/stems/") || lower.contains("/mixes/")
            || lower.contains("/masters/") || lower.contains("/renders/") {
            return .audioFiles
        }
        if isAudioRelatedPath(lower) { return .otherAudioStorage }
        return nil
    }

    private func adjustedFolderSize(_ path: String, excluding excludedPaths: [String]) -> Int64 {
        let base = size(ofPath: path)
        guard base > 0 else { return 0 }
        let excluded = totalSize(ofPaths: excludedPaths.filter { pathContains(path, candidate: $0) })
        return max(0, base - excluded)
    }

    private func totalSize(ofPaths paths: [String], excluding excludedPaths: [String] = []) -> Int64 {
        let normalized = paths
            .map { Self.normalizedPath($0) }
            .filter { size(ofPath: $0) > 0 }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count < rhs.count }
                return lhs < rhs
            }

        var selected: [String] = []
        for path in normalized {
            if selected.contains(where: { Self.pathsOverlap($0, path) }) { continue }
            selected.append(path)
        }

        let exclusions = excludedPaths.map { Self.normalizedPath($0) }
        return selected.reduce(Int64(0)) { total, path in
            let size = size(ofPath: path)
            let excluded = totalSize(ofPaths: exclusions.filter { pathContains(path, candidate: $0) })
            return total + max(0, size - excluded)
        }
    }

    private func size(ofPath path: String) -> Int64 {
        let normalized = normalizedPath(path)
        if let size = result.folderSizes[normalized] { return size }
        if normalized == normalizedPath(result.rootPath) { return result.totalSize }
        return 0
    }

    private func hasChildren(_ path: String) -> Bool {
        !(result.folderChildren[normalizedPath(path)]?.isEmpty ?? true)
    }

    private static func sourceBasePath(_ source: StorageExplorerSource) -> String {
        switch source {
        case .audio(_, let basePath), .applications(let basePath), .personal(_, let basePath), .otherMac(let basePath):
            return basePath
        }
    }

    private func sourceBasePath(_ source: StorageExplorerSource) -> String {
        Self.sourceBasePath(source)
    }

    private func sourceBaseTitle(_ source: StorageExplorerSource) -> String {
        switch source {
        case .audio(let category, _): return category.rawValue
        case .applications: return "Applications"
        case .personal(let folder, _): return folder.rawValue
        case .otherMac: return "Other Mac Storage"
        }
    }

    private func sourceBaseIsAlreadyShown(_ source: StorageExplorerSource) -> Bool {
        switch source {
        case .audio, .applications, .otherMac:
            return true
        case .personal(let folder, _):
            return folder != .other
        }
    }

    private static func audioCategoryColor(_ category: StorageExplorerAudioCategory) -> Color {
        switch category {
        case .plugins: return .indigo
        case .pluginContent: return .teal
        case .presets: return .blue
        case .sampleLibraries: return .mint
        case .impulseResponses: return .cyan
        case .audioProjects: return .purple
        case .audioFiles: return .cyan
        case .cachesDownloads: return .orange
        case .otherAudioStorage: return .gray
        }
    }

    private func audioCategoryColor(_ category: StorageExplorerAudioCategory) -> Color {
        Self.audioCategoryColor(category)
    }

    private static func applicationDisplayName(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private static func displayName(forPath path: String) -> String {
        let last = URL(fileURLWithPath: path).lastPathComponent
        return last.isEmpty ? path : last
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func normalizedPath(_ path: String) -> String {
        Self.normalizedPath(path)
    }

    private static func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        pathContains(lhs, candidate: rhs) || pathContains(rhs, candidate: lhs)
    }

    private static func pathsOverlapNormalized(_ lhs: String, _ rhs: String) -> Bool {
        pathContainsNormalized(lhs, candidate: rhs) || pathContainsNormalized(rhs, candidate: lhs)
    }

    private static func pathContains(_ path: String, candidate: String) -> Bool {
        let parent = normalizedPath(path)
        let child = normalizedPath(candidate)
        if parent == "/" { return child.hasPrefix("/") }
        return parent == child || child.hasPrefix(parent + "/")
    }

    private static func pathContainsNormalized(_ parent: String, candidate child: String) -> Bool {
        if parent == "/" { return child.hasPrefix("/") }
        return parent == child || child.hasPrefix(parent + "/")
    }

    private func pathContains(_ path: String, candidate: String) -> Bool {
        Self.pathContains(path, candidate: candidate)
    }

    private static func isAudioRelatedPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return audioPathMarkers.contains { lower.contains($0) }
    }

    private static let audioPathMarkers = [
        "ableton", "logic", "garageband", "pro tools", "avid", "cubase", "nuendo",
        "studio one", "fl studio", "reaper", "reason", "kontakt", "native instruments",
        "xln audio", "addictive drums", "addictive keys", "slate digital", "waves",
        "fabfilter", "soundtoys", "universal audio", "uad", "plugin alliance",
        "izotope", "arturia", "spitfire", "eastwest", "toontrack", "superior drummer",
        "ezdrummer", "omnisphere", "keyscape", "spectrasonics", "output", "uvi",
        "sample librar", "/samples/", "/loops/", "/stems/", "/bounces/", "/mixes/",
        "/masters/", "/renders/", "/sessions/", "/daw projects/", "/logic projects/",
    ]

    private static let relocationGuidanceKinds: Set<AudioFolderGuidanceKind> = [
        .contentLibrary,
        .sampleLibrary,
        .impulseResponseLibrary,
    ]

    private static let leaveInPlaceCategories: Set<AudioSystemDataCategory> = [
        .plugins,
        .presets,
        .pluginContent,
    ]

    private static let relocatableVendorMarkers = [
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

private struct ActionToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

private nonisolated struct ResultsPerformanceTimer {
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

private nonisolated func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

private nonisolated struct KeepSafeIndex {
    let exactItemsByPath: [String: KeepSafeItem]
    let folderPrefixes: [(prefix: String, item: KeepSafeItem)]

    init(items: [KeepSafeItem]) {
        var exact: [String: KeepSafeItem] = [:]
        var folders: [(String, KeepSafeItem)] = []

        for item in items {
            let original = Self.normalize(item.originalPath)
            let resolved = Self.normalize(item.resolvedPath)
            exact[original] = item
            exact[resolved] = item
            if item.itemType == .folder {
                folders.append((original, item))
                folders.append((resolved, item))
            }
        }

        var seenFolders = Set<String>()
        exactItemsByPath = exact
        folderPrefixes = folders
            .filter { seenFolders.insert($0.0).inserted }
            .map { (prefix: $0.0, item: $0.1) }
            .sorted { $0.prefix.count > $1.prefix.count }
    }

    func item(for path: String) -> KeepSafeItem? {
        let normalized = Self.normalize(path)
        return item(forNormalizedPath: normalized)
    }

    func item(forNormalizedPath normalized: String) -> KeepSafeItem? {
        if let item = exactItemsByPath[normalized] { return item }
        return folderPrefixes.first { entry in
            normalized == entry.prefix || normalized.hasPrefix(entry.prefix + "/")
        }?.item
    }

    func isProtected(_ path: String) -> Bool {
        item(for: path) != nil
    }

    private static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

private enum ResultSectionID: Hashable {
    case summary
    case recommendations
    case categories
    case audioSystemData
    case audioSystemFolder(String)
    case keepSafe
    case duplicates
    case installers
    case staging
    case storageExplorer
    case largestAudioAssets
}

@MainActor
final class PathSelectionState: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    private(set) var selectedPaths: Set<String> = []
    private(set) var selectedCount = 0
    private(set) var selectedBytes: Int64 = 0

    private var stageablePaths: Set<String> = []
    private var byteSizes: [String: Int64] = [:]

    func configure(
        stageablePaths: Set<String>,
        byteSizes: [String: Int64],
        blockedPathKeys: Set<String> = []
    ) {
        self.stageablePaths = stageablePaths
        self.byteSizes = byteSizes
        prune(blockedPathKeys: blockedPathKeys)
    }

    func setSelection(_ paths: Set<String>, blockedPathKeys: Set<String> = []) {
        let filtered = Set(paths.lazy.filter { self.isStageable($0, blockedPathKeys: blockedPathKeys) })
        replaceSelection(with: filtered)
    }

    func setSelected(_ path: String, _ isSelected: Bool) {
        if isSelected {
            insert(path)
        } else {
            remove(path)
        }
    }

    func insert(_ path: String) {
        guard stageablePaths.contains(path), !selectedPaths.contains(path) else { return }
        objectWillChange.send()
        selectedPaths.insert(path)
        selectedCount += 1
        selectedBytes += byteSizes[path] ?? 0
    }

    func remove(_ path: String) {
        guard selectedPaths.contains(path) else { return }
        objectWillChange.send()
        selectedPaths.remove(path)
        selectedCount -= 1
        selectedBytes -= byteSizes[path] ?? 0
    }

    func subtract(_ paths: Set<String>) {
        let removed = selectedPaths.intersection(paths)
        guard !removed.isEmpty else { return }
        objectWillChange.send()
        selectedPaths.subtract(removed)
        selectedCount = selectedPaths.count
        selectedBytes -= bytes(for: removed)
    }

    func removeAll() {
        guard !selectedPaths.isEmpty || selectedCount != 0 || selectedBytes != 0 else { return }
        objectWillChange.send()
        selectedPaths.removeAll()
        selectedCount = 0
        selectedBytes = 0
    }

    func contains(_ path: String) -> Bool {
        selectedPaths.contains(path)
    }

    func prune(blockedPathKeys: Set<String> = []) {
        let filtered = Set(selectedPaths.lazy.filter { self.isStageable($0, blockedPathKeys: blockedPathKeys) })
        replaceSelection(with: filtered)
    }

    private func isStageable(_ path: String, blockedPathKeys: Set<String>) -> Bool {
        guard stageablePaths.contains(path) else { return false }
        guard !blockedPathKeys.isEmpty else { return true }
        return !blockedPathKeys.contains(KeepSafeStore.standardizedPath(path))
    }

    private func replaceSelection(with paths: Set<String>) {
        let newCount = paths.count
        let newBytes = bytes(for: paths)
        guard selectedPaths != paths || selectedCount != newCount || selectedBytes != newBytes else { return }
        objectWillChange.send()
        selectedPaths = paths
        selectedCount = newCount
        selectedBytes = newBytes
    }

    private func bytes(for paths: Set<String>) -> Int64 {
        paths.reduce(Int64(0)) { $0 + (byteSizes[$1] ?? 0) }
    }
}

private struct PointerCursorModifier: ViewModifier {
    let isActive: Bool
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content.onHover { hovering in
            guard isActive else { return }
            if hovering {
                NSCursor.pointingHand.push()
                isHovering = true
            } else if isHovering {
                NSCursor.pop()
                isHovering = false
            }
        }
    }
}

private struct InteractiveHoverModifier: ViewModifier {
    let isActive: Bool
    let isSelected: Bool
    let cornerRadius: CGFloat
    let tint: Color
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backgroundColor)
            )
            .onHover { hovering in
                guard isActive else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
            .pointerCursor(isActive)
    }

    private var backgroundColor: Color {
        if isSelected { return tint.opacity(0.14) }
        if isActive && isHovering { return tint.opacity(0.09) }
        return .clear
    }
}

private extension View {
    func pointerCursor(_ isActive: Bool = true) -> some View {
        modifier(PointerCursorModifier(isActive: isActive))
    }

    func interactiveHover(
        isActive: Bool = true,
        isSelected: Bool = false,
        cornerRadius: CGFloat = 7,
        tint: Color = .teal
    ) -> some View {
        modifier(InteractiveHoverModifier(
            isActive: isActive,
            isSelected: isSelected,
            cornerRadius: cornerRadius,
            tint: tint
        ))
    }

    func interactiveRow(
        isActive: Bool = true,
        isSelected: Bool = false,
        tint: Color = .teal
    ) -> some View {
        padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .interactiveHover(isActive: isActive, isSelected: isSelected, tint: tint)
    }

    func iconActionControl(
        isActive: Bool = true,
        isSelected: Bool = false,
        help text: String
    ) -> some View {
        frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .interactiveHover(isActive: isActive, isSelected: isSelected, cornerRadius: 14, tint: .teal)
            .help(text)
            .accessibilityLabel(Text(text))
    }

    func subtleTextAction(help text: String? = nil) -> some View {
        padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .interactiveHover(cornerRadius: 6, tint: .teal)
            .help(text ?? "")
    }
}

private struct DuplicateResultsSection<GroupRow: View, IdenticalRow: View>: View {
    let hasDuplicateGroups: Bool
    let duplicateGroups: [DuplicateGroupPresentationRow]
    let identicalContentGroups: [IdenticalContentGroupPresentation]
    let actionableReclaimable: Int64
    let selection: PathSelectionState
    @Binding var expandedResultListIDs: Set<String>
    let isMovingToStaging: Bool
    let selectAll: () -> Void
    let deselectAll: () -> Void
    let moveSelected: () -> Void
    let groupRow: (DuplicateGroupPresentationRow) -> GroupRow
    let identicalRow: (IdenticalContentGroupPresentation) -> IdenticalRow
    let human: (Int64) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Duplicate files").font(.headline)
                    Spacer()
                    if actionableReclaimable > 0 {
                        Text("\(human(actionableReclaimable)) reclaimable")
                            .font(.callout.weight(.semibold)).foregroundStyle(.teal)
                    }
                }
                if !hasDuplicateGroups {
                    Text("No confident duplicates over 1 MB (same name and identical content).")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Same filename and byte-for-byte identical. SessionSweep preselects likely redundant copies, but you can change any checkbox before moving files.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    DuplicateSelectionControls(
                        selection: selection,
                        isMovingToStaging: isMovingToStaging,
                        selectAll: selectAll,
                        deselectAll: deselectAll,
                        moveSelected: moveSelected,
                        human: human
                    )

                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(duplicateGroups) { groupRow($0) }
                    }
                }
            }

            if !identicalContentGroups.isEmpty {
                let listID = "identical-content-groups"
                let compactCount = 10
                let visibleGroups = visibleItems(
                    identicalContentGroups,
                    compactCount: compactCount,
                    listID: listID
                )
                let hiddenCount = max(0, identicalContentGroups.count - compactCount)

                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Label("Identical content, different names", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline).foregroundStyle(.orange)
                    Text("These files are byte-for-byte identical but have different names. SessionSweep adds audio-aware context, but this section is informational only and is not counted as reclaimable cleanup.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visibleGroups) { identicalRow($0) }
                    }
                    expandableToggle(
                        listID: listID,
                        hiddenCount: hiddenCount,
                        itemSingular: "group",
                        itemPlural: "groups",
                        expandedLabel: "Hide additional groups",
                        accessibilityCollapsedLabel: "Show \(hiddenCount) more identical-content group\(hiddenCount == 1 ? "" : "s")",
                        accessibilityExpandedLabel: "Hide additional identical-content groups"
                    )
                }
            }
        }
    }

    private func visibleItems<Item>(
        _ items: [Item],
        compactCount: Int,
        listID: String
    ) -> [Item] {
        guard compactCount > 0,
              items.count > compactCount,
              !expandedResultListIDs.contains(listID)
        else { return items }
        return Array(items.prefix(compactCount))
    }

    @ViewBuilder
    private func expandableToggle(
        listID: String,
        hiddenCount: Int,
        itemSingular: String,
        itemPlural: String,
        expandedLabel: String,
        accessibilityCollapsedLabel: String,
        accessibilityExpandedLabel: String
    ) -> some View {
        if hiddenCount > 0 {
            let isExpanded = expandedResultListIDs.contains(listID)
            let collapsedTitle = "Show \(hiddenCount) more \(hiddenCount == 1 ? itemSingular : itemPlural)"
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if isExpanded {
                        expandedResultListIDs.remove(listID)
                    } else {
                        expandedResultListIDs.insert(listID)
                    }
                }
            } label: {
                Label(isExpanded ? expandedLabel : collapsedTitle,
                      systemImage: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.teal)
            .interactiveHover(isSelected: isExpanded, cornerRadius: 7, tint: .teal)
            .pointerCursor()
            .help(isExpanded ? expandedLabel : collapsedTitle)
            .accessibilityLabel(isExpanded ? accessibilityExpandedLabel : accessibilityCollapsedLabel)
        }
    }
}

private struct DuplicateSelectionControls: View {
    @ObservedObject var selection: PathSelectionState
    let isMovingToStaging: Bool
    let selectAll: () -> Void
    let deselectAll: () -> Void
    let moveSelected: () -> Void
    let human: (Int64) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button("Select All") { selectAll() }
                    .buttonStyle(.borderless)
                    .subtleTextAction(help: "Select all duplicate files")
                Button("Deselect All") { deselectAll() }
                    .buttonStyle(.borderless)
                    .subtleTextAction(help: "Clear duplicate file selection")
                Spacer()
            }

            if selection.selectedCount > 0 {
                HStack(spacing: 10) {
                    Button { moveSelected() } label: {
                        Label(isMovingToStaging ? "Moving..." : "Move to Staging",
                              systemImage: isMovingToStaging ? "hourglass" : "tray.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isMovingToStaging)
                    .pointerCursor(!isMovingToStaging)
                    .help("Move selected duplicate files to SessionSweep Staging")

                    Text("\(selection.selectedCount) file\(selection.selectedCount == 1 ? "" : "s") selected · \(human(selection.selectedBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct DuplicatePathResultRow<KeepSafeControl: View>: View {
    let row: DuplicatePathPresentationRow
    let isBusy: Bool
    @ObservedObject var selection: PathSelectionState
    let recommendationLabel: (Bool, DuplicateSafetyClassification) -> String
    let recommendationDescription: (Bool, DuplicateSafetyClassification) -> String
    let keepSafeControl: () -> KeepSafeControl
    let human: (Int64) -> String

    var body: some View {
        let path = row.path
        let safetyClassification = row.safetyClassification
        let isStageable = row.isStageable && !isBusy
        let isSelected = selection.contains(path) && isStageable

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle("", isOn: Binding(
                get: { selection.contains(path) && isStageable },
                set: { selection.setSelected(path, $0 && isStageable) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(!isStageable)

            VStack(alignment: .leading, spacing: 2) {
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(recommendationLabel(row.isKeeper, safetyClassification))
                    .font(.caption2)
                    .foregroundStyle((row.isKeeper || row.isNeverRecommend || row.isKeepSafe) ? Color.secondary : Color.teal)
                    .help(recommendationDescription(row.isKeeper, safetyClassification))
            }
            Spacer()
            Text(human(row.fileSize))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            keepSafeControl()
        }
        .padding(.vertical, 2)
    }
}

private struct InstallerResultsSection<RowContent: View>: View {
    let rows: [InstallerPresentationRow]
    let total: Int64
    let selection: PathSelectionState
    let isMovingInstallersToStaging: Bool
    let selectAll: () -> Void
    let deselectAll: () -> Void
    let moveSelected: () -> Void
    let rowContent: (InstallerPresentationRow) -> RowContent
    let human: (Int64) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Installers").font(.headline)
                Spacer()
                if total > 0 {
                    Text("\(human(total)) reclaimable")
                        .font(.callout.weight(.semibold)).foregroundStyle(.teal)
                }
            }

            if rows.isEmpty {
                Text("No leftover app installers found.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("App installers (.dmg, .pkg) left over after setup. Once an app is in Applications, its installer is safe to remove. SessionSweep flags installers whose app is already installed.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                InstallerSelectionControls(
                    selection: selection,
                    isMovingInstallersToStaging: isMovingInstallersToStaging,
                    selectAll: selectAll,
                    deselectAll: deselectAll,
                    moveSelected: moveSelected,
                    human: human
                )

                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { rowContent($0) }
                }
            }
        }
    }
}

private struct InstallerSelectionControls: View {
    @ObservedObject var selection: PathSelectionState
    let isMovingInstallersToStaging: Bool
    let selectAll: () -> Void
    let deselectAll: () -> Void
    let moveSelected: () -> Void
    let human: (Int64) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button("Select All") { selectAll() }
                    .buttonStyle(.borderless)
                    .subtleTextAction(help: "Select all stageable installers")
                Button("Deselect All") { deselectAll() }
                    .buttonStyle(.borderless)
                    .subtleTextAction(help: "Clear installer selection")
                Spacer()
            }

            if selection.selectedCount > 0 {
                HStack(spacing: 10) {
                    Button { moveSelected() } label: {
                        Label(isMovingInstallersToStaging ? "Moving..." : "Move to Staging",
                              systemImage: isMovingInstallersToStaging ? "hourglass" : "tray.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isMovingInstallersToStaging)
                    .pointerCursor(!isMovingInstallersToStaging)
                    .help("Move selected installers to SessionSweep Staging")

                    Text("\(selection.selectedCount) file\(selection.selectedCount == 1 ? "" : "s") selected · \(human(selection.selectedBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct InstallerResultRow<KeepSafeControl: View>: View {
    let row: InstallerPresentationRow
    let isBusy: Bool
    @ObservedObject var selection: PathSelectionState
    let keepSafeControl: () -> KeepSafeControl
    let human: (Int64) -> String

    var body: some View {
        let item = row.item
        let path = row.path
        let isStageable = row.isStageable && !isBusy
        let isSelected = selection.contains(path) && isStageable
        let alreadyInstalled = row.alreadyInstalled

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle("", isOn: Binding(
                get: { selection.contains(path) && isStageable },
                set: { selection.setSelected(path, $0 && isStageable) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(!isStageable)

            Image(systemName: "shippingbox").foregroundStyle(.pink).font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if alreadyInstalled {
                    Text("App already in Applications — safe to remove")
                        .font(.caption2)
                        .foregroundStyle(row.isKeepSafe ? Color.secondary : Color.teal)
                } else {
                    Text(row.parentPath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Text(human(item.size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            keepSafeControl()
        }
        .padding(.vertical, 2)
    }
}

private nonisolated extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

struct ContentView: View {
    private static let detectedAudioFoldersListID = "audio-system-detected-folders"

    @StateObject private var controller = ScanController()
    @StateObject private var keepSafeStore = KeepSafeStore.shared
    @State private var duplicateSelection = PathSelectionState()
    @State private var installerSelection = PathSelectionState()
    @State private var stagedFiles: [StagedFile] = []
    @State private var appAlert: AppAlert?
    @State private var showOtherLargeApplications = false
    @State private var expandedAudioGuidancePaths: Set<String> = []
    @State private var expandedResultListIDs: Set<String> = []
    @State private var storageExplorerRoute: StorageExplorerRoute = .root
    @State private var resultsPresentationModel: ResultsPresentationModel?
    @State private var resultsPresentationBuildTask: Task<Void, Never>?
    @State private var pendingResultsPresentationIdentity: String?
    @State private var pendingResultsPresentationShouldSelectDuplicates = false
    @State private var protectionRefreshTask: Task<Void, Never>?
    @State private var pendingProtectionRefreshRevision: String?
    @State private var suppressNextKeepSafeProtectionRefresh = false
    @State private var keepSafePathsInProgress: Set<String> = []
    @State private var keepSafeItemIDsInProgress: Set<UUID> = []
    @State private var pendingRemoveKeepSafeItem: KeepSafeItem?
    @State private var actionToast: ActionToast?
    @State private var isMovingToStaging = false
    @State private var isMovingInstallersToStaging = false
    @State private var isRestoringAllStaged = false
    @State private var isClearingStaging = false
    @AppStorage("SessionSweepHasValidLicense") private var hasValidLicense = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            Group {
                if let result = controller.result {
                    let identity = resultsPresentationIdentity(for: result)
                    if let model = resultsPresentationModel, model.identity == identity {
                        resultsView(result, model: model)
                    } else {
                        preparingResultsView
                            .onAppear { rebuildResultsPresentationModel(selectRecommendedDuplicates: true) }
                    }
                }
                else if controller.isScanning { scanningView }
                else { emptyView }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(28)
        .frame(minWidth: 780, minHeight: 660)
        .overlay(alignment: .topTrailing) {
            if let actionToast {
                Text(actionToast.message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
                    .padding(.top, 4)
                    .padding(.trailing, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .accessibilityLabel(actionToast.message)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: actionToast)
        .task {
            refreshStaging()
        }
        .onChange(of: scanResultExpansionIdentity(controller.result)) { _ in
            expandedResultListIDs.removeAll()
            storageExplorerRoute = .root
            let keepSafeIdentityBeforeRefresh = keepSafePresentationIdentity()
            refreshKeepSafeFromCurrentScan()
            suppressNextKeepSafeProtectionRefresh = keepSafePresentationIdentity() != keepSafeIdentityBeforeRefresh
            refreshStaging()
            rebuildResultsPresentationModel(selectRecommendedDuplicates: true)
            installerSelection.removeAll()
        }
        .onChange(of: keepSafePresentationIdentity()) { revision in
            if suppressNextKeepSafeProtectionRefresh {
                suppressNextKeepSafeProtectionRefresh = false
                pruneSelectionsAgainstPresentationModel()
                return
            }
            refreshProtectionPresentationModel(keepSafeRevision: revision)
        }
        .alert(item: $appAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("Remove Keep Safe?", isPresented: Binding(
            get: { pendingRemoveKeepSafeItem != nil },
            set: { if !$0 { pendingRemoveKeepSafeItem = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingRemoveKeepSafeItem = nil }
            Button("Remove Keep Safe") {
                if let item = pendingRemoveKeepSafeItem {
                    removeKeepSafe(item)
                }
                pendingRemoveKeepSafeItem = nil
            }
        } message: {
            Text("SessionSweep may include this item in future cleanup recommendations if it otherwise qualifies. The file will not be moved or deleted now.")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SessionSweep").font(.title2.bold())
                Text("Find what's eating your drive")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if controller.isScanning {
                Button(role: .cancel) { controller.cancel() } label: {
                    Text("Cancel").frame(minWidth: 60)
                }
                .controlSize(.large)
                .pointerCursor()
                .help("Cancel scan")
            } else if controller.result != nil {
                Button { pickAndScan() } label: {
                    Label("Scan Again", systemImage: "magnifyingglass")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .pointerCursor()
                .help("Choose a folder and scan again")
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "internaldrive")
                .font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("Pick a folder to scan.")
                .font(.title3.weight(.medium))
            Text("Try your projects folder, your Music drive, or your whole startup disk.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { pickAndScan() } label: {
                Label("Choose Folder & Scan", systemImage: "magnifyingglass")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .pointerCursor()
            .help("Choose a folder to scan")
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var scanningView: some View {
        VStack(spacing: 20) {
            Spacer()

            if controller.phase == .scanning {
                // Live bytes found — the key progress signal
                if controller.liveBytes > 0 {
                    VStack(spacing: 4) {
                        Text(human(controller.liveBytes))
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("found so far")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)
                }

                ProgressView()
                    .controlSize(.large)

                VStack(spacing: 6) {
                    Text("Scanning…")
                        .font(.title3.weight(.semibold))
                    if controller.liveItems > 0 {
                        Text("\(controller.liveItems.formatted()) items scanned")
                            .font(.callout).foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    if !controller.liveLabel.isEmpty {
                        Text(controller.liveLabel)
                            .font(.caption).foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.middle)
                            .padding(.top, 2)
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                VStack(spacing: 6) {
                    Text("Checking for duplicates…")
                        .font(.title3.weight(.semibold))
                    Text("Comparing files — almost done.")
                        .font(.callout).foregroundStyle(.secondary)
                    if controller.dupTotal > 0 {
                        Text("\(controller.dupChecked) of \(controller.dupTotal) groups checked")
                            .font(.caption).foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
            }

            Spacer()

            // Cancel button also shown inline for visibility
            Button(role: .cancel) { controller.cancel() } label: {
                Text("Cancel scan")
                    .frame(minWidth: 120)
            }
            .controlSize(.regular)
            .pointerCursor()
            .help("Cancel scan")
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.3), value: controller.liveBytes)
    }

    private var preparingResultsView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Preparing results...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func resultsView(_ r: ScanResult, model: ResultsPresentationModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(human(r.totalSize))
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                        Text("across \(r.fileCount.formatted()) items in \(headlineLocation)")
                            .foregroundStyle(.secondary)
                        Text(String(format: "Scan completed in %.0f seconds.", r.elapsed))
                            .font(.callout).foregroundStyle(.secondary)
                            .padding(.top, 2)
                        if r.unreadableCount > 0 || r.excludedSystemCount > 0 {
                            VStack(alignment: .leading, spacing: 3) {
                                if r.unreadableCount > 0 {
                                    Label(
                                        "\(r.unreadableCount) item\(r.unreadableCount == 1 ? "" : "s") couldn't be read — these are protected system files that require special permissions. Nothing was missed from your audio content.",
                                        systemImage: "lock"
                                    )
                                }
                                if r.excludedSystemCount > 0 {
                                    Label(
                                        "\(r.excludedSystemCount) macOS system folder\(r.excludedSystemCount == 1 ? "" : "s") skipped — SessionSweep only looks at your content, not core OS files.",
                                        systemImage: "xmark.shield"
                                    )
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.top, 2)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        if r.cancelled {
                            Label("Scan cancelled — partial results", systemImage: "exclamationmark.circle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .id(ResultSectionID.summary)

                    card { categorySection(model: model) }
                        .id(ResultSectionID.categories)
                    storageRecommendationsSection(model, result: r, proxy: proxy)
                        .id(ResultSectionID.recommendations)
                    card { audioSystemDataSection(r, model: model) }
                        .id(ResultSectionID.audioSystemData)
                    card { keepSafeSection(model: model) }
                        .id(ResultSectionID.keepSafe)
                    card { duplicatesSection(r, model: model) }
                        .id(ResultSectionID.duplicates)
                    card { installersSection(model: model) }
                        .id(ResultSectionID.installers)
                    card { stagingSection() }
                        .id(ResultSectionID.staging)
                    card { browserSection(model: model) }
                        .id(ResultSectionID.storageExplorer)

                    largestAudioAssetsSection(model: model)
                        .id(ResultSectionID.largestAudioAssets)

                    Text("Scanned in \(String(format: "%.1f", r.elapsed))s · "
                         + "\(r.fileCount.formatted()) items · \(r.unreadableCount) unreadable · "
                         + "\(r.excludedSystemCount) system folders skipped")
                        .font(.caption2).foregroundStyle(.tertiary).padding(.top, 4)
                }
                .padding(.bottom, 16)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.secondary.opacity(0.06))
            )
    }

    private func resultsPresentationIdentity(for result: ScanResult) -> String {
        scanResultExpansionIdentity(result)
    }

    private func keepSafePresentationIdentity() -> String {
        keepSafeStore.items
            .map {
                [
                    $0.id.uuidString,
                    $0.originalPath,
                    $0.resolvedPath,
                    $0.itemType.rawValue,
                    "\($0.sizeAtProtection)",
                    "\($0.dateProtected.timeIntervalSinceReferenceDate)",
                    $0.classification ?? "",
                    $0.category ?? ""
                ].joined(separator: ":")
            }
            .sorted()
            .joined(separator: "|")
    }

    private func rebuildResultsPresentationModel(selectRecommendedDuplicates: Bool) {
        guard let result = controller.result else {
            resultsPresentationBuildTask?.cancel()
            resultsPresentationBuildTask = nil
            protectionRefreshTask?.cancel()
            protectionRefreshTask = nil
            pendingResultsPresentationIdentity = nil
            pendingResultsPresentationShouldSelectDuplicates = false
            pendingProtectionRefreshRevision = nil
            resultsPresentationModel = nil
            duplicateSelection.configure(stageablePaths: [], byteSizes: [:])
            installerSelection.configure(stageablePaths: [], byteSizes: [:])
            return
        }

        let identity = resultsPresentationIdentity(for: result)
        if let model = resultsPresentationModel, model.identity == identity {
            configureSelectionModels(for: model)
            if selectRecommendedDuplicates {
                duplicateSelection.setSelection(
                    model.recommendedDuplicateSelection,
                    blockedPathKeys: keepSafePathsInProgress
                )
            }
            pruneSelectionsAgainstPresentationModel()
            return
        }

        if pendingResultsPresentationIdentity == identity {
            pendingResultsPresentationShouldSelectDuplicates = pendingResultsPresentationShouldSelectDuplicates || selectRecommendedDuplicates
            return
        }

        resultsPresentationBuildTask?.cancel()
        protectionRefreshTask?.cancel()
        protectionRefreshTask = nil
        pendingProtectionRefreshRevision = nil
        pendingResultsPresentationIdentity = identity
        pendingResultsPresentationShouldSelectDuplicates = selectRecommendedDuplicates

        let keepSafeItems = keepSafeStore.items
        let keepSafeRevision = keepSafePresentationIdentity()
        resultsPresentationBuildTask = Task.detached(priority: .userInitiated) {
            let model = ResultsPresentationModel.build(
                result: result,
                keepSafeItems: keepSafeItems,
                identity: identity,
                keepSafeRevision: keepSafeRevision
            )

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard pendingResultsPresentationIdentity == identity else { return }
                guard let currentResult = controller.result,
                      resultsPresentationIdentity(for: currentResult) == identity else {
                    pendingResultsPresentationIdentity = nil
                    pendingResultsPresentationShouldSelectDuplicates = false
                    return
                }
                guard keepSafePresentationIdentity() == keepSafeRevision else {
                    let shouldRetrySelectingDuplicates = pendingResultsPresentationShouldSelectDuplicates || selectRecommendedDuplicates
                    pendingResultsPresentationIdentity = nil
                    pendingResultsPresentationShouldSelectDuplicates = false
                    resultsPresentationBuildTask = nil
                    rebuildResultsPresentationModel(selectRecommendedDuplicates: shouldRetrySelectingDuplicates)
                    return
                }

                let shouldSelectDuplicates = pendingResultsPresentationShouldSelectDuplicates
                resultsPresentationModel = model
                pendingResultsPresentationIdentity = nil
                pendingResultsPresentationShouldSelectDuplicates = false
                resultsPresentationBuildTask = nil
                configureSelectionModels(for: model)
                if shouldSelectDuplicates {
                    duplicateSelection.setSelection(
                        model.recommendedDuplicateSelection,
                        blockedPathKeys: keepSafePathsInProgress
                    )
                }
                pruneSelectionsAgainstPresentationModel()
            }
        }
    }

    private func refreshProtectionPresentationModel(keepSafeRevision: String) {
        guard let model = resultsPresentationModel,
              let result = controller.result,
              model.identity == resultsPresentationIdentity(for: result)
        else {
            rebuildResultsPresentationModel(selectRecommendedDuplicates: false)
            return
        }

        if model.keepSafeRevision == keepSafeRevision {
            pruneSelectionsAgainstPresentationModel()
            return
        }

        protectionRefreshTask?.cancel()
        pendingProtectionRefreshRevision = keepSafeRevision
        let keepSafeItems = keepSafeStore.items
        protectionRefreshTask = Task.detached(priority: .userInitiated) {
            let refreshedModel = model.refreshingProtection(
                keepSafeItems: keepSafeItems,
                keepSafeRevision: keepSafeRevision
            )

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard pendingProtectionRefreshRevision == keepSafeRevision else { return }
                guard let currentResult = controller.result,
                      resultsPresentationIdentity(for: currentResult) == refreshedModel.identity,
                      keepSafePresentationIdentity() == keepSafeRevision else {
                    pendingProtectionRefreshRevision = nil
                    protectionRefreshTask = nil
                    return
                }
                resultsPresentationModel = refreshedModel
                pendingProtectionRefreshRevision = nil
                protectionRefreshTask = nil
                configureSelectionModels(for: refreshedModel)
                pruneSelectionsAgainstPresentationModel()
            }
        }
    }

    private func configureSelectionModels(for model: ResultsPresentationModel) {
        duplicateSelection.configure(
            stageablePaths: model.duplicateStageablePaths,
            byteSizes: model.duplicatePathSizes,
            blockedPathKeys: keepSafePathsInProgress
        )
        installerSelection.configure(
            stageablePaths: model.installerStageablePaths,
            byteSizes: model.installerPathSizes,
            blockedPathKeys: keepSafePathsInProgress
        )
    }

    private func pruneSelectionsAgainstPresentationModel() {
        guard let model = resultsPresentationModel else {
            duplicateSelection.configure(stageablePaths: [], byteSizes: [:])
            installerSelection.configure(stageablePaths: [], byteSizes: [:])
            return
        }
        configureSelectionModels(for: model)
    }

    @ViewBuilder
    private func storageRecommendationsSection(
        _ model: ResultsPresentationModel,
        result r: ScanResult,
        proxy: ScrollViewProxy
    ) -> some View {
        let recommendations = model.recommendations

        if !recommendations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommended Next Steps")
                        .font(.headline)
                    Text("SessionSweep found a few opportunities worth reviewing, ordered from the safest recommendations to items that deserve a closer look.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 285), spacing: 12, alignment: .top)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(recommendations) { recommendation in
                        recommendationCard(recommendation, result: r, proxy: proxy)
                    }
                }
            }
        }
    }

    private func recommendationCard(
        _ recommendation: StorageRecommendation,
        result: ScanResult,
        proxy: ScrollViewProxy
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: recommendation.iconName)
                    .font(.title3)
                    .foregroundStyle(recommendationColor(recommendation.kind))
                    .frame(width: 24, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(recommendation.title)
                        .font(.subheadline.weight(.semibold))
                    Text(recommendation.estimate)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
            }

            Text(recommendation.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if let confidence = recommendation.confidence {
                    Text(confidence)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                }
                Spacer(minLength: 0)
                if let destination = recommendation.destination {
                    Button {
                        navigateToRecommendation(destination, result: result, model: resultsPresentationModel, proxy: proxy)
                    } label: {
                        Label(recommendation.actionTitle, systemImage: "arrow.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.teal)
                    .subtleTextAction(help: recommendation.actionTitle)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func recommendationColor(_ kind: StorageRecommendationKind) -> Color {
        switch kind {
        case .safeCleanup: return .teal
        case .archiveCandidates: return .purple
        case .libraryRelocation: return .mint
        case .largeApplications: return .brown
        case .leaveInPlace: return .secondary
        case .keepSafe: return .teal
        }
    }

    private func navigateToRecommendation(
        _ destination: StorageRecommendationDestination,
        result: ScanResult,
        model: ResultsPresentationModel?,
        proxy: ScrollViewProxy
    ) {
        let target: ResultSectionID
        switch destination {
        case .safeCleanup:
            target = result.duplicateGroups.isEmpty ? .installers : .duplicates
        case .archiveCandidates:
            storageExplorerRoute = .personalFiles
            target = .storageExplorer
        case .libraryRelocation:
            if let candidatePath = model?.firstRelocationCandidatePath {
                expandedAudioGuidancePaths.insert(candidatePath)
                expandedResultListIDs.insert(Self.detectedAudioFoldersListID)
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(ResultSectionID.audioSystemFolder(candidatePath), anchor: .center)
                    }
                }
                return
            }
            target = .audioSystemData
        case .leaveInPlace:
            target = .audioSystemData
        case .applications:
            storageExplorerRoute = .applications
            target = .storageExplorer
        case .keepSafe:
            target = .keepSafe
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    private func categorySection(model: ResultsPresentationModel) -> some View {
        let cats = model.categoryRows
        let total = max(model.totalSize, 1)
        let mid = (cats.count + 1) / 2
        let leftCol = Array(cats.prefix(mid))
        let rightCol = Array(cats.dropFirst(mid))

        return VStack(alignment: .leading, spacing: 14) {
            Text("What's Filling Your Drive").font(.headline)
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(cats, id: \.category) { row in
                        Rectangle().fill(row.category.color)
                            .frame(width: max(2, geo.size.width * (Double(row.size) / Double(total))))
                    }
                }
            }
            .frame(height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(leftCol, id: \.category) { row in
                        categoryRow(row.category, size: row.size, total: total)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rightCol, id: \.category) { row in
                        categoryRow(row.category, size: row.size, total: total)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func categoryRow(_ cat: Category, size: Int64, total: Int64) -> some View {
        HStack(spacing: 8) {
            Circle().fill(cat.color).frame(width: 9, height: 9)
            Text(cat.displayName)
            Spacer()
            Text(human(size))
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Text("\(Int((Double(size) / Double(total) * 100).rounded()))%")
                .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func keepSafeSection(model: ResultsPresentationModel) -> some View {
        let items = model.sortedKeepSafeItems
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your Protected Files").font(.headline)
                    Text("These are files and folders you asked SessionSweep to keep out of cleanup recommendations.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text("Keep Safe only affects SessionSweep. It does not prevent files from being moved or deleted in Finder, another app, or by macOS. Keep Safe is not a backup.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if items.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("No protected files yet")
                        .font(.callout)
                    Text("Use Keep Safe on any file or folder you do not want SessionSweep to recommend or stage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        keepSafeItemRow(item)
                    }
                }
            }
        }
    }

    private func keepSafeItemRow(_ item: KeepSafeItem) -> some View {
        let status = keepSafeStore.availability(for: item)
        let currentPath = keepSafeStore.currentPath(for: item)
        let guidance = keepSafeGuidance(for: item, currentPath: currentPath)
        let isBusy = isKeepSafeOperationInProgress(path: currentPath, protectedItem: item)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: item.itemType == .folder ? "folder.fill" : "doc.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(item.classification ?? item.category ?? "Protected item") · \(item.itemType.displayName) · \(keepSafeStatusText(status))")
                        .font(.caption2)
                        .foregroundStyle(status == .available ? Color.secondary : Color.orange)
                }
                Spacer()
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.62)
                        .frame(width: 12, height: 12)
                        .accessibilityLabel("Updating Keep Safe")
                }
                Menu {
                    Button("Reveal in Finder") { revealKeepSafeItem(item) }
                    Button("Copy Path") { copyPath(currentPath) }
                    Divider()
                    Button(isBusy ? "Removing..." : "Remove from Keep Safe") { pendingRemoveKeepSafeItem = item }
                        .disabled(isBusy)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .iconActionControl(help: "More actions")
                }
                .buttonStyle(.borderless)
                .menuStyle(.button)
                .help("Protected item actions")
            }

            Text(currentPath)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 10) {
                Text(item.sizeAtProtection > 0 ? human(item.sizeAtProtection) : "Size unavailable")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(item.sizeAtProtection > 0 ? .secondary : .tertiary)
                Label("Keep Safe", systemImage: "lock.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.teal)
                Text("Protected \(item.dateProtected.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            if let guidance {
                Text(guidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func keepSafeGuidance(for item: KeepSafeItem, currentPath: String) -> String? {
        if let audioItem = AudioSystemDataClassifier.classify(path: currentPath, size: item.sizeAtProtection) {
            let guidance = AudioFolderGuidanceClassifier.guidance(for: audioItem)
            return "\(guidance.displayTitle). \(guidance.explanation) \(guidance.guidance) Keep Safe remains active until you remove it."
        }

        if let classification = item.classification {
            return "\(classification). Keep Safe prevents SessionSweep from recommending or staging this item."
        }

        return "Keep Safe prevents SessionSweep from recommending or staging this item while still allowing you to review its path and classification."
    }

    private func keepSafeStatusText(_ status: KeepSafeAvailabilityStatus) -> String {
        switch status {
        case .available:
            return "Available"
        case .locationChanged:
            return "Location changed"
        case .notAvailable:
            return "Not currently available"
        }
    }

    private func sortedKeepSafeItems() -> [KeepSafeItem] {
        keepSafeStore.items.sorted { lhs, rhs in
            let lhsKnown = lhs.sizeAtProtection > 0
            let rhsKnown = rhs.sizeAtProtection > 0
            if lhsKnown != rhsKnown { return lhsKnown }
            if lhsKnown && rhsKnown && lhs.sizeAtProtection != rhs.sizeAtProtection {
                return lhs.sizeAtProtection > rhs.sizeAtProtection
            }
            if lhs.dateProtected != rhs.dateProtected {
                return lhs.dateProtected > rhs.dateProtected
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func scanResultExpansionIdentity(_ result: ScanResult?) -> String {
        guard let result else { return "no-scan" }
        return [
            result.rootPath,
            "\(result.fileCount)",
            "\(result.totalSize)",
            "\(result.unreadableCount)",
            "\(result.elapsed)"
        ].joined(separator: "|")
    }

    private func visibleResultItems<Item>(
        _ items: [Item],
        compactCount: Int,
        listID: String
    ) -> [Item] {
        guard compactCount > 0,
              items.count > compactCount,
              !expandedResultListIDs.contains(listID)
        else { return items }
        return Array(items.prefix(compactCount))
    }

    private func hiddenResultItemCount<Item>(
        _ items: [Item],
        compactCount: Int
    ) -> Int {
        max(0, items.count - compactCount)
    }

    private struct IdenticalContentGroupPresentation: Identifiable {
        let group: DuplicateGroup
        let classification: DifferentNameMatchClassification

        var id: DuplicateGroup.ID { group.id }
        var representedStorageBytes: Int64 { group.fileSize * Int64(group.count) }
        var largestFileBytes: Int64 { group.fileSize }
        var filename: String { group.displayName }
    }

    private func sortedIdenticalContentGroups(
        _ groups: [DuplicateGroup]
    ) -> [IdenticalContentGroupPresentation] {
        groups
            .map { group in
                IdenticalContentGroupPresentation(
                    group: group,
                    classification: DifferentNameMatchClassifier.classify(
                        paths: group.paths,
                        fileSize: group.fileSize
                    )
                )
            }
            .sorted { lhs, rhs in
                let lhsCategory = identicalContentCategorySortRank(lhs.classification.kind)
                let rhsCategory = identicalContentCategorySortRank(rhs.classification.kind)
                if lhsCategory != rhsCategory { return lhsCategory < rhsCategory }

                if lhs.representedStorageBytes != rhs.representedStorageBytes {
                    return lhs.representedStorageBytes > rhs.representedStorageBytes
                }

                if lhs.largestFileBytes != rhs.largestFileBytes {
                    return lhs.largestFileBytes > rhs.largestFileBytes
                }

                return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
            }
    }

    private func identicalContentCategorySortRank(_ kind: DifferentNameMatchKind) -> Int {
        switch kind {
        case .repeatedExportCopies:
            return 0
        case .possibleAlternateVersions:
            return 1
        case .possibleDuplicateTracks:
            return 2
        case .unclear:
            return 3
        case .likelyConsolidatedStems:
            return 4
        case .possibleSilentFiles:
            return 5
        }
    }

    @ViewBuilder
    private func expandableResultListToggle(
        listID: String,
        hiddenCount: Int,
        itemSingular: String,
        itemPlural: String,
        expandedLabel: String? = nil,
        accessibilityCollapsedLabel: String? = nil,
        accessibilityExpandedLabel: String? = nil
    ) -> some View {
        if hiddenCount > 0 {
            let isExpanded = expandedResultListIDs.contains(listID)
            let collapsedTitle = "Show \(hiddenCount) more \(hiddenCount == 1 ? itemSingular : itemPlural)"
            let expandedTitle = expandedLabel ?? "Hide additional \(itemPlural)"
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if isExpanded {
                        expandedResultListIDs.remove(listID)
                    } else {
                        expandedResultListIDs.insert(listID)
                    }
                }
            } label: {
                Label(isExpanded ? expandedTitle : collapsedTitle,
                      systemImage: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.teal)
            .interactiveHover(isSelected: isExpanded, cornerRadius: 7, tint: .teal)
            .pointerCursor()
            .help(isExpanded ? expandedTitle : collapsedTitle)
            .accessibilityLabel(isExpanded
                                ? (accessibilityExpandedLabel ?? expandedTitle)
                                : (accessibilityCollapsedLabel ?? collapsedTitle))
        }
    }

    private func audioSystemDataSection(_ r: ScanResult, model: ResultsPresentationModel) -> some View {
        let audio = r.audioSystemData
        let categories = model.audioCategoryRows
        let topFolders = model.topAudioFolders
        let topFolderPaths = Set(topFolders.map { $0.item.path })
        let detectedAudioFolderLimit = 12
        let rows = visibleResultItems(
            model.detectedAudioFolders,
            compactCount: detectedAudioFolderLimit,
            listID: Self.detectedAudioFoldersListID
        )
        let hiddenDetectedAudioFolderCount = hiddenResultItemCount(
            model.detectedAudioFolders,
            compactCount: detectedAudioFolderLimit
        )

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Audio System Data").font(.headline)
                    Text("Music production files macOS may label as System Data.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text(human(audio.totalSize))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(audio.totalSize > 0 ? .primary : .secondary)
            }

            Text("SessionSweep found audio production files that can contribute to macOS \"System Data.\" These are typically part of your studio setup rather than hidden junk files.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if r.unreadableCount > 0 {
                VStack(alignment: .leading, spacing: 3) {
                    Label(
                        "Some system folders couldn't be analyzed because macOS restricted access.",
                        systemImage: "lock"
                    )
                    Text("Granting Full Disk Access allows SessionSweep to provide a more complete storage analysis. Your files are never modified during scanning.")
                        .padding(.leading, 18)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if audio.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("No significant audio-related System Data was detected.")
                        .font(.callout)
                    Text("Your music production files are either stored elsewhere or are using minimal space.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(categories, id: \.category) { row in
                        audioBreakdownRow(row.category, size: row.size, total: max(audio.totalSize, 1))
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Top folders").font(.subheadline.weight(.semibold))
                    ForEach(topFolders) { audioSystemDataRow($0, isScrollAnchor: true) }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Detected audio folders").font(.subheadline.weight(.semibold))
                    ForEach(rows) { row in
                        audioSystemDataRow(row, isScrollAnchor: !topFolderPaths.contains(row.item.path))
                    }
                    expandableResultListToggle(
                        listID: Self.detectedAudioFoldersListID,
                        hiddenCount: hiddenDetectedAudioFolderCount,
                        itemSingular: "audio folder",
                        itemPlural: "audio folders",
                        expandedLabel: "Hide additional audio folders",
                        accessibilityCollapsedLabel: "Show \(hiddenDetectedAudioFolderCount) more detected audio folder\(hiddenDetectedAudioFolderCount == 1 ? "" : "s")",
                        accessibilityExpandedLabel: "Hide additional detected audio folders"
                    )
                }

                Text("These files are usually part of your music production environment—plugins, presets, impulse responses, and application support files. SessionSweep is showing them so you understand where storage is being used, not because they are automatically safe to delete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func audioBreakdownRow(
        _ category: AudioSystemDataCategory,
        size: Int64,
        total: Int64
    ) -> some View {
        HStack(spacing: 8) {
            Circle().fill(category.color).frame(width: 9, height: 9)
            Text(category.rawValue)
            Spacer()
            Text(human(size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(size > 0 ? .secondary : .tertiary)
            Text("\(Int((Double(size) / Double(total) * 100).rounded()))%")
                .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func audioSystemDataRow(
        _ row: AudioFolderPresentationRow,
        isScrollAnchor: Bool = false
    ) -> some View {
        let item = row.item
        let guidance = row.guidance
        let isExpanded = expandedAudioGuidancePaths.contains(item.path)

        let row = VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(item.category.color).frame(width: 8, height: 8)
                Text(item.friendlyName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(item.safetyStatus.rawValue)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .help(item.safetyStatus.explanatoryCopy)
                    .accessibilityLabel(item.safetyStatus.explanatoryCopy)
                Button {
                    toggleAudioGuidance(for: item.path)
                } label: {
                    Image(systemName: isExpanded ? "info.circle.fill" : "info.circle")
                        .font(.title3)
                        .iconActionControl(isSelected: isExpanded, help: "About this folder")
                }
                .buttonStyle(.borderless)
                .help("About this folder")
                Text(human(item.size))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 88, alignment: .trailing)
            }
            HStack(spacing: 6) {
                Text(item.category.rawValue)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(item.category.color)
                Text(item.path)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if isExpanded {
                audioFolderGuidanceDetails(item: item, guidance: guidance)
            }
        }
        .padding(.vertical, 3)

        if isScrollAnchor {
            row.id(ResultSectionID.audioSystemFolder(item.path))
        } else {
            row
        }
    }

    private func audioFolderGuidanceDetails(
        item: AudioSystemDataItem,
        guidance: AudioFolderGuidance
    ) -> some View {
        let vendorGuide = guidance.vendorGuide

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(item.friendlyName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(human(item.size))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(guidance.displayTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("•")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(item.category.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.category.color)
                Spacer()
                Button {
                    revealAudioFolderInFinder(item.path)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .buttonStyle(.borderless)
                .subtleTextAction(help: "Reveal this folder in Finder")
                Button {
                    copyAudioFolderPath(item.path)
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .subtleTextAction(help: "Copy this folder path")
            }

            audioFolderAdvisorSection(
                title: "About",
                text: vendorGuide.about
            )
            audioFolderAdvisorSection(
                title: "Why it exists",
                text: vendorGuide.whyItExists
            )

            VStack(alignment: .leading, spacing: 5) {
                Text("Relocation Support")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Label(
                    guidance.relocationSupport.displayTitle,
                    systemImage: relocationSupportIcon(guidance.relocationSupport)
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(relocationSupportColor(guidance.relocationSupport))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(relocationSupportColor(guidance.relocationSupport).opacity(0.10), in: Capsule())
                if isUnknownRelocationSupport(guidance.relocationSupport) {
                    Text("We could not verify an official relocation method for this folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let method = vendorGuide.recommendedMethod {
                audioFolderAdvisorSection(
                    title: "Recommended Method",
                    text: method
                )
            }

            audioFolderAdvisorSection(
                title: "Risk Guidance",
                text: vendorGuide.riskSummary
            )

            if let urlString = vendorGuide.documentationURLString,
               let url = URL(string: urlString) {
                Link(destination: url) {
                    Label(vendorGuide.documentationTitle ?? "Vendor Documentation", systemImage: "arrow.up.right.square")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.teal)
            }

            Text(item.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .padding(.leading, 16)
        .padding(.top, 4)
    }

    private func audioFolderAdvisorSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func relocationSupportIcon(_ support: RelocationSupport) -> String {
        switch support {
        case .officialSupported:
            return "checkmark.seal"
        case .vendorToolRequired:
            return "gearshape"
        case .manualPossible:
            return "hand.raised"
        case .reviewFirst:
            return "magnifyingglass.circle"
        case .leaveInPlace:
            return "lock"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private func relocationSupportColor(_ support: RelocationSupport) -> Color {
        switch support {
        case .officialSupported, .vendorToolRequired:
            return .teal
        case .manualPossible:
            return .blue
        case .reviewFirst:
            return .orange
        case .leaveInPlace:
            return .secondary
        case .unknown:
            return .secondary
        }
    }

    private func isUnknownRelocationSupport(_ support: RelocationSupport) -> Bool {
        switch support {
        case .unknown:
            return true
        default:
            return false
        }
    }

    private func largestAudioAssetsSection(model: ResultsPresentationModel) -> some View {
        let audioAssets = model.largestAudioAssets
        let otherLargeApplications = model.otherLargeApplications
        let audioAssetsListID = "largest-audio-assets"
        let audioAssetsLimit = 12
        let visibleAudioAssets = visibleResultItems(
            audioAssets,
            compactCount: audioAssetsLimit,
            listID: audioAssetsListID
        )
        let hiddenAudioAssetCount = hiddenResultItemCount(
            audioAssets,
            compactCount: audioAssetsLimit
        )
        let otherApplicationsListID = "other-large-applications"
        let otherApplicationsLimit = 8
        let visibleOtherLargeApplications = visibleResultItems(
            otherLargeApplications,
            compactCount: otherApplicationsLimit,
            listID: otherApplicationsListID
        )
        let hiddenOtherApplicationCount = hiddenResultItemCount(
            otherLargeApplications,
            compactCount: otherApplicationsLimit
        )

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Largest Audio Assets").font(.headline)
                Text("The largest audio applications, libraries, sample content, and production assets on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if audioAssets.isEmpty {
                Text("No large audio-focused assets were found in the top scan results.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleAudioAssets) { fileRow($0) }
                expandableResultListToggle(
                    listID: audioAssetsListID,
                    hiddenCount: hiddenAudioAssetCount,
                    itemSingular: "audio asset",
                    itemPlural: "audio assets",
                    expandedLabel: "Hide additional audio assets"
                )
            }

            if !otherLargeApplications.isEmpty {
                DisclosureGroup(isExpanded: $showOtherLargeApplications) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Very large non-audio apps are shown here for context, but they are not part of your primary music-production storage picture.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(visibleOtherLargeApplications) { fileRow($0) }
                        expandableResultListToggle(
                            listID: otherApplicationsListID,
                            hiddenCount: hiddenOtherApplicationCount,
                            itemSingular: "application",
                            itemPlural: "applications",
                            expandedLabel: "Hide additional applications",
                            accessibilityCollapsedLabel: "Show \(hiddenOtherApplicationCount) more other large application\(hiddenOtherApplicationCount == 1 ? "" : "s")",
                            accessibilityExpandedLabel: "Hide additional other large applications"
                        )
                    }
                    .padding(.top, 6)
                } label: {
                    HStack {
                        Text("Other Large Applications")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(otherLargeApplications.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .padding(.top, 4)
                .interactiveHover(isSelected: showOtherLargeApplications, tint: .teal)
                .pointerCursor()
                .help(showOtherLargeApplications ? "Hide other large applications" : "Show other large applications")
            }
        }
    }

    private func duplicatesSection(_ r: ScanResult, model: ResultsPresentationModel) -> some View {
        DuplicateResultsSection(
            hasDuplicateGroups: !r.duplicateGroups.isEmpty,
            duplicateGroups: model.duplicateGroups,
            identicalContentGroups: model.identicalContentGroups,
            actionableReclaimable: model.duplicateActionableTotal,
            selection: duplicateSelection,
            expandedResultListIDs: $expandedResultListIDs,
            isMovingToStaging: isMovingToStaging,
            selectAll: { selectAllDuplicates(r) },
            deselectAll: { deselectAllDuplicates() },
            moveSelected: { moveSelectedToStaging() },
            groupRow: { confidentRow($0, selection: duplicateSelection) },
            identicalRow: { item in
                identicalRow(item.group, classification: item.classification, sharedParent: item.sharedParent)
            },
            human: human
        )
    }

    private func confidentRow(_ row: DuplicateGroupPresentationRow, selection: PathSelectionState) -> some View {
        let g = row.group
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc.fill").foregroundStyle(.teal).font(.caption)
                Text(g.displayName).fontWeight(.medium)
                    .lineLimit(1).truncationMode(.middle)
                Text("×\(g.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(human(row.actionableBytes)) reclaimable")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            ForEach(row.paths) { pathRow in
                duplicatePathRow(pathRow, selection: selection)
            }
        }
        .padding(.vertical, 4)
    }

    private func duplicatePathRow(_ row: DuplicatePathPresentationRow, selection: PathSelectionState) -> some View {
        let path = row.path
        let safetyClassification = row.safetyClassification
        let isBusy = isKeepSafeOperationInProgress(pathKey: row.pathKey, protectedItem: row.keepSafeItem)
        return DuplicatePathResultRow(
            row: row,
            isBusy: isBusy,
            selection: selection,
            recommendationLabel: duplicateRecommendationLabel,
            recommendationDescription: duplicateRecommendationDescription,
            keepSafeControl: {
                keepSafeButton(
                    path: path,
                    protectedItem: row.keepSafeItem,
                    itemType: .file,
                    size: row.fileSize,
                    classification: safetyClassification.label,
                    category: "Duplicate File"
                )
            },
            human: human
        )
    }

    private func installersSection(model: ResultsPresentationModel) -> some View {
        InstallerResultsSection(
            rows: model.installerRows,
            total: model.installerActionableTotal,
            selection: installerSelection,
            isMovingInstallersToStaging: isMovingInstallersToStaging,
            selectAll: { selectAllInstallers(model.stageableInstallerRows) },
            deselectAll: { deselectAllInstallers() },
            moveSelected: { moveSelectedInstallersToStaging() },
            rowContent: { installerRow($0, selection: installerSelection) },
            human: human
        )
    }

    private func installerRow(_ row: InstallerPresentationRow, selection: PathSelectionState) -> some View {
        let path = row.path
        let isBusy = isKeepSafeOperationInProgress(pathKey: row.pathKey, protectedItem: row.keepSafeItem)
        return InstallerResultRow(
            row: row,
            isBusy: isBusy,
            selection: selection,
            keepSafeControl: {
                keepSafeButton(
                    path: path,
                    protectedItem: row.keepSafeItem,
                    itemType: .file,
                    size: row.item.size,
                    classification: row.alreadyInstalled ? "Installer already installed" : "Installer",
                    category: Category.installers.displayName
                )
            },
            human: human
        )
    }

    private func stagingSection() -> some View {
        let total = stagedFiles.reduce(Int64(0)) { $0 + $1.size }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Staging").font(.headline)
                    Text("Files moved out of duplicate locations, mirrored by original path.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if total > 0 {
                    Text(human(total))
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.teal)
                }
            }

            if stagedFiles.isEmpty {
                Text("No files are currently in SessionSweep Staging.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("\(stagedFiles.count) file\(stagedFiles.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { restoreAllStaged() } label: {
                        Label(isRestoringAllStaged ? "Restoring..." : "Restore All",
                              systemImage: isRestoringAllStaged ? "hourglass" : "arrow.uturn.backward")
                    }
                    .disabled(isRestoringAllStaged || isClearingStaging)
                    .pointerCursor(!isRestoringAllStaged && !isClearingStaging)
                    .help("Restore every staged file to its original location")
                    Button(role: .destructive) { clearStaging() } label: {
                        Label(isClearingStaging ? "Clearing..." : "Clear Staging",
                              systemImage: isClearingStaging ? "hourglass" : "trash")
                    }
                    .disabled(isRestoringAllStaged || isClearingStaging)
                    .pointerCursor(!isRestoringAllStaged && !isClearingStaging)
                    .help("Permanently delete all files in SessionSweep Staging")
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(stagedFiles) { stagedFileRow($0) }
                }
            }
        }
    }

    private func stagedFileRow(_ file: StagedFile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.originalPath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(human(file.size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .trailing)
            Button { restore(file) } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .pointerCursor()
            .help("Restore this file to its original location")
        }
        .interactiveRow(isActive: false)
    }

    private func identicalRow(
        _ g: DuplicateGroup,
        classification: DifferentNameMatchClassification,
        sharedParent: String?
    ) -> some View {
        let fileListID = "identical-content-files-\(g.id.uuidString)"
        let fileLimit = 8
        let visiblePaths = visibleResultItems(g.paths, compactCount: fileLimit, listID: fileListID)
        let hiddenCount = hiddenResultItemCount(g.paths, compactCount: fileLimit)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.badge.magnifyingglass").foregroundStyle(.orange).font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text(classification.title).fontWeight(.semibold)
                    Text("\(g.count) files with identical audio content")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(human(g.fileSize)) each")
                    .font(.callout.monospacedDigit()).foregroundStyle(.tertiary)
            }

            Text(classification.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Label("Total storage represented: \(human(g.fileSize * Int64(g.count)))", systemImage: "externaldrive")
                if let sharedParent {
                    Label("Shared folder: \(shortDisplayPath(sharedParent))", systemImage: "folder")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            if let reason = classification.reason {
                Text("Reason: \(reason)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if classification.showsCautionNote {
                Text("Review these files in context before making changes. Identical audio content does not prove the files are interchangeable.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 5) {
                ForEach(visiblePaths, id: \.self) { path in
                    differentNameFileRow(path, fileSize: g.fileSize, sharedParent: sharedParent)
                }
            }

            expandableResultListToggle(
                listID: fileListID,
                hiddenCount: hiddenCount,
                itemSingular: "file",
                itemPlural: "files",
                expandedLabel: "Hide additional files",
                accessibilityCollapsedLabel: "Show \(hiddenCount) more identical-content file\(hiddenCount == 1 ? "" : "s")",
                accessibilityExpandedLabel: "Hide additional identical-content files"
            )
        }
        .padding(.vertical, 6)
    }

    private func differentNameFileRow(
        _ path: String,
        fileSize: Int64,
        sharedParent: String?
    ) -> some View {
        let protectedItem = keepSafeStore.protectedItem(for: path)
        let isBusy = isKeepSafeOperationInProgress(path: path, protectedItem: protectedItem)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "doc").foregroundStyle(.secondary).font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(pathContext(path, sharedParent: sharedParent))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(human(fileSize))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.62)
                    .frame(width: 12, height: 12)
                    .accessibilityLabel("Protecting")
            }
            Menu {
                keepSafeMenuButton(
                    path: path,
                    itemType: .file,
                    size: fileSize,
                    classification: "Identical content, different names",
                    category: Category.audioFiles.displayName
                )
                Divider()
                Button("Reveal in Finder") { revealDifferentNameFileInFinder(path) }
                Button("Copy Path") { copyPath(path) }
                Button("Copy Filename") { copyFilename(path) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .iconActionControl(help: "More actions")
            }
            .buttonStyle(.borderless)
            .menuStyle(.button)
            .help("More actions")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Reveal in Finder") { revealDifferentNameFileInFinder(path) }
            Button("Copy Path") { copyPath(path) }
            Button("Copy Filename") { copyFilename(path) }
        }
    }

    private func browserSection(model: ResultsPresentationModel) -> some View {
        let presentation = model.routePresentation(for: storageExplorerRoute)
        let route = presentation.route
        let allNodes = presentation.nodes
        let listID = storageExplorerListID(for: route)
        let compactLimit = storageExplorerCompactLimit(for: route)
        let nodes = visibleResultItems(allNodes, compactCount: compactLimit, listID: listID)
        let hiddenNodeCount = hiddenResultItemCount(allNodes, compactCount: compactLimit)
        let itemNames = storageExplorerItemNames(for: route)
        let parentTotal = max(presentation.total, 1)
        let residual = presentation.residual

        return AnyView(
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Storage Explorer").font(.headline)
                        Text("Explore where storage is being used across your studio and Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text(human(parentTotal))
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                storageExplorerBreadcrumbs(presentation.breadcrumbs)
                if case .applications = route {
                    applicationsExplorerContent(
                        nodes: allNodes,
                        parentTotal: parentTotal,
                        residual: residual
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(nodes) { storageExplorerRow($0, parentTotal: parentTotal) }
                        expandableResultListToggle(
                            listID: listID,
                            hiddenCount: hiddenNodeCount,
                            itemSingular: itemNames.singular,
                            itemPlural: itemNames.plural,
                            expandedLabel: "Hide additional \(itemNames.plural)",
                            accessibilityCollapsedLabel: "Show \(hiddenNodeCount) more storage explorer \(itemNames.singular)\(hiddenNodeCount == 1 ? "" : "s")",
                            accessibilityExpandedLabel: "Hide additional storage explorer \(itemNames.plural)"
                        )
                        if let residual, residual.size >= 1_048_576 {
                            residualRow(residual.size, parentTotal: parentTotal, title: residual.title)
                        }
                        if allNodes.isEmpty && (residual?.size ?? 0) < 1_048_576 {
                            Text(storageExplorerEmptyMessage(for: route))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        )
    }

    private func storageExplorerBreadcrumbs(
        _ crumbs: [StorageExplorerBreadcrumb]
    ) -> some View {
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(crumbs.enumerated()), id: \.offset) { idx, crumb in
                    if idx > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    if idx == crumbs.count - 1 {
                        Text(crumb.title)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                    } else {
                        Button { storageExplorerRoute = crumb.route } label: {
                            Text(crumb.title)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fontWeight(.regular)
                        }
                        .buttonStyle(.plain)
                        .subtleTextAction(help: "Go to \(crumb.title)")
                        .accessibilityLabel("Go to \(crumb.title)")
                    }
                }
            }
        }
    }

    private func applicationsExplorerContent(
        nodes: [StorageExplorerNode],
        parentTotal: Int64,
        residual: (title: String, size: Int64)?
    ) -> some View {
        let items = classifiedApplicationItems(from: nodes)
        let audioApplications = items.filter { $0.classification.isAudioApplication }
        let otherApplications = items.filter { !$0.classification.isAudioApplication }
        let audioListID = "storage-explorer-applications-audio"
        let otherListID = "storage-explorer-applications-other"
        let compactCount = 12
        let visibleAudioApplications = visibleResultItems(
            audioApplications,
            compactCount: compactCount,
            listID: audioListID
        )
        let visibleOtherApplications = visibleResultItems(
            otherApplications,
            compactCount: compactCount,
            listID: otherListID
        )
        let hiddenAudioCount = hiddenResultItemCount(audioApplications, compactCount: compactCount)
        let hiddenOtherCount = hiddenResultItemCount(otherApplications, compactCount: compactCount)

        return VStack(alignment: .leading, spacing: 16) {
            Text("Large applications are shown for awareness only. SessionSweep does not recommend removing installed applications. This view helps explain where storage is being used across your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            applicationGroup(
                title: "Audio Applications",
                description: "Applications used for music production, recording, editing, mixing, mastering, or audio restoration.",
                emptyMessage: "No audio applications were found in this scan.",
                applications: visibleAudioApplications,
                parentTotal: parentTotal,
                listID: audioListID,
                hiddenCount: hiddenAudioCount
            )

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                applicationGroupHeader(
                    title: "Other Large Applications",
                    description: "Large applications that are not classified as audio production software."
                )
                if visibleOtherApplications.isEmpty {
                    Text("No other large applications were found in this scan.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleOtherApplications) { item in
                        applicationExplorerRow(item, parentTotal: parentTotal)
                    }
                }
                expandableResultListToggle(
                    listID: otherListID,
                    hiddenCount: hiddenOtherCount,
                    itemSingular: "application",
                    itemPlural: "applications",
                    expandedLabel: "Hide additional applications",
                    accessibilityCollapsedLabel: "Show \(hiddenOtherCount) more other large application\(hiddenOtherCount == 1 ? "" : "s")",
                    accessibilityExpandedLabel: "Hide additional other large applications"
                )
                if let residual, residual.size >= 1_048_576 {
                    applicationResidualRow(residual.size, parentTotal: parentTotal)
                }
            }
        }
    }

    private func applicationGroup(
        title: String,
        description: String,
        emptyMessage: String,
        applications: [ApplicationExplorerItem],
        parentTotal: Int64,
        listID: String,
        hiddenCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            applicationGroupHeader(title: title, description: description)
            if applications.isEmpty {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(applications) { item in
                    applicationExplorerRow(item, parentTotal: parentTotal)
                }
            }
            expandableResultListToggle(
                listID: listID,
                hiddenCount: hiddenCount,
                itemSingular: "application",
                itemPlural: "applications",
                expandedLabel: "Hide additional applications",
                accessibilityCollapsedLabel: "Show \(hiddenCount) more \(title.lowercased()) application\(hiddenCount == 1 ? "" : "s")",
                accessibilityExpandedLabel: "Hide additional \(title.lowercased()) applications"
            )
        }
    }

    private func applicationGroupHeader(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func applicationExplorerRow(
        _ item: ApplicationExplorerItem,
        parentTotal: Int64
    ) -> some View {
        let node = item.node
        let pct = Int((Double(node.size) / Double(max(parentTotal, 1)) * 100).rounded())
        let drillable = node.route != nil

        return Button {
            if let route = node.route { storageExplorerRoute = route }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: node.iconName)
                    .foregroundStyle(node.color)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.classification.displayTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let path = node.path {
                        Text(path)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if drillable {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("\(pct)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Text(human(node.size))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 88, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .interactiveRow(isActive: drillable)
        }
        .buttonStyle(.plain)
        .disabled(!drillable)
        .pointerCursor(drillable)
        .help(drillable ? "Open \(node.title)" : "")
    }

    private func applicationResidualRow(_ residual: Int64, parentTotal: Int64) -> some View {
        let pct = Int((Double(residual) / Double(max(parentTotal, 1)) * 100).rounded())
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .foregroundStyle(.secondary)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text("Other applications and supporting files")
                    .foregroundStyle(.secondary)
                Text("Additional installed applications and smaller supporting items not listed individually.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text("\(pct)%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            Text(human(residual))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .trailing)
        }
    }

    private func classifiedApplicationItems(from nodes: [StorageExplorerNode]) -> [ApplicationExplorerItem] {
        nodes
            .compactMap { node -> ApplicationExplorerItem? in
                guard node.path != nil else { return nil }
                let classification = cachedApplicationClassification(title: node.subtitle)
                return ApplicationExplorerItem(node: node, classification: classification)
            }
            .sorted { lhs, rhs in
                let lhsKnown = lhs.node.size > 0
                let rhsKnown = rhs.node.size > 0
                if lhsKnown != rhsKnown { return lhsKnown }
                if lhsKnown && rhsKnown && lhs.node.size != rhs.node.size {
                    return lhs.node.size > rhs.node.size
                }
                return lhs.node.title.localizedStandardCompare(rhs.node.title) == .orderedAscending
            }
    }

    private func cachedApplicationClassification(title: String) -> ApplicationClassification {
        let kind = ApplicationClassificationKind.allCases.first { $0.displayTitle == title }
            ?? .otherApplication
        return ApplicationClassification(kind: kind)
    }

    private func storageExplorerRow(_ node: StorageExplorerNode, parentTotal: Int64) -> some View {
        let proportion = max(0.01, min(1, Double(node.size) / Double(parentTotal)))
        let pct = Int((Double(node.size) / Double(parentTotal) * 100).rounded())
        let drillable = node.route != nil
        return Button {
            if let route = node.route { storageExplorerRoute = route }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: node.iconName).foregroundStyle(node.color).font(.caption)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.title).fontWeight(.medium)
                            .lineLimit(1).truncationMode(.middle)
                        if !node.subtitle.isEmpty {
                            Text(node.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        if let path = node.path {
                            Text(path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if drillable {
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text("\(pct)%").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    Text(human(node.size))
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 88, alignment: .trailing)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.12))
                        Capsule()
                            .fill(LinearGradient(colors: [.teal, .cyan],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * proportion)
                    }
                }
                .frame(height: 7)
            }
            .contentShape(Rectangle())
            .interactiveRow(isActive: drillable)
        }
        .buttonStyle(.plain)
        .disabled(!drillable)
        .pointerCursor(drillable)
        .help(drillable ? "Open \(node.title)" : "")
    }

    private func residualRow(
        _ residual: Int64,
        parentTotal: Int64,
        title: String = "Files & smaller items here"
    ) -> some View {
        let proportion = max(0.01, min(1, Double(residual) / Double(parentTotal)))
        let pct = Int((Double(residual) / Double(parentTotal) * 100).rounded())
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc").foregroundStyle(.secondary).font(.caption)
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text("\(pct)%").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                Text(human(residual))
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 88, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule().fill(Color.secondary.opacity(0.35))
                        .frame(width: geo.size.width * proportion)
                }
            }
            .frame(height: 7)
        }
    }

    private func normalizedStorageExplorerRoute(
        _ route: StorageExplorerRoute,
        in result: ScanResult
    ) -> StorageExplorerRoute {
        switch route {
        case .rawFolder(let path, _):
            return size(ofPath: path, in: result) > 0 ? route : .root
        default:
            return route
        }
    }

    private func storageExplorerNodes(
        for route: StorageExplorerRoute,
        in result: ScanResult
    ) -> [StorageExplorerNode] {
        switch route {
        case .root:
            return storageExplorerRootNodes(in: result)
        case .audioProduction:
            return audioProductionCategoryNodes(in: result)
        case .audioCategory(let category):
            return audioProductionContributorNodes(for: category, in: result)
        case .applications:
            return applicationExplorerNodes(in: result)
        case .personalFiles:
            return personalExplorerNodes(in: result)
        case .rawFolder(let path, let source):
            return rawFolderExplorerNodes(path: path, source: source, in: result)
        }
    }

    private func storageExplorerTotal(
        for route: StorageExplorerRoute,
        nodes: [StorageExplorerNode],
        in result: ScanResult
    ) -> Int64 {
        switch route {
        case .root:
            return max(scanRootSize(result), nodes.reduce(Int64(0)) { $0 + $1.size })
        case .audioProduction, .audioCategory, .personalFiles:
            return nodes.reduce(Int64(0)) { $0 + $1.size }
        case .applications:
            return max(applicationsTotal(in: result), nodes.reduce(Int64(0)) { $0 + $1.size })
        case .rawFolder(let path, _):
            return size(ofPath: path, in: result)
        }
    }

    private func storageExplorerResidual(
        for route: StorageExplorerRoute,
        nodes: [StorageExplorerNode],
        parentTotal: Int64
    ) -> (title: String, size: Int64)? {
        let shownSum = nodes.reduce(Int64(0)) { $0 + $1.size }
        let residual = max(0, parentTotal - shownSum)
        guard residual > 0 else { return nil }

        switch route {
        case .applications:
            return ("Other applications and supporting files", residual)
        case .rawFolder:
            return ("Files & smaller items here", residual)
        default:
            return nil
        }
    }

    private func storageExplorerEmptyMessage(for route: StorageExplorerRoute) -> String {
        switch route {
        case .root:
            return "No browsable storage groups were found in this scan."
        case .audioProduction:
            return "No audio-production storage categories were found in this scan."
        case .audioCategory:
            return "No contributing folders were found for this category."
        case .applications:
            return "No installed applications were found in this scan."
        case .personalFiles:
            return "No familiar personal folders were found in this scan."
        case .rawFolder:
            return "This folder has no subfolders to drill into."
        }
    }

    private func storageExplorerCompactLimit(for route: StorageExplorerRoute) -> Int {
        switch route {
        case .root, .audioProduction, .personalFiles:
            return Int.max
        case .audioCategory, .rawFolder:
            return 25
        case .applications:
            return 30
        }
    }

    private func storageExplorerListID(for route: StorageExplorerRoute) -> String {
        switch route {
        case .root:
            return "storage-explorer-root"
        case .audioProduction:
            return "storage-explorer-audio-production"
        case .audioCategory(let category):
            return "storage-explorer-audio-category-\(category.rawValue)"
        case .applications:
            return "storage-explorer-applications"
        case .personalFiles:
            return "storage-explorer-personal-files"
        case .rawFolder(let path, let source):
            return "storage-explorer-raw-\(sourceBaseTitle(source))-\(normalizedPath(path))"
        }
    }

    private func storageExplorerItemNames(for route: StorageExplorerRoute) -> (singular: String, plural: String) {
        switch route {
        case .applications:
            return ("application", "applications")
        case .root, .audioProduction:
            return ("category", "categories")
        case .audioCategory, .personalFiles, .rawFolder:
            return ("folder", "folders")
        }
    }

    private func storageExplorerBreadcrumbItems(
        for route: StorageExplorerRoute,
        in result: ScanResult
    ) -> [StorageExplorerBreadcrumb] {
        var crumbs = [
            StorageExplorerBreadcrumb(
                id: "root",
                title: storageRootLabel(for: result),
                route: .root
            )
        ]

        switch route {
        case .root:
            break
        case .audioProduction:
            crumbs.append(StorageExplorerBreadcrumb(id: "audio", title: "Audio Production", route: .audioProduction))
        case .audioCategory(let category):
            crumbs.append(StorageExplorerBreadcrumb(id: "audio", title: "Audio Production", route: .audioProduction))
            crumbs.append(StorageExplorerBreadcrumb(id: "audio-\(category.rawValue)", title: category.rawValue, route: route))
        case .applications:
            crumbs.append(StorageExplorerBreadcrumb(id: "applications", title: "Applications", route: .applications))
        case .personalFiles:
            crumbs.append(StorageExplorerBreadcrumb(id: "personal", title: "Personal Files", route: .personalFiles))
        case .rawFolder(let path, let source):
            appendSourceBreadcrumbs(source, route: route, result: result, crumbs: &crumbs)
            appendRawPathBreadcrumbs(path: path, source: source, crumbs: &crumbs)
        }

        return crumbs
    }

    private func appendSourceBreadcrumbs(
        _ source: StorageExplorerSource,
        route: StorageExplorerRoute,
        result: ScanResult,
        crumbs: inout [StorageExplorerBreadcrumb]
    ) {
        switch source {
        case .audio(let category, _):
            crumbs.append(StorageExplorerBreadcrumb(id: "audio", title: "Audio Production", route: .audioProduction))
            crumbs.append(StorageExplorerBreadcrumb(id: "audio-\(category.rawValue)", title: category.rawValue, route: .audioCategory(category)))
        case .applications:
            crumbs.append(StorageExplorerBreadcrumb(id: "applications", title: "Applications", route: .applications))
        case .personal(let folder, _):
            crumbs.append(StorageExplorerBreadcrumb(id: "personal", title: "Personal Files", route: .personalFiles))
            if folder == .other {
                crumbs.append(StorageExplorerBreadcrumb(
                    id: "personal-other",
                    title: folder.rawValue,
                    route: .rawFolder(path: sourceBasePath(source), source: source)
                ))
            }
        case .otherMac:
            crumbs.append(StorageExplorerBreadcrumb(
                id: "other-mac",
                title: "Other Mac Storage",
                route: .rawFolder(path: sourceBasePath(source), source: source)
            ))
        }
    }

    private func appendRawPathBreadcrumbs(
        path: String,
        source: StorageExplorerSource,
        crumbs: inout [StorageExplorerBreadcrumb]
    ) {
        let base = sourceBasePath(source)
        let baseTitle = sourceBaseTitle(source)
        let currentPath = normalizedPath(path)
        let normalizedBase = normalizedPath(base)
        let baseAlreadyShown = sourceBaseIsAlreadyShown(source)

        guard currentPath == normalizedBase || pathContains(normalizedBase, candidate: currentPath) else {
            crumbs.append(StorageExplorerBreadcrumb(id: currentPath, title: displayName(forPath: currentPath), route: .rawFolder(path: currentPath, source: source)))
            return
        }

        if !baseAlreadyShown {
            crumbs.append(StorageExplorerBreadcrumb(id: normalizedBase, title: baseTitle, route: .rawFolder(path: normalizedBase, source: source)))
        }

        guard currentPath != normalizedBase else { return }
        let relative = normalizedBase == "/"
            ? String(currentPath.dropFirst(1))
            : String(currentPath.dropFirst(normalizedBase.count + 1))
        var accumulated = normalizedBase
        for component in relative.split(separator: "/").map(String.init) {
            accumulated = accumulated == "/" ? "/\(component)" : "\(accumulated)/\(component)"
            crumbs.append(StorageExplorerBreadcrumb(
                id: accumulated,
                title: component,
                route: .rawFolder(path: accumulated, source: source)
            ))
        }
    }

    private func storageExplorerRootNodes(in result: ScanResult) -> [StorageExplorerNode] {
        let audioTotal = audioProductionTotal(in: result)
        let appsTotal = applicationsTotal(in: result)
        let personalTotal = personalExplorerNodes(in: result).reduce(Int64(0)) { $0 + $1.size }
        let rootTotal = scanRootSize(result)
        let otherTotal = max(0, rootTotal - audioTotal - appsTotal - personalTotal)

        var nodes: [StorageExplorerNode] = []
        if audioTotal > 0 {
            nodes.append(StorageExplorerNode(
                id: "audio-production",
                title: "Audio Production",
                subtitle: "Plugins, presets, sample libraries, audio support files, and production content.",
                path: nil,
                size: audioTotal,
                iconName: "waveform",
                color: .teal,
                route: .audioProduction
            ))
        }
        if appsTotal > 0 {
            nodes.append(StorageExplorerNode(
                id: "applications",
                title: "Applications",
                subtitle: "Installed apps and their storage usage.",
                path: nil,
                size: appsTotal,
                iconName: "app.fill",
                color: .brown,
                route: .applications
            ))
        }
        if personalTotal > 0 {
            nodes.append(StorageExplorerNode(
                id: "personal-files",
                title: "Personal Files",
                subtitle: "Projects, documents, downloads, desktop files, and other user-created content.",
                path: nil,
                size: personalTotal,
                iconName: "person.crop.square.fill",
                color: .cyan,
                route: .personalFiles
            ))
        }
        if otherTotal >= 1_048_576 {
            let source = StorageExplorerSource.otherMac(basePath: result.rootPath)
            nodes.append(StorageExplorerNode(
                id: "other-mac-storage",
                title: "Other Mac Storage",
                subtitle: "Scanned storage that does not fit the studio, app, or personal groups.",
                path: nil,
                size: otherTotal,
                iconName: "internaldrive.fill",
                color: .secondary,
                route: .rawFolder(path: result.rootPath, source: source)
            ))
        }
        return nodes
    }

    private func audioProductionCategoryNodes(in result: ScanResult) -> [StorageExplorerNode] {
        let contributors = audioProductionContributors(in: result)
        let totals = Dictionary(grouping: contributors, by: \.category)
            .mapValues { $0.reduce(Int64(0)) { $0 + $1.size } }

        return StorageExplorerAudioCategory.allCases.compactMap { category in
            guard let total = totals[category], total > 0 else { return nil }
            return StorageExplorerNode(
                id: "audio-category-\(category.rawValue)",
                title: category.rawValue,
                subtitle: category.description,
                path: nil,
                size: total,
                iconName: category.iconName,
                color: audioCategoryColor(category),
                route: .audioCategory(category)
            )
        }
    }

    private func audioProductionContributorNodes(
        for category: StorageExplorerAudioCategory,
        in result: ScanResult
    ) -> [StorageExplorerNode] {
        audioProductionContributors(in: result)
            .filter { $0.category == category }
            .sorted { $0.size > $1.size }
            .map { contributor in
                let source = StorageExplorerSource.audio(category, basePath: contributor.path)
                return StorageExplorerNode(
                    id: contributor.id,
                    title: contributor.title,
                    subtitle: contributor.subtitle,
                    path: contributor.path,
                    size: contributor.size,
                    iconName: category.iconName,
                    color: audioCategoryColor(category),
                    route: controller.hasChildren(contributor.path) ? .rawFolder(path: contributor.path, source: source) : nil
                )
            }
    }

    private func applicationExplorerNodes(in result: ScanResult) -> [StorageExplorerNode] {
        let appItems = result.topFiles
            .filter { $0.category == .applications }
            .sorted { $0.size > $1.size }

        if !appItems.isEmpty {
            return appItems.map { item in
                let title = applicationDisplayName(item.displayName)
                let classification = ApplicationClassifier.classify(
                    displayName: title,
                    path: item.url.path
                )
                return StorageExplorerNode(
                    id: "app-\(item.url.path)",
                    title: title,
                    subtitle: classification.displayTitle,
                    path: item.url.path,
                    size: item.size,
                    iconName: "app.fill",
                    color: classification.isAudioApplication ? .teal : .brown,
                    route: controller.hasChildren(item.url.path)
                        ? .rawFolder(path: item.url.path, source: .applications(basePath: item.url.path))
                        : nil
                )
            }
        }

        return applicationFolderPaths(in: result).map { path in
            StorageExplorerNode(
                id: "app-folder-\(path)",
                title: displayName(forPath: path),
                subtitle: "Applications folder",
                path: path,
                size: size(ofPath: path, in: result),
                iconName: "folder.fill",
                color: .brown,
                route: .rawFolder(path: path, source: .applications(basePath: path))
            )
        }
    }

    private func personalExplorerNodes(in result: ScanResult) -> [StorageExplorerNode] {
        let home = normalizedPath(NSHomeDirectory())
        let audioPaths = audioProductionContributors(in: result).map(\.path)
        let projectPaths = personalProjectPaths(in: result)
        let homeApplications = "\(home)/Applications"

        let folderSpecs: [(StorageExplorerPersonalFolder, String, [String])] = [
            (.desktop, "\(home)/Desktop", audioPaths),
            (.documents, "\(home)/Documents", audioPaths + projectPaths),
            (.downloads, "\(home)/Downloads", audioPaths),
            (.music, "\(home)/Music", audioPaths + projectPaths),
            (.movies, "\(home)/Movies", audioPaths),
        ]

        var nodes: [StorageExplorerNode] = folderSpecs.compactMap { spec in
            let (folder, path, exclusions) = spec
            let size = adjustedFolderSize(path, in: result, excluding: exclusions)
            guard size > 0 else { return nil }
            return personalNode(folder: folder, path: path, size: size)
        }

        let projectTotal = totalSize(ofPaths: projectPaths, in: result, excluding: audioPaths)
        if projectTotal > 0 {
            let routePath = projectPaths.first ?? "\(home)/Projects"
            nodes.append(personalNode(folder: .projects, path: routePath, size: projectTotal))
        }

        let homeSize = size(ofPath: home, in: result)
        if homeSize > 0 {
            let namedRawPaths = folderSpecs.map { $0.1 } + projectPaths + [homeApplications]
            let excludedTotal = totalSize(ofPaths: namedRawPaths + audioPaths, in: result)
            let other = max(0, homeSize - excludedTotal)
            if other >= 1_048_576 {
                nodes.append(StorageExplorerNode(
                    id: "personal-other",
                    title: StorageExplorerPersonalFolder.other.rawValue,
                    subtitle: StorageExplorerPersonalFolder.other.description,
                    path: home,
                    size: other,
                    iconName: "folder.fill",
                    color: .secondary,
                    route: .rawFolder(path: home, source: .personal(.other, basePath: home))
                ))
            }
        }

        return nodes
    }

    private func rawFolderExplorerNodes(
        path: String,
        source: StorageExplorerSource,
        in result: ScanResult
    ) -> [StorageExplorerNode] {
        let parentTotal = max(size(ofPath: path, in: result), 1)
        return controller.children(of: path).map { child in
            let proportion = Double(child.size) / Double(parentTotal)
            let subtitle = proportion >= 0.01
                ? "\(Int((proportion * 100).rounded()))% of this level"
                : "Less than 1% of this level"
            return StorageExplorerNode(
                id: "raw-\(child.url.path)",
                title: child.displayName,
                subtitle: subtitle,
                path: child.url.path,
                size: child.size,
                iconName: "folder.fill",
                color: .teal,
                route: controller.hasChildren(child.url.path)
                    ? .rawFolder(path: child.url.path, source: source)
                    : nil
            )
        }
    }

    private func personalNode(
        folder: StorageExplorerPersonalFolder,
        path: String,
        size: Int64
    ) -> StorageExplorerNode {
        StorageExplorerNode(
            id: "personal-\(folder.rawValue)-\(path)",
            title: folder.rawValue,
            subtitle: folder.description,
            path: path,
            size: size,
            iconName: folder == .downloads ? "arrow.down.circle.fill" : "folder.fill",
            color: folder == .downloads ? .orange : .cyan,
            route: .rawFolder(path: path, source: .personal(folder, basePath: path))
        )
    }

    private func audioProductionTotal(in result: ScanResult) -> Int64 {
        audioProductionContributors(in: result).reduce(Int64(0)) { $0 + $1.size }
    }

    private func audioProductionContributors(in result: ScanResult) -> [StorageExplorerContributor] {
        var candidates: [StorageExplorerContributor] = []

        for item in result.audioSystemData.items {
            candidates.append(StorageExplorerContributor(
                id: "audio-system-\(item.path)",
                title: item.friendlyName,
                subtitle: item.category.rawValue,
                path: item.path,
                size: item.size,
                category: audioCategory(for: item.category),
                priority: 100
            ))
        }

        for (path, size) in result.folderSizes where size >= 1_048_576 {
            let normalized = normalizedPath(path)
            guard AudioSystemDataClassifier.classify(path: normalized) == nil,
                  let category = audioCategory(forFolderPath: normalized) else { continue }
            candidates.append(StorageExplorerContributor(
                id: "audio-folder-\(normalized)",
                title: displayName(forPath: normalized),
                subtitle: category.rawValue,
                path: normalized,
                size: size,
                category: category,
                priority: 70
            ))
        }

        for item in result.topFiles where item.category != .applications && isAudioAsset(item) {
            let path = normalizedPath(item.url.path)
            guard let category = audioCategory(for: item) else { continue }
            candidates.append(StorageExplorerContributor(
                id: "audio-item-\(path)",
                title: item.displayName,
                subtitle: item.category?.displayName ?? category.rawValue,
                path: path,
                size: item.size,
                category: category,
                priority: 40
            ))
        }

        return nonOverlappingContributors(candidates)
    }

    private func nonOverlappingContributors(
        _ candidates: [StorageExplorerContributor]
    ) -> [StorageExplorerContributor] {
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            if lhs.size != rhs.size { return lhs.size > rhs.size }
            return lhs.path < rhs.path
        }

        var selected: [StorageExplorerContributor] = []
        for candidate in sorted {
            if selected.contains(where: { pathsOverlap($0.path, candidate.path) }) { continue }
            selected.append(candidate)
        }
        return selected
    }

    private func audioCategory(for category: AudioSystemDataCategory) -> StorageExplorerAudioCategory {
        switch category {
        case .plugins: return .plugins
        case .presets: return .presets
        case .impulseResponses: return .impulseResponses
        case .pluginContent: return .pluginContent
        case .cachesDownloads: return .cachesDownloads
        }
    }

    private func audioCategory(for item: SizedItem) -> StorageExplorerAudioCategory? {
        switch item.category {
        case .projects:
            return .audioProjects
        case .plugins:
            return .plugins
        case .pluginData:
            return .pluginContent
        case .sampleLibraries:
            return .sampleLibraries
        case .audioFiles:
            return .audioFiles
        case .installers, .archives:
            return audioCategory(forFolderPath: item.url.path) ?? .cachesDownloads
        case .media, .other, nil:
            return audioCategory(forFolderPath: item.url.path) ?? .otherAudioStorage
        case .applications:
            return nil
        }
    }

    private func audioCategory(forFolderPath path: String) -> StorageExplorerAudioCategory? {
        let lower = normalizedPath(path).lowercased()
        if lower.contains("/library/audio/plug-ins/") { return .plugins }
        if lower.contains("/library/audio/presets/") { return .presets }
        if lower.contains("/library/audio/impulse responses/") { return .impulseResponses }
        if lower.contains("/library/application support/") && isAudioRelatedPath(lower) { return .pluginContent }
        if lower.contains("/audio/") && lower.contains("/application support/") { return .pluginContent }
        if lower.contains("/packdownloads/") || lower.contains("/library/caches/") && isAudioRelatedPath(lower) {
            return .cachesDownloads
        }
        if lower.contains("/sample libraries/") || lower.contains("/sample library/")
            || lower.contains("/samples/") || lower.contains("/loops/")
            || lower.contains("/apple loops/") || lower.contains("sample librar") {
            return .sampleLibraries
        }
        if lower.contains("/sessions/") || lower.contains("/session files/")
            || lower.contains("/daw projects/") || lower.contains("/logic projects/") {
            return .audioProjects
        }
        if lower.contains("/bounces/") || lower.contains("/exports/")
            || lower.contains("/stems/") || lower.contains("/mixes/")
            || lower.contains("/masters/") || lower.contains("/renders/") {
            return .audioFiles
        }
        if isAudioRelatedPath(lower) { return .otherAudioStorage }
        return nil
    }

    private func applicationsTotal(in result: ScanResult) -> Int64 {
        let folderTotal = totalSize(ofPaths: applicationFolderPaths(in: result), in: result)
        let appItemsTotal = result.topFiles
            .filter { $0.category == .applications }
            .reduce(Int64(0)) { $0 + $1.size }
        return max(folderTotal, appItemsTotal)
    }

    private func applicationFolderPaths(in result: ScanResult) -> [String] {
        let homeApplications = "\(normalizedPath(NSHomeDirectory()))/Applications"
        let candidates = ["/Applications", homeApplications, result.rootPath]
        return candidates
            .map(normalizedPath)
            .filter { path in
                size(ofPath: path, in: result) > 0
                    && (path.hasSuffix("/Applications") || path == "/Applications")
            }
            .removingDuplicates()
    }

    private func personalProjectPaths(in result: ScanResult) -> [String] {
        let home = normalizedPath(NSHomeDirectory())
        let candidates = [
            "\(home)/Projects",
            "\(home)/Sessions",
            "\(home)/Documents/Projects",
            "\(home)/Documents/Sessions",
            "\(home)/Music/Projects",
            "\(home)/Music/Sessions",
        ]
        return candidates
            .map(normalizedPath)
            .filter { size(ofPath: $0, in: result) > 0 }
            .removingDuplicates()
    }

    private func adjustedFolderSize(
        _ path: String,
        in result: ScanResult,
        excluding excludedPaths: [String]
    ) -> Int64 {
        let base = size(ofPath: path, in: result)
        guard base > 0 else { return 0 }
        let excluded = totalSize(
            ofPaths: excludedPaths.filter { pathContains(path, candidate: $0) },
            in: result
        )
        return max(0, base - excluded)
    }

    private func totalSize(
        ofPaths paths: [String],
        in result: ScanResult,
        excluding excludedPaths: [String] = []
    ) -> Int64 {
        let normalized = paths
            .map(normalizedPath)
            .filter { size(ofPath: $0, in: result) > 0 }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count < rhs.count }
                return lhs < rhs
            }

        var selected: [String] = []
        for path in normalized {
            if selected.contains(where: { pathsOverlap($0, path) }) { continue }
            selected.append(path)
        }

        let exclusions = excludedPaths.map(normalizedPath)
        return selected.reduce(Int64(0)) { total, path in
            let size = size(ofPath: path, in: result)
            let excluded = totalSize(
                ofPaths: exclusions.filter { pathContains(path, candidate: $0) },
                in: result
            )
            return total + max(0, size - excluded)
        }
    }

    private func scanRootSize(_ result: ScanResult) -> Int64 {
        max(size(ofPath: result.rootPath, in: result), result.totalSize)
    }

    private func size(ofPath path: String, in result: ScanResult) -> Int64 {
        let normalized = normalizedPath(path)
        if let size = result.folderSizes[normalized] { return size }
        if normalized == normalizedPath(result.rootPath) { return result.totalSize }
        return 0
    }

    private func pathContains(_ path: String, candidate: String) -> Bool {
        let parent = normalizedPath(path)
        let child = normalizedPath(candidate)
        if parent == "/" { return child.hasPrefix("/") }
        return parent == child || child.hasPrefix(parent + "/")
    }

    private func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        pathContains(lhs, candidate: rhs) || pathContains(rhs, candidate: lhs)
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func displayName(forPath path: String) -> String {
        let normalized = normalizedPath(path)
        let name = URL(fileURLWithPath: normalized).lastPathComponent
        return name.isEmpty ? "Mac Storage" : name
    }

    private func applicationDisplayName(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private func storageRootLabel(for result: ScanResult) -> String {
        let root = normalizedPath(result.rootPath)
        if root == "/" { return "Mac Storage" }
        if root.hasPrefix("/Volumes/") {
            let name = URL(fileURLWithPath: root).lastPathComponent
            return name.isEmpty ? "Drive Storage" : name
        }
        let name = URL(fileURLWithPath: root).lastPathComponent
        return name.isEmpty ? "Drive Storage" : name
    }

    private func sourceBasePath(_ source: StorageExplorerSource) -> String {
        switch source {
        case .audio(_, let basePath), .applications(let basePath),
             .personal(_, let basePath), .otherMac(let basePath):
            return basePath
        }
    }

    private func sourceBaseTitle(_ source: StorageExplorerSource) -> String {
        switch source {
        case .audio(_, let basePath), .applications(let basePath):
            return displayName(forPath: basePath)
        case .personal(let folder, let basePath):
            return folder == .other ? folder.rawValue : displayName(forPath: basePath)
        case .otherMac:
            return "Other Mac Storage"
        }
    }

    private func sourceBaseIsAlreadyShown(_ source: StorageExplorerSource) -> Bool {
        switch source {
        case .personal(let folder, _):
            return folder == .other
        case .otherMac:
            return true
        case .audio, .applications:
            return false
        }
    }

    private func audioCategoryColor(_ category: StorageExplorerAudioCategory) -> Color {
        switch category {
        case .plugins: return .indigo
        case .pluginContent: return .teal
        case .presets: return .blue
        case .sampleLibraries: return .mint
        case .impulseResponses: return .green
        case .audioProjects: return .purple
        case .audioFiles: return .cyan
        case .cachesDownloads: return .orange
        case .otherAudioStorage: return .secondary
        }
    }

    private func fileRow(_ item: SizedItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName).lineLimit(1).truncationMode(.middle)
                Text(item.parentPath)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let c = item.category {
                HStack(spacing: 5) {
                    Circle().fill(c.color).frame(width: 7, height: 7)
                    Text(c.displayName).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(human(item.size))
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func largestAudioAssets(in result: ScanResult) -> [SizedItem] {
        result.topFiles
            .filter(isAudioAsset)
            .sorted { lhs, rhs in
                if lhs.size != rhs.size { return lhs.size > rhs.size }
                let lhsScore = audioAssetPriority(lhs)
                let rhsScore = audioAssetPriority(rhs)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhs.displayName < rhs.displayName
            }
    }

    private func otherLargeApplications(in result: ScanResult) -> [SizedItem] {
        result.topFiles
            .filter { item in
                item.category == .applications
                    && !isAudioAsset(item)
                    && item.size >= 20 * 1_024 * 1_024 * 1_024
            }
            .sorted { $0.size > $1.size }
    }

    private func isAudioAsset(_ item: SizedItem) -> Bool {
        guard let category = item.category else { return isAudioRelatedPath(item.url.path) }
        switch category {
        case .projects, .plugins, .pluginData, .sampleLibraries, .audioFiles:
            return true
        case .applications:
            return isAudioApplication(item)
        case .installers, .archives:
            return isAudioRelatedPath(item.url.path)
        case .media, .other:
            return isAudioRelatedPath(item.url.path)
        }
    }

    private func audioAssetPriority(_ item: SizedItem) -> Int {
        switch item.category {
        case .projects: return 90
        case .sampleLibraries: return 85
        case .pluginData: return 80
        case .plugins: return 75
        case .audioFiles: return 70
        case .applications: return isAudioApplication(item) ? 65 : 0
        case .installers: return isAudioRelatedPath(item.url.path) ? 60 : 0
        case .archives: return isAudioRelatedPath(item.url.path) ? 55 : 0
        case .media, .other, nil: return isAudioRelatedPath(item.url.path) ? 50 : 0
        }
    }

    private func isAudioApplication(_ item: SizedItem) -> Bool {
        guard item.category == .applications else { return false }
        return ApplicationClassifier.classify(
            displayName: applicationDisplayName(item.displayName),
            path: item.url.path
        ).isAudioApplication
    }

    private func isAudioRelatedPath(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let lowerPath = normalized.lowercased()
        let parent = URL(fileURLWithPath: normalized).deletingLastPathComponent().path

        if AudioSystemDataClassifier.classify(path: normalized) != nil { return true }
        if AudioSystemDataClassifier.classify(path: parent) != nil { return true }

        return audioAssetPathMarkers.contains { marker in
            lowerPath.contains(marker)
        }
    }

    private var audioAssetPathMarkers: [String] {
        [
            "/ableton/",
            "/audio music apps/",
            "/audio/impulse responses/",
            "/audio/plug-ins/",
            "/audio/presets/",
            "/avid/",
            "/cubase/",
            "/eastwest/",
            "/factory library",
            "/factory sounds",
            "/garageband/",
            "/izotope/",
            "/kontakt",
            "/logic/",
            "/native instruments/",
            "/output/",
            "/plugin alliance/",
            "/pro tools/",
            "/sample libraries/",
            "/samples/",
            "/sessions/",
            "/slate digital/",
            "/sound libraries/",
            "/spitfire",
            "/studio one/",
            "/superior drummer",
            "/toontrack/",
            "/uvi/",
            "/waves/",
            "/xln audio/",
            "addictive drums",
            "bounce",
            "bounces",
            "ezdrummer",
            "exports",
            "keyscape",
            "mixes",
            "omnisphere",
        ]
    }

    private func toggleAudioGuidance(for path: String) {
        withAnimation(.easeInOut(duration: 0.16)) {
            if expandedAudioGuidancePaths.contains(path) {
                expandedAudioGuidancePaths.remove(path)
            } else {
                expandedAudioGuidancePaths.insert(path)
            }
        }
    }

    private func revealAudioFolderInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            appAlert = AppAlert(
                title: "Folder Not Found",
                message: "SessionSweep could not reveal this folder because it no longer exists at the scanned path. Nothing was changed."
            )
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyAudioFolderPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        showToast("Path copied")
    }

    @ViewBuilder
    private func keepSafeButton(
        path: String,
        protectedItem: KeepSafeItem?,
        itemType: KeepSafeItemType?,
        size: Int64,
        classification: String?,
        category: String?
    ) -> some View {
        let protectedItem = protectedItem ?? keepSafeStore.protectedItem(for: path)
        let isBusy = isKeepSafeOperationInProgress(path: path, protectedItem: protectedItem)
        Button {
            guard !isBusy else { return }
            if let protectedItem {
                pendingRemoveKeepSafeItem = protectedItem
            } else {
                addKeepSafe(
                    path: path,
                    itemType: itemType,
                    size: size,
                    classification: classification,
                    category: category
                )
            }
        } label: {
            HStack(spacing: 5) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.62)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: protectedItem == nil ? "lock" : "lock.fill")
                }
                Text(isBusy ? "Protecting..." : "Keep Safe")
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(protectedItem == nil && !isBusy ? Color.secondary : Color.teal)
        .interactiveHover(isSelected: protectedItem != nil, cornerRadius: 7, tint: .teal)
        .disabled(isBusy)
        .pointerCursor(!isBusy)
        .help(protectedItem == nil ? "Keep Safe" : "Remove from Keep Safe")
        .accessibilityLabel(isBusy ? "Protecting" : (protectedItem == nil ? "Keep Safe" : "Remove from Keep Safe"))
    }

    @ViewBuilder
    private func keepSafeMenuButton(
        path: String,
        itemType: KeepSafeItemType?,
        size: Int64,
        classification: String?,
        category: String?
    ) -> some View {
        let protectedItem = keepSafeStore.protectedItem(for: path)
        let isBusy = isKeepSafeOperationInProgress(path: path, protectedItem: protectedItem)
        if isBusy {
            Button("Protecting...") {}
                .disabled(true)
        } else if let protectedItem {
            Button("Remove from Keep Safe") {
                pendingRemoveKeepSafeItem = protectedItem
            }
        } else {
            Button("Keep Safe") {
                addKeepSafe(
                    path: path,
                    itemType: itemType,
                    size: size,
                    classification: classification,
                    category: category
                )
            }
        }
    }

    private func addKeepSafe(
        path: String,
        itemType: KeepSafeItemType?,
        size: Int64,
        classification: String?,
        category: String?
    ) {
        let pathKey = keepSafeOperationPathKey(path)
        guard !keepSafePathsInProgress.contains(pathKey) else { return }
        debugLog("Local Keep Safe persistence starting for \(pathKey)")
        keepSafePathsInProgress.insert(pathKey)
        duplicateSelection.remove(path)
        installerSelection.remove(path)
        pruneSelectionsAgainstPresentationModel()

        Task { @MainActor in
            await Task.yield()
            do {
                _ = try keepSafeStore.addPersisting(
                    path: path,
                    itemType: itemType,
                    size: size,
                    classification: classification,
                    category: category
                )
                debugLog("Local Keep Safe persistence finished for \(pathKey)")
                pruneSelectionsAgainstPresentationModel()
                showToast("Added to Keep Safe")
            } catch {
                appAlert = AppAlert(
                    title: "Could Not Keep Safe",
                    message: "SessionSweep could not save this Keep Safe change. Nothing was moved or deleted.\n\n\(error.localizedDescription)"
                )
            }
            keepSafePathsInProgress.remove(pathKey)
            pruneSelectionsAgainstPresentationModel()
        }
    }

    private func removeKeepSafe(_ item: KeepSafeItem) {
        let pathKeys = keepSafeOperationPathKeys(for: item)
        guard !keepSafeItemIDsInProgress.contains(item.id) else { return }
        debugLog("Local Keep Safe removal starting for \(item.id)")
        keepSafeItemIDsInProgress.insert(item.id)
        keepSafePathsInProgress.formUnion(pathKeys)
        duplicateSelection.remove(item.originalPath)
        duplicateSelection.remove(item.resolvedPath)
        installerSelection.remove(item.originalPath)
        installerSelection.remove(item.resolvedPath)
        pruneSelectionsAgainstPresentationModel()

        Task { @MainActor in
            await Task.yield()
            do {
                _ = try keepSafeStore.removePersisting(id: item.id)
                debugLog("Local Keep Safe removal finished for \(item.id)")
                showToast("Removed from Keep Safe")
            } catch {
                appAlert = AppAlert(
                    title: "Could Not Remove Keep Safe",
                    message: "SessionSweep could not save this Keep Safe change. The item remains protected.\n\n\(error.localizedDescription)"
                )
            }
            keepSafeItemIDsInProgress.remove(item.id)
            keepSafePathsInProgress.subtract(pathKeys)
            pruneSelectionsAgainstPresentationModel()
        }
    }

    private func keepSafeOperationPathKey(_ path: String) -> String {
        KeepSafeStore.standardizedPath(path)
    }

    private func keepSafeOperationPathKeys(for item: KeepSafeItem) -> Set<String> {
        [
            keepSafeOperationPathKey(item.originalPath),
            keepSafeOperationPathKey(item.resolvedPath)
        ]
    }

    private func isKeepSafeOperationInProgress(
        path: String,
        protectedItem: KeepSafeItem?
    ) -> Bool {
        isKeepSafeOperationInProgress(
            pathKey: keepSafeOperationPathKey(path),
            protectedItem: protectedItem
        )
    }

    private func isKeepSafeOperationInProgress(
        pathKey: String,
        protectedItem: KeepSafeItem?
    ) -> Bool {
        if isKeepSafePathKeyInProgress(pathKey) { return true }
        guard let protectedItem else { return false }
        return keepSafeItemIDsInProgress.contains(protectedItem.id)
    }

    private func isKeepSafePathInProgress(_ path: String) -> Bool {
        isKeepSafePathKeyInProgress(keepSafeOperationPathKey(path))
    }

    private func isKeepSafePathKeyInProgress(_ pathKey: String) -> Bool {
        keepSafePathsInProgress.contains(pathKey)
    }

    private func revealKeepSafeItem(_ item: KeepSafeItem) {
        let path = keepSafeStore.currentPath(for: item)
        guard FileManager.default.fileExists(atPath: path) else {
            appAlert = AppAlert(
                title: "File Not Found",
                message: "This item may have been moved, removed, or be on a disconnected drive. Run a new scan to refresh available results."
            )
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func refreshKeepSafeFromCurrentScan() {
        keepSafeStore.refreshAvailability()
        guard let result = controller.result else { return }
        var paths = result.folderSizes
        for item in result.topFiles {
            paths[item.url.path] = item.size
        }
        for item in result.installerFiles {
            paths[item.url.path] = item.size
        }
        keepSafeStore.updateSeen(paths: paths)
    }

    private func actionableDuplicateReclaimable(in result: ScanResult) -> Int64 {
        result.duplicateGroups.reduce(Int64(0)) { total, group in
            total + actionableDuplicateBytes(in: group, keeper: recommendedKeeper(in: group))
        }
    }

    private func actionableDuplicateBytes(in group: DuplicateGroup, keeper: String?) -> Int64 {
        let count = group.paths.filter { path in
            path != keeper && isStageableDuplicatePath(path)
        }.count
        return Int64(count) * group.fileSize
    }

    private func isStageableInstallerPath(_ path: String) -> Bool {
        if isKeepSafePathInProgress(path) { return false }
        if let model = resultsPresentationModel {
            return model.installerStageablePaths.contains(path)
        }
        return !keepSafeStore.isProtected(path)
    }

    private func revealDifferentNameFileInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            appAlert = AppAlert(
                title: "File Not Found",
                message: "This file may have been moved or removed since the scan. Run a new scan to refresh the results."
            )
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        showToast("Path copied")
    }

    private func copyFilename(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(URL(fileURLWithPath: path).lastPathComponent, forType: .string)
        showToast("Filename copied")
    }

    private func showToast(_ message: String) {
        let toast = ActionToast(message: message)
        actionToast = toast

        Task {
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            await MainActor.run {
                if actionToast == toast {
                    actionToast = nil
                }
            }
        }
    }

    private func pathContext(_ path: String, sharedParent: String?) -> String {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        guard let sharedParent else { return path }
        if parent == sharedParent {
            return shortDisplayPath(parent)
        }
        if path.hasPrefix(sharedParent + "/") {
            return String(path.dropFirst(sharedParent.count + 1))
        }
        return path
    }

    private func shortDisplayPath(_ path: String) -> String {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        if normalized == home { return "~" }
        if normalized.hasPrefix(home + "/") {
            return "~/" + String(normalized.dropFirst(home.count + 1))
        }

        let components = normalized.split(separator: "/").map(String.init)
        guard components.count > 3 else { return normalized }
        return components.suffix(3).joined(separator: "/")
    }

    private func resetDuplicateSelection() {
        guard let model = resultsPresentationModel else {
            duplicateSelection.removeAll()
            return
        }
        duplicateSelection.setSelection(
            model.recommendedDuplicateSelection,
            blockedPathKeys: keepSafePathsInProgress
        )
    }

    private func selectAllDuplicates(_ r: ScanResult) {
        let candidates = resultsPresentationModel?.duplicateStageablePaths ?? Set(r.duplicateGroups.flatMap { group in
            group.paths.filter(isStageableDuplicatePath)
        })
        duplicateSelection.setSelection(candidates, blockedPathKeys: keepSafePathsInProgress)
        showToast("\(duplicateSelection.selectedCount) file\(duplicateSelection.selectedCount == 1 ? "" : "s") selected")
    }

    private func deselectAllDuplicates() {
        duplicateSelection.removeAll()
        showToast("Selection cleared")
    }

    private func selectAllInstallers(_ items: [InstallerPresentationRow]) {
        installerSelection.setSelection(Set(items.filter(\.isStageable).map(\.path)), blockedPathKeys: keepSafePathsInProgress)
        showToast("\(installerSelection.selectedCount) installer\(installerSelection.selectedCount == 1 ? "" : "s") selected")
    }

    private func deselectAllInstallers() {
        installerSelection.removeAll()
        showToast("Selection cleared")
    }

    private func selectedDuplicateBytes(in result: ScanResult) -> Int64 {
        result.duplicateGroups.reduce(Int64(0)) { total, group in
            total + Int64(group.paths.filter {
                duplicateSelection.contains($0) && isStageableDuplicatePath($0)
            }.count) * group.fileSize
        }
    }

    private func isStageableDuplicatePath(_ path: String) -> Bool {
        if isKeepSafePathInProgress(path) { return false }
        if let model = resultsPresentationModel {
            return model.duplicateStageablePaths.contains(path)
        }
        return !DuplicateSafetyClassifier.isNeverRecommend(path: path) && !keepSafeStore.isProtected(path)
    }

    private func duplicateRecommendationLabel(
        isKeeper: Bool,
        safetyClassification: DuplicateSafetyClassification
    ) -> String {
        if safetyClassification.isNeverRecommend { return safetyClassification.label }
        return isKeeper ? "Recommended keep" : "Recommended staging"
    }

    private func duplicateRecommendationDescription(
        isKeeper: Bool,
        safetyClassification: DuplicateSafetyClassification
    ) -> String {
        if safetyClassification.isNeverRecommend {
            return safetyClassification.description
        }
        return isKeeper ? "SessionSweep recommends keeping this copy." : "SessionSweep recommends staging this redundant copy."
    }

    private func recommendedKeeper(in group: DuplicateGroup) -> String? {
        group.paths.max { lhs, rhs in
            isBetterKeeper(rhs, than: lhs)
        }
    }

    private func isBetterKeeper(_ lhs: String, than rhs: String) -> Bool {
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

    private func locationScore(for path: String) -> Int {
        let lower = path.lowercased()
        var score = 10
        if lower.contains("/music/") || lower.contains("/documents/") ||
            lower.contains("/projects/") || lower.contains("/sessions/") {
            score += 8
        }
        if lower.contains("/downloads/") || lower.contains("/desktop/") ||
            lower.contains("/trash/") || lower.contains("/caches/") ||
            lower.contains("/tmp/") || lower.contains("/temp/") ||
            lower.contains("backup") || lower.contains(" copy") {
            score -= 8
        }
        return score
    }

    private func modificationDate(for path: String) -> TimeInterval {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
    }

    private func moveSelectedToStaging() {
//        guard hasValidLicense else {
//            appAlert = AppAlert(
//                title: "License Required",
//                message: "Moving duplicate files to SessionSweep Staging is a paid feature. Activate a valid license to use Move to Staging."
//            )
//            return
//        }

        guard !isMovingToStaging else { return }
        isMovingToStaging = true
        defer { isMovingToStaging = false }

        let paths = duplicateSelection.selectedPaths.sorted()
        var movedOriginalPaths: Set<String> = []
        var skippedCount = 0
        var protectedSkippedCount = 0

        for path in paths {
            guard isStageableDuplicatePath(path) else {
                protectedSkippedCount += keepSafeStore.isProtected(path) ? 1 : 0
                skippedCount += keepSafeStore.isProtected(path) ? 0 : 1
                continue
            }

            do {
                let staged = try StagingManager.moveToStaging(originalPath: path)
                movedOriginalPaths.insert(staged.originalPath)
            } catch StagingError.keepSafeProtected(_) {
                protectedSkippedCount += 1
            } catch {
                skippedCount += 1
            }
        }

        if !movedOriginalPaths.isEmpty {
            applyMovedDuplicatePaths(movedOriginalPaths)
            duplicateSelection.subtract(movedOriginalPaths)
            refreshStaging()
            showToast("\(movedOriginalPaths.count) file\(movedOriginalPaths.count == 1 ? "" : "s") moved to Staging")
        }

        if protectedSkippedCount > 0 {
            appAlert = protectedSkippedAlert(count: protectedSkippedCount)
        } else if skippedCount > 0 {
            appAlert = skippedMoveAlert(count: skippedCount)
        }
    }

    private func applyMovedDuplicatePaths(_ movedPaths: Set<String>) {
        guard var result = controller.result else { return }
        result.duplicateGroups = result.duplicateGroups.compactMap { group in
            let remaining = group.paths.filter { !movedPaths.contains($0) }
            guard remaining.count >= 2 else { return nil }
            return DuplicateGroup(fileSize: group.fileSize, paths: remaining, sameName: group.sameName)
        }
        result.duplicateReclaimable = result.duplicateGroups.reduce(0) { $0 + $1.reclaimable }
        controller.result = result
    }

    private func moveSelectedInstallersToStaging() {
        guard !isMovingInstallersToStaging else { return }
        isMovingInstallersToStaging = true
        defer { isMovingInstallersToStaging = false }

        let paths = installerSelection.selectedPaths.sorted()
        var movedOriginalPaths: Set<String> = []
        var skippedCount = 0
        var protectedSkippedCount = 0

        for path in paths {
            guard isStageableInstallerPath(path) else {
                protectedSkippedCount += 1
                continue
            }
            do {
                let staged = try StagingManager.moveToStaging(originalPath: path)
                movedOriginalPaths.insert(staged.originalPath)
            } catch StagingError.keepSafeProtected(_) {
                protectedSkippedCount += 1
            } catch {
                skippedCount += 1
            }
        }

        if !movedOriginalPaths.isEmpty {
            applyMovedInstallerPaths(movedOriginalPaths)
            installerSelection.subtract(movedOriginalPaths)
            refreshStaging()
            showToast("\(movedOriginalPaths.count) installer\(movedOriginalPaths.count == 1 ? "" : "s") moved to Staging")
        }

        if protectedSkippedCount > 0 {
            appAlert = protectedSkippedAlert(count: protectedSkippedCount)
        } else if skippedCount > 0 {
            appAlert = skippedMoveAlert(count: skippedCount)
        }
    }

    private func applyMovedInstallerPaths(_ movedPaths: Set<String>) {
        guard var result = controller.result else { return }
        result.installerFiles = result.installerFiles.filter { !movedPaths.contains($0.url.path) }
        controller.result = result
    }

    private func refreshStaging() {
        do {
            stagedFiles = try StagingManager.stagedFiles()
        } catch {
            appAlert = AppAlert(title: "Could Not Read Staging", message: error.localizedDescription)
        }
    }

    private func restore(_ file: StagedFile) {
        do {
            try StagingManager.restore(file)
            refreshStaging()
            showToast("File restored")
        } catch {
            appAlert = skippedRestoreAlert(count: 1)
        }
    }

    private func restoreAllStaged() {
        guard !isRestoringAllStaged else { return }
        isRestoringAllStaged = true
        defer { isRestoringAllStaged = false }

        let originalCount = stagedFiles.count
        var skippedCount = 0
        for file in stagedFiles {
            do {
                try StagingManager.restore(file)
            } catch {
                skippedCount += 1
            }
        }
        refreshStaging()

        if skippedCount > 0 {
            appAlert = skippedRestoreAlert(count: skippedCount)
        } else if originalCount > 0 {
            showToast("\(originalCount) file\(originalCount == 1 ? "" : "s") restored")
        }
    }

    private func skippedMoveAlert(count: Int) -> AppAlert {
        AppAlert(
            title: "Some Files Were Skipped Safely",
            message: "SessionSweep couldn't move some protected files because macOS or the plugin vendor prevents changes to them.\n\nNo protected files were deleted. SessionSweep skipped those files and moved the remaining selected files when possible.\n\n\(skippedProtectedFilesLine(count))"
        )
    }

    private func protectedSkippedAlert(count: Int) -> AppAlert {
        AppAlert(
            title: "Protected Items Were Skipped",
            message: "SessionSweep skipped \(count) item\(count == 1 ? "" : "s") marked Keep Safe. No protected items were moved."
        )
    }

    private func skippedRestoreAlert(count: Int) -> AppAlert {
        AppAlert(
            title: "Some Files Were Skipped Safely",
            message: "SessionSweep could not restore some files because macOS, the plugin vendor, or the original location prevented the move. No staged files were deleted.\n\n\(skippedFilesLine(count))"
        )
    }

    private func skippedProtectedFilesLine(_ count: Int) -> String {
        "\(count) protected file\(count == 1 ? " was" : "s were") skipped."
    }

    private func skippedFilesLine(_ count: Int) -> String {
        "Skipped \(count) file\(count == 1 ? "" : "s")."
    }

    private func clearStaging() {
        guard !isClearingStaging else { return }
        isClearingStaging = true
        defer { isClearingStaging = false }

        let originalCount = stagedFiles.count
        do {
            try StagingManager.clearStaging()
            refreshStaging()
            if originalCount > 0 {
                showToast("Staging cleared")
            }
        } catch {
            appAlert = AppAlert(title: "Could Not Clear Staging", message: error.localizedDescription)
        }
    }

    private var headlineLocation: String {
        let u = URL(fileURLWithPath: controller.scannedPath)
        let n = u.lastPathComponent
        return (n.isEmpty || n == "/") ? controller.scannedPath : n
    }

    private func pickAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        controller.start(url: url)
    }

    private func human(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}

private struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview { ContentView() }
