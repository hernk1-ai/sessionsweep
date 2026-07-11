import Foundation
import CryptoKit

nonisolated final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    func cancel() { lock.lock(); _cancelled = true; lock.unlock() }
}

nonisolated enum ScanPhase: Sendable { case scanning, findingDuplicates }

nonisolated enum Category: String, CaseIterable, Sendable, Hashable {
    case projects        = "Projects"
    case plugins         = "Plugins"
    case pluginData      = "Plugin Data"
    case sampleLibraries = "Sample Libraries"
    case audioFiles      = "Audio Files"
    case applications    = "Applications"
    case media           = "Media"
    case installers      = "Installers"
    case archives        = "Archives"
    case other           = "Other"
    var displayName: String { rawValue }

    private static let dawExts: Set<String> = [
        "logicx","logic","ptx","ptf","ptxt","als","alp","cpr","cbp",
        "song","rpp","flp","band","reason","npr","sng","mmp"
    ]
    private static let pluginExts: Set<String> = [
        "vst","vst3","component","clap","aax","aaxplugin","aubundle","lv2"
    ]
    private static let pluginDataExts: Set<String> = [
        "nkx","nki","ncw","nkm","nkb","nkc","xpak","blob","px",
        "exs","fxp","fxb","aupreset","vstpreset","sf2","sfz"
    ]
    private static let appExts: Set<String>       = ["app"]
    private static let installerExts: Set<String> = ["dmg","pkg","mpkg"]
    private static let archiveExts: Set<String>   = ["zip","rar","7z","gz","tar","tgz","bz2","sit"]
    private static let audioExts: Set<String>     = ["wav","aif","aiff","aifc","caf","mp3","m4a","flac","ogg","aac","wma"]
    private static let mediaExts: Set<String>     = ["mp4","mov","m4v","avi","mkv","wmv","jpg","jpeg","png","gif","heic","tiff","tif","psd","raw","cr2","arw"]

    static func classify(url: URL, isPackage: Bool = false) -> Category {
        let ext = url.pathExtension.lowercased()
        if dawExts.contains(ext)        { return .projects }
        if pluginExts.contains(ext)     { return .plugins }
        if appExts.contains(ext)        { return .applications }
        if installerExts.contains(ext)  { return .installers }
        if archiveExts.contains(ext)    { return .archives }
        if pluginDataExts.contains(ext) { return .pluginData }

        let p = url.path.lowercased()
        if p.contains("/audio/plug-ins/") { return .plugins }
        if p.contains("/application support/") &&
            (p.contains("/ujam") || p.contains("/xln audio") || p.contains("/kush audio")
             || p.contains("/native instruments") || p.contains("/output")
             || p.contains("/spectrasonics") || p.contains("/logic")
             || p.contains("/garageband") || p.contains("/reason")
             || p.contains("/izotope") || p.contains("/waves")) {
            return .pluginData
        }
        if p.contains("/applications/waves/data") { return .pluginData }
        if p.contains("/library/audio/presets")  { return .pluginData }
        if p.contains("/library/audio/impulse responses") { return .sampleLibraries }
        if p.contains("/library/audio/apple loops")        { return .sampleLibraries }
        if p.contains("/splice") || p.contains("/spitfire") || p.contains("sample librar")
            || p.contains("/samples") || p.contains("all-samples") || p.contains("/loops") {
            return .sampleLibraries
        }
        if p.contains("media.localized") || p.contains("/movies/") || p.contains("/pictures/") {
            return .media
        }
        if audioExts.contains(ext) { return .audioFiles }
        if mediaExts.contains(ext) { return .media }
        return .other
    }
}

nonisolated struct SizedItem: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let size: Int64
    var category: Category? = nil
    var displayName: String {
        let n = url.lastPathComponent
        return n.isEmpty ? url.path : n
    }
    var parentPath: String { url.deletingLastPathComponent().path }
}

nonisolated struct DuplicateGroup: Identifiable, Sendable {
    let id = UUID()
    let fileSize: Int64
    let paths: [String]
    let sameName: Bool
    var count: Int { paths.count }
    var reclaimable: Int64 { fileSize * Int64(max(0, count - 1)) }
    var displayName: String {
        guard let first = paths.first else { return "?" }
        return (first as NSString).lastPathComponent
    }
}

// Progress now reports itemsSeen (folders + files) so the UI moves immediately.
nonisolated struct ScanProgress: Sendable {
    var phase: ScanPhase
    var count: Int
    var total: Int64
    var label: String
    var itemsSeen: Int = 0
}

nonisolated struct ScanResult: Sendable {
    var totalSize: Int64 = 0
    var fileCount: Int = 0
    var unreadableCount: Int = 0
    var excludedSystemCount: Int = 0
    var cancelled: Bool = false
    var elapsed: TimeInterval = 0
    var rootPath: String = "/"
    var topFiles: [SizedItem] = []
    var categoryTotals: [Category: Int64] = [:]
    var folderSizes: [String: Int64] = [:]
    var folderChildren: [String: [String]] = [:]
    var audioSystemData: AudioSystemDataSummary = AudioSystemDataSummary()
    var duplicateGroups: [DuplicateGroup] = []
    var identicalContentGroups: [DuplicateGroup] = []
    var duplicateReclaimable: Int64 = 0
    var identicalContentReclaimable: Int64 = 0
    var installerFiles: [SizedItem] = []
}

nonisolated enum Scanner {
    static let minDupSize: Int64 = 1_048_576
    static let browserMinSize: Int64 = 1_048_576
    private nonisolated static let topFilesLimit = 100

    private static let bundleLikeExts: Set<String> = [
        "swiftmodule","framework","bundle","app","component","vst","vst3",
        "clap","aaxplugin","kext","plugin","xpc","prefpane","qlgenerator"
    ]

    private static let excludedRoots = [
        "/System", "/private", "/usr", "/bin", "/sbin",
        "/dev", "/cores", "/Network", "/opt", "/.vol",
        "/Library/Updates"
    ]

    // Folders that indicate developer tooling artifacts rather than user content.
    // These are excluded wherever they appear in the tree (not just at fixed roots),
    // since things like node_modules can be nested many levels deep inside any
    // project folder. Matching skips the whole subtree via skipDescendants(),
    // so this also avoids wasted work walking into huge dependency trees.
    private static func isDeveloperArtifact(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name == "node_modules" { return true }
        if name == ".git" { return true }
        if name == "Pods" { return true }
        if name == ".build" { return true }
        let p = url.path
        if p.contains("/Library/Developer/Xcode/DerivedData") { return true }
        return false
    }

    private static func isExcluded(_ url: URL) -> Bool {
        let p = url.path
        for root in excludedRoots where p == root || p.hasPrefix(root + "/") { return true }
        if p.contains("/Library/Developer") { return true }
        if p.contains("/Library/Application Support/Adobe") { return true }
        if isDeveloperArtifact(url) { return true }
        return false
    }

    private static func allocatedSize(of dir: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let e = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles], errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            guard let v = try? f.resourceValues(forKeys: keys),
                  v.isSymbolicLink != true, v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
        }
        return total
    }

    static nonisolated func scan(
        root: URL,
        cancel: CancelToken? = nil,
        progress: (@Sendable (ScanProgress) -> Void)? = nil
    ) -> ScanResult {
        let start = Date()
        var result = ScanResult()
        var unreadable = 0
        var itemsSeen = 0   // every entry the walker yields, dirs included

        let keys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey, .fileSizeKey,
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
        ]

        var folderSizes: [String: Int64] = [:]
        var sizeBuckets: [Int64: [String]] = [:]
        var seenDuplicateTargets: Set<String> = []
        let rootPath = root.standardizedFileURL.path
        result.rootPath = rootPath

        func addToAncestors(of itemURL: URL, _ size: Int64) {
            var current = itemURL.deletingLastPathComponent().standardizedFileURL
            while true {
                folderSizes[current.path, default: 0] += size
                if current.path == rootPath { break }
                let up = current.deletingLastPathComponent().standardizedFileURL
                if up.path == current.path { break }
                current = up
            }
        }

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in unreadable += 1; return true }
        ) else {
            result.elapsed = Date().timeIntervalSince(start)
            return result
        }

        for case let url as URL in enumerator {
            // Heartbeat: fires on the very first item and every 500 items thereafter,
            // counting directories too — so the display never sits frozen at zero.
            itemsSeen += 1
            if itemsSeen == 1 || itemsSeen % 500 == 0 {
                let folder = url.deletingLastPathComponent().lastPathComponent
                progress?(ScanProgress(phase: .scanning, count: result.fileCount,
                                       total: result.totalSize, label: folder,
                                       itemsSeen: itemsSeen))
                if cancel?.isCancelled == true { result.cancelled = true; break }
            }

            guard let v = try? url.resourceValues(forKeys: keys) else {
                unreadable += 1; continue
            }
            if v.isSymbolicLink == true { continue }

            if v.isDirectory == true {
                if isExcluded(url) {
                    result.excludedSystemCount += 1
                    enumerator.skipDescendants()
                    continue
                }
                if v.isPackage == true {
                    let size = allocatedSize(of: url)
                    let cat = Category.classify(url: url, isPackage: true)
                    result.totalSize += size
                    result.fileCount += 1
                    result.categoryTotals[cat, default: 0] += size
                    insertTop(&result.topFiles,
                              item: SizedItem(url: url, size: size, category: cat), limit: topFilesLimit)
                    addToAncestors(of: url, size)
                    enumerator.skipDescendants()
                }
                continue
            }

            guard v.isRegularFile == true else { continue }

            let size = Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
            let cat = Category.classify(url: url)
            result.totalSize += size
            result.fileCount += 1
            result.categoryTotals[cat, default: 0] += size
            let sizedItem = SizedItem(url: url, size: size, category: cat)
            insertTop(&result.topFiles, item: sizedItem, limit: topFilesLimit)
            if cat == .installers {
                result.installerFiles.append(sizedItem)
            }
            addToAncestors(of: url, size)

            let logical = Int64(v.fileSize ?? 0)
            if logical >= minDupSize,
               let duplicatePath = duplicateCandidatePath(for: url, seenTargets: &seenDuplicateTargets),
               !DuplicateSafetyClassifier.isNeverRecommend(path: url.path),
               !DuplicateSafetyClassifier.isNeverRecommend(path: duplicatePath) {
                sizeBuckets[logical, default: []].append(duplicatePath)
            }
        }

        var children: [String: [String]] = [:]
        for path in folderSizes.keys where path != rootPath {
            let ext = (path as NSString).pathExtension.lowercased()
            if bundleLikeExts.contains(ext) { continue }
            if (folderSizes[path] ?? 0) < browserMinSize { continue }
            let parent = (path as NSString).deletingLastPathComponent
            children[parent, default: []].append(path)
        }

        result.unreadableCount = unreadable
        result.folderSizes = folderSizes
        result.folderChildren = children
        result.audioSystemData = AudioSystemDataClassifier.summarize(folderSizes: folderSizes)

        if cancel?.isCancelled != true {
            let (confident, identical) = findDuplicates(
                sizeBuckets: sizeBuckets, cancel: cancel, progress: progress)
            let actionableConfident = filterNeverRecommendDuplicates(confident)
            let actionableIdentical = filterNeverRecommendDuplicates(identical)
            result.duplicateGroups = actionableConfident
            result.identicalContentGroups = actionableIdentical
            result.duplicateReclaimable = actionableConfident.reduce(0) { $0 + $1.reclaimable }
            result.identicalContentReclaimable = actionableIdentical.reduce(0) { $0 + $1.reclaimable }
        }
        if cancel?.isCancelled == true { result.cancelled = true }

        result.elapsed = Date().timeIntervalSince(start)
        return result
    }

    private static nonisolated func findDuplicates(
        sizeBuckets: [Int64: [String]],
        cancel: CancelToken?,
        progress: (@Sendable (ScanProgress) -> Void)?
    ) -> (confident: [DuplicateGroup], identical: [DuplicateGroup]) {
        let candidates = sizeBuckets.filter { $0.value.count >= 2 }
        let totalCandidates = candidates.count
        var confident: [DuplicateGroup] = []
        var identical: [DuplicateGroup] = []
        var processed = 0

        for (size, paths) in candidates {
            if cancel?.isCancelled == true { break }
            processed += 1

            var byPartial: [String: [String]] = [:]
            for p in paths {
                if cancel?.isCancelled == true { break }
                if let h = partialHash(path: p, fileSize: size) {
                    byPartial[h, default: []].append(p)
                }
            }

            for (_, pPaths) in byPartial where pPaths.count >= 2 {
                var byFull: [String: [String]] = [:]
                for p in pPaths {
                    if cancel?.isCancelled == true { break }
                    progress?(ScanProgress(phase: .findingDuplicates, count: processed,
                                           total: Int64(totalCandidates),
                                           label: (p as NSString).lastPathComponent))
                    if let h = fullHash(path: p) {
                        byFull[h, default: []].append(p)
                    }
                }

                for (_, fPaths) in byFull where fPaths.count >= 2 {
                    var byName: [String: [String]] = [:]
                    for p in fPaths {
                        let name = (p as NSString).lastPathComponent
                        byName[name, default: []].append(p)
                    }
                    var singletons: [String] = []
                    for (_, namePaths) in byName {
                        if namePaths.count >= 2 {
                            confident.append(DuplicateGroup(
                                fileSize: size, paths: namePaths.sorted(), sameName: true))
                        } else {
                            singletons.append(contentsOf: namePaths)
                        }
                    }
                    if singletons.count >= 2 {
                        identical.append(DuplicateGroup(
                            fileSize: size, paths: singletons.sorted(), sameName: false))
                    }
                }
            }
        }

        confident.sort { $0.reclaimable > $1.reclaimable }
        identical.sort { $0.reclaimable > $1.reclaimable }
        return (confident, identical)
    }

    private static nonisolated func filterNeverRecommendDuplicates(
        _ groups: [DuplicateGroup]
    ) -> [DuplicateGroup] {
        groups.compactMap { group in
            let actionablePaths = group.paths.filter {
                !DuplicateSafetyClassifier.isNeverRecommend(path: $0)
            }
            guard actionablePaths.count >= 2 else { return nil }
            return DuplicateGroup(
                fileSize: group.fileSize,
                paths: actionablePaths.sorted(),
                sameName: group.sameName)
        }
        .sorted { $0.reclaimable > $1.reclaimable }
    }

    private static nonisolated func duplicateCandidatePath(
        for url: URL,
        seenTargets: inout Set<String>
    ) -> String? {
        let resolvedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard seenTargets.insert(resolvedPath).inserted else { return nil }
        return resolvedPath
    }

    private static func partialHash(path: String, fileSize: Int64, sample: Int = 65536) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        if let head = try? handle.read(upToCount: sample) { hasher.update(data: head) }
        let tailOffset = UInt64(max(0, fileSize - Int64(sample)))
        if (try? handle.seek(toOffset: tailOffset)) != nil {
            if let tail = try? handle.read(upToCount: sample) { hasher.update(data: tail) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func fullHash(path: String) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func insertTop(_ list: inout [SizedItem], item: SizedItem, limit: Int) {
        if list.count < limit {
            list.append(item); list.sort { $0.size > $1.size }
        } else if let last = list.last, item.size > last.size {
            list[limit - 1] = item; list.sort { $0.size > $1.size }
        }
    }
}
