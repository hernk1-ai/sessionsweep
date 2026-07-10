import Foundation
import Combine

enum KeepSafeItemType: String, Codable, Sendable, Hashable {
    case file
    case folder

    var displayName: String {
        switch self {
        case .file: return "File"
        case .folder: return "Folder"
        }
    }
}

enum KeepSafeAvailabilityStatus: String, Sendable, Hashable {
    case available = "Available"
    case locationChanged = "Location changed"
    case notAvailable = "Not currently available"
}

struct KeepSafeItem: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var originalPath: String
    var resolvedPath: String
    var displayName: String
    var itemType: KeepSafeItemType
    var sizeAtProtection: Int64
    var dateProtected: Date
    var lastSeenDate: Date?
    var lastKnownExists: Bool
    var sourceVolumeIdentifier: String?
    var bookmarkData: Data?
    var classification: String?
    var category: String?
    var note: String?
}

final class KeepSafeStore: ObservableObject {
    static let shared = KeepSafeStore()

    @Published private(set) var items: [KeepSafeItem] = []

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("SessionSweep", isDirectory: true)
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/SessionSweep", isDirectory: true)

        self.fileURL = fileURL ?? supportDirectory.appendingPathComponent("KeepSafeItems.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
        refreshAvailability()
    }

    func add(
        path: String,
        itemType: KeepSafeItemType? = nil,
        size: Int64? = nil,
        classification: String? = nil,
        category: String? = nil,
        note: String? = nil
    ) {
        let standardized = standardize(path)
        let resolved = resolve(path)
        if let existing = item(for: standardized) ?? item(for: resolved) {
            update(existing.id) { item in
                item.lastSeenDate = Date()
                item.lastKnownExists = fileExists(at: standardized) || fileExists(at: resolved)
                item.classification = classification ?? item.classification
                item.category = category ?? item.category
                item.note = note ?? item.note
            }
            return
        }

        let url = URL(fileURLWithPath: standardized)
        let inferredType = itemType ?? inferredItemType(path: standardized)
        let item = KeepSafeItem(
            id: UUID(),
            originalPath: standardized,
            resolvedPath: resolved,
            displayName: url.lastPathComponent.isEmpty ? standardized : url.lastPathComponent,
            itemType: inferredType,
            sizeAtProtection: size ?? currentSize(path: standardized),
            dateProtected: Date(),
            lastSeenDate: fileExists(at: standardized) || fileExists(at: resolved) ? Date() : nil,
            lastKnownExists: fileExists(at: standardized) || fileExists(at: resolved),
            sourceVolumeIdentifier: sourceVolumeIdentifier(path: standardized),
            bookmarkData: makeBookmarkData(path: standardized),
            classification: classification,
            category: category,
            note: note
        )
        items.append(item)
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func remove(path: String) {
        guard let item = item(for: path) else { return }
        remove(id: item.id)
    }

    func isProtected(_ path: String) -> Bool {
        protectedItem(for: path) != nil
    }

    func protectedItem(for path: String) -> KeepSafeItem? {
        let standardized = standardize(path)
        let resolved = resolve(path)
        return items.first { item in
            matches(item: item, candidate: standardized) || matches(item: item, candidate: resolved)
        }
    }

    func item(for path: String) -> KeepSafeItem? {
        let standardized = standardize(path)
        let resolved = resolve(path)
        return items.first { item in
            pathsEqual(item.originalPath, standardized)
                || pathsEqual(item.resolvedPath, standardized)
                || pathsEqual(item.originalPath, resolved)
                || pathsEqual(item.resolvedPath, resolved)
        }
    }

    func availability(for item: KeepSafeItem) -> KeepSafeAvailabilityStatus {
        if fileExists(at: item.originalPath) || fileExists(at: item.resolvedPath) {
            return .available
        }
        if let resolvedBookmarkPath = resolvedBookmarkPath(for: item),
           fileExists(at: resolvedBookmarkPath) {
            return pathsEqual(resolvedBookmarkPath, item.originalPath) || pathsEqual(resolvedBookmarkPath, item.resolvedPath)
                ? .available
                : .locationChanged
        }
        return .notAvailable
    }

    func currentPath(for item: KeepSafeItem) -> String {
        if fileExists(at: item.originalPath) { return item.originalPath }
        if fileExists(at: item.resolvedPath) { return item.resolvedPath }
        if let resolvedBookmarkPath = resolvedBookmarkPath(for: item) {
            return resolvedBookmarkPath
        }
        return item.originalPath
    }

    func refreshAvailability() {
        var changed = false
        for index in items.indices {
            let status = availability(for: items[index])
            let exists = status == .available || status == .locationChanged
            if items[index].lastKnownExists != exists {
                items[index].lastKnownExists = exists
                changed = true
            }
            if exists {
                items[index].lastSeenDate = Date()
                changed = true
            }
        }
        if changed { save() }
    }

    func updateSeen(paths: [String: Int64]) {
        var changed = false
        for (path, size) in paths {
            guard let protected = item(for: path),
                  let index = items.firstIndex(where: { $0.id == protected.id }) else { continue }
            items[index].lastSeenDate = Date()
            items[index].lastKnownExists = true
            if size > 0 { items[index].sizeAtProtection = size }
            changed = true
        }
        if changed { save() }
    }

    private func update(_ id: UUID, _ mutate: (inout KeepSafeItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
        save()
    }

    private func matches(item: KeepSafeItem, candidate: String) -> Bool {
        let itemPaths = [item.originalPath, item.resolvedPath].map(standardize)
        let candidates = [candidate, resolve(candidate)].map(standardize)

        for itemPath in itemPaths {
            for candidatePath in candidates {
                if pathsEqual(itemPath, candidatePath) { return true }
                if item.itemType == .folder && isDescendant(candidatePath, of: itemPath) { return true }
            }
        }
        return false
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            items = []
            return
        }
        items = (try? decoder.decode([KeepSafeItem].self, from: data)) ?? []
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Could not save Keep Safe items: \(error.localizedDescription)")
        }
    }

    private func inferredItemType(path: String) -> KeepSafeItemType {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return .folder
        }
        return .file
    }

    private func currentSize(path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey])
        if values?.isDirectory == true { return 0 }
        return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }

    private func sourceVolumeIdentifier(path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.volumeIdentifierKey, .volumeNameKey])
        if let identifier = values?.volumeIdentifier {
            return String(describing: identifier)
        }
        return values?.volumeName
    }

    private func makeBookmarkData(path: String) -> Data? {
        try? URL(fileURLWithPath: path).bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func resolvedBookmarkPath(for item: KeepSafeItem) -> String? {
        guard let data = item.bookmarkData else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), !isStale else { return nil }
        return standardize(url.path)
    }

    private func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private func standardize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func resolve(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func pathsEqual(_ lhs: String, _ rhs: String) -> Bool {
        standardize(lhs) == standardize(rhs)
    }

    private func isDescendant(_ candidate: String, of folder: String) -> Bool {
        let child = standardize(candidate)
        let parent = standardize(folder)
        guard parent != "/" else { return child.hasPrefix("/") }
        return child.hasPrefix(parent + "/")
    }
}
