import Foundation

struct StagedFile: Identifiable, Sendable {
    let url: URL
    let originalPath: String
    let size: Int64

    var id: String { url.path }
    var displayName: String { url.lastPathComponent.isEmpty ? originalPath : url.lastPathComponent }
}

enum StagingError: LocalizedError {
    case sourceMissing(String)
    case stagedFileExists(String)
    case restoreDestinationExists(String)
    case invalidStagedPath(String)

    var errorDescription: String? {
        switch self {
        case .sourceMissing(let path):
            return "The original file could not be found: \(path)"
        case .stagedFileExists(let path):
            return "A staged copy already exists for: \(path)"
        case .restoreDestinationExists(let path):
            return "A file already exists at the restore location: \(path)"
        case .invalidStagedPath(let path):
            return "This file is not inside the SessionSweep staging folder: \(path)"
        }
    }
}

enum StagingManager {
    static var stagingFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("SessionSweep Staging", isDirectory: true)
    }

    static func duplicateSafetyClassification(originalPath: String) -> DuplicateSafetyClassification {
        DuplicateSafetyClassifier.classify(path: originalPath)
    }

    static func isNeverRecommendDuplicate(originalPath: String) -> Bool {
        duplicateSafetyClassification(originalPath: originalPath).isNeverRecommend
    }

    static func isProtectedVendorResource(originalPath: String) -> Bool {
        isNeverRecommendDuplicate(originalPath: originalPath)
    }

    static func stagedFiles() throws -> [StagedFile] {
        let root = stagingFolderURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return []
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [StagedFile] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            files.append(
                StagedFile(
                    url: url,
                    originalPath: try originalPath(for: url),
                    size: Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                )
            )
        }
        return files.sorted { $0.originalPath.localizedStandardCompare($1.originalPath) == .orderedAscending }
    }

    static func moveToStaging(originalPath: String) throws -> StagedFile {
        let source = URL(fileURLWithPath: originalPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw StagingError.sourceMissing(source.path)
        }

        let destination = stagingURL(forOriginalPath: source.path)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw StagingError.stagedFileExists(source.path)
        }

        let values = try source.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)

        try ensureStagingFolder()
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: source, to: destination)

        return StagedFile(url: destination, originalPath: source.path, size: size)
    }

    static func restore(_ file: StagedFile) throws {
        let destination = URL(fileURLWithPath: file.originalPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: file.url.path) else {
            throw StagingError.sourceMissing(file.url.path)
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw StagingError.restoreDestinationExists(destination.path)
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: file.url, to: destination)
        removeEmptyParents(startingAt: file.url.deletingLastPathComponent())
    }

    static func clearStaging() throws {
        let root = stagingFolderURL
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.trashItem(at: root, resultingItemURL: nil)
    }

    private static func ensureStagingFolder() throws {
        try FileManager.default.createDirectory(
            at: stagingFolderURL,
            withIntermediateDirectories: true
        )
    }

    private static func stagingURL(forOriginalPath path: String) -> URL {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let relative = standardized.hasPrefix("/") ? String(standardized.dropFirst()) : standardized
        return stagingFolderURL.appendingPathComponent(relative)
    }

    private static func originalPath(for stagedURL: URL) throws -> String {
        let rootPath = stagingFolderURL.standardizedFileURL.path
        let stagedPath = stagedURL.standardizedFileURL.path
        guard stagedPath.hasPrefix(rootPath + "/") else {
            throw StagingError.invalidStagedPath(stagedPath)
        }
        let relative = String(stagedPath.dropFirst(rootPath.count + 1))
        return "/" + relative
    }

    private static func removeEmptyParents(startingAt url: URL) {
        let root = stagingFolderURL.standardizedFileURL
        var current = url.standardizedFileURL
        while current.path.hasPrefix(root.path), current.path != root.path {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: current,
                includingPropertiesForKeys: nil
            ), contents.isEmpty else {
                return
            }
            try? FileManager.default.removeItem(at: current)
            current = current.deletingLastPathComponent().standardizedFileURL
        }
    }
}
