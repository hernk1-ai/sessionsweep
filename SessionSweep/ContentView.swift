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

struct ContentView: View {
    @StateObject private var controller = ScanController()
    @State private var selectedDuplicatePaths: Set<String> = []
    @State private var stagedFiles: [StagedFile] = []
    @State private var appAlert: AppAlert?
    @AppStorage("SessionSweepHasValidLicense") private var hasValidLicense = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            Group {
                if let result = controller.result { resultsView(result) }
                else if controller.isScanning { scanningView }
                else { emptyView }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(28)
        .frame(minWidth: 780, minHeight: 660)
        .task {
            refreshStaging()
        }
        .onChange(of: controller.result?.rootPath) { _ in
            resetDuplicateSelection()
            refreshStaging()
        }
        .alert(item: $appAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
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
            } else if controller.result != nil {
                Button { pickAndScan() } label: {
                    Label("Scan Again", systemImage: "magnifyingglass")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
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
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.3), value: controller.liveBytes)
    }

    private func resultsView(_ r: ScanResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
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

                card { categorySection(r) }
                card { audioSystemDataSection(r) }
                card { duplicatesSection(r) }
                card { stagingSection() }
                card { browserSection() }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Largest files").font(.headline)
                    ForEach(r.topFiles.prefix(12)) { fileRow($0) }
                }

                Text("Scanned in \(String(format: "%.1f", r.elapsed))s · "
                     + "\(r.fileCount.formatted()) items · \(r.unreadableCount) unreadable · "
                     + "\(r.excludedSystemCount) system folders skipped")
                    .font(.caption2).foregroundStyle(.tertiary).padding(.top, 4)
            }
            .padding(.bottom, 16)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(18)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func categorySection(_ r: ScanResult) -> some View {
        let cats = Category.allCases
            .map { ($0, r.categoryTotals[$0] ?? 0) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        let total = max(r.totalSize, 1)
        let mid = (cats.count + 1) / 2
        let leftCol = Array(cats.prefix(mid))
        let rightCol = Array(cats.dropFirst(mid))

        return VStack(alignment: .leading, spacing: 14) {
            Text("What's filling your drive").font(.headline)
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(cats, id: \.0) { cat, size in
                        Rectangle().fill(cat.color)
                            .frame(width: max(2, geo.size.width * (Double(size) / Double(total))))
                    }
                }
            }
            .frame(height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(leftCol, id: \.0) { cat, size in
                        categoryRow(cat, size: size, total: total)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rightCol, id: \.0) { cat, size in
                        categoryRow(cat, size: size, total: total)
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

    private func audioSystemDataSection(_ r: ScanResult) -> some View {
        let audio = r.audioSystemData
        let categories = AudioSystemDataCategory.allCases
            .map { ($0, audio.categoryTotals[$0] ?? 0) }
        let rows = audio.items.prefix(12)

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
                    ForEach(categories, id: \.0) { category, size in
                        audioBreakdownRow(category, size: size, total: max(audio.totalSize, 1))
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Top folders").font(.subheadline.weight(.semibold))
                    ForEach(audio.topFolders) { audioSystemDataRow($0) }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Detected audio folders").font(.subheadline.weight(.semibold))
                    ForEach(Array(rows)) { audioSystemDataRow($0) }
                    if audio.items.count > rows.count {
                        Text("+ \(audio.items.count - rows.count) more audio folders")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
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

    private func audioSystemDataRow(_ item: AudioSystemDataItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(item.category.color).frame(width: 8, height: 8)
                Text(item.friendlyName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(item.safetyStatus.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(item.safetyStatus.color)
                    .help(item.safetyStatus.explanatoryCopy)
                    .accessibilityLabel(item.safetyStatus.explanatoryCopy)
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
        }
        .padding(.vertical, 3)
    }

    private func duplicatesSection(_ r: ScanResult) -> some View {
        let selectedBytes = selectedDuplicateBytes(in: r)
        return VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Duplicate files").font(.headline)
                    Spacer()
                    if r.duplicateReclaimable > 0 {
                        Text("\(human(r.duplicateReclaimable)) reclaimable")
                            .font(.callout.weight(.semibold)).foregroundStyle(.teal)
                    }
                }
                if r.duplicateGroups.isEmpty {
                    Text("No confident duplicates over 1 MB (same name and identical content).")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Same filename and byte-for-byte identical. SessionSweep preselects likely redundant copies, but you can change any checkbox before moving files.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !selectedDuplicatePaths.isEmpty {
                        HStack(spacing: 10) {
                            Button { moveSelectedToStaging() } label: {
                                Label("Move to Staging", systemImage: "tray.and.arrow.down")
                            }
                            .buttonStyle(.borderedProminent)

                            Text("\(selectedDuplicatePaths.count) file\(selectedDuplicatePaths.count == 1 ? "" : "s") selected · \(human(selectedBytes))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }

                    ForEach(r.duplicateGroups) { confidentRow($0) }
                }
            }

            if !r.identicalContentGroups.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Label("Identical content, different names", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline).foregroundStyle(.orange)
                    Text("These files are byte-for-byte identical but have different names — often silent or empty stems from a consolidated session, which are NOT interchangeable. These are almost never safe to delete. Shown for awareness only; not counted as reclaimable.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(r.identicalContentGroups.prefix(10)) { identicalRow($0) }
                    if r.identicalContentGroups.count > 10 {
                        Text("+ \(r.identicalContentGroups.count - 10) more groups")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func confidentRow(_ g: DuplicateGroup) -> some View {
        let keeper = recommendedKeeper(in: g)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc.fill").foregroundStyle(.teal).font(.caption)
                Text(g.displayName).fontWeight(.medium)
                    .lineLimit(1).truncationMode(.middle)
                Text("×\(g.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(human(g.reclaimable)) reclaimable")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            ForEach(g.paths, id: \.self) { path in
                duplicatePathRow(path, fileSize: g.fileSize, keeper: keeper)
            }
        }
        .padding(.vertical, 4)
    }

    private func duplicatePathRow(_ path: String, fileSize: Int64, keeper: String?) -> some View {
        let isKeeper = path == keeper
        let isSelected = selectedDuplicatePaths.contains(path)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle("", isOn: Binding(
                get: { selectedDuplicatePaths.contains(path) },
                set: { checked in
                    if checked {
                        selectedDuplicatePaths.insert(path)
                    } else {
                        selectedDuplicatePaths.remove(path)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 2) {
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(isKeeper ? "Recommended keep" : "Recommended staging")
                    .font(.caption2)
                    .foregroundStyle(isKeeper ? Color.secondary : Color.teal)
            }
            Spacer()
            Text(human(fileSize))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
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
                    Button(role: .destructive) { clearStaging() } label: {
                        Label("Clear Staging", systemImage: "trash")
                    }
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
        }
        .padding(.vertical, 3)
    }

    private func identicalRow(_ g: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                Text("\(g.count) identical files · different names").fontWeight(.medium)
                Spacer()
                Text("\(human(g.fileSize)) each")
                    .font(.callout.monospacedDigit()).foregroundStyle(.tertiary)
            }
            ForEach(g.paths.prefix(8), id: \.self) { path in
                Text(path).font(.caption2).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            if g.paths.count > 8 {
                Text("…and \(g.paths.count - 8) more")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func browserSection() -> some View {
        let current = controller.currentPath
        let parentTotal = max(controller.size(of: current), 1)
        let kids = controller.children(of: current)
        let shown = Array(kids.prefix(25))
        let shownSum = shown.reduce(Int64(0)) { $0 + $1.size }
        let residual = max(0, parentTotal - shownSum)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Browse folders").font(.headline)
                Spacer()
                Text(human(parentTotal))
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            breadcrumbs()
            VStack(spacing: 12) {
                ForEach(shown) { childRow($0, parentTotal: parentTotal) }
                if residual >= 1_048_576 { residualRow(residual, parentTotal: parentTotal) }
                if shown.isEmpty && residual < 1_048_576 {
                    Text("This folder has no subfolders to drill into.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func breadcrumbs() -> some View {
        let root = controller.scannedPath
        let current = controller.currentPath
        var crumbs: [(name: String, path: String)] = []
        let rootName = (root == "/") ? "/" : URL(fileURLWithPath: root).lastPathComponent
        crumbs.append((rootName, root))
        if current != root && current.hasPrefix(root) {
            let rest = String(current.dropFirst(root.count)).split(separator: "/")
            var accum = root
            for comp in rest {
                accum = (accum == "/") ? "/" + comp : accum + "/" + comp
                crumbs.append((String(comp), accum))
            }
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(crumbs.enumerated()), id: \.offset) { idx, crumb in
                    if idx > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Button { controller.navigate(to: crumb.path) } label: {
                        Text(crumb.name)
                            .font(.callout)
                            .foregroundStyle(idx == crumbs.count - 1 ? .primary : .secondary)
                            .fontWeight(idx == crumbs.count - 1 ? .semibold : .regular)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func childRow(_ item: SizedItem, parentTotal: Int64) -> some View {
        let proportion = max(0.01, Double(item.size) / Double(parentTotal))
        let pct = Int((Double(item.size) / Double(parentTotal) * 100).rounded())
        let drillable = controller.hasChildren(item.url.path)
        return Button {
            if drillable { controller.navigate(to: item.url.path) }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundStyle(.teal).font(.caption)
                    Text(item.displayName).fontWeight(.medium)
                        .lineLimit(1).truncationMode(.middle)
                    if drillable {
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text("\(pct)%").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    Text(human(item.size))
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
        }
        .buttonStyle(.plain)
        .disabled(!drillable)
    }

    private func residualRow(_ residual: Int64, parentTotal: Int64) -> some View {
        let proportion = max(0.01, Double(residual) / Double(parentTotal))
        let pct = Int((Double(residual) / Double(parentTotal) * 100).rounded())
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc").foregroundStyle(.secondary).font(.caption)
                Text("Files & smaller items here").foregroundStyle(.secondary)
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

    private func resetDuplicateSelection() {
        guard let result = controller.result else {
            selectedDuplicatePaths = []
            return
        }
        selectedDuplicatePaths = Set(result.duplicateGroups.flatMap { group in
            guard let keeper = recommendedKeeper(in: group) else { return [String]() }
            return group.paths.filter { $0 != keeper }
        })
    }

    private func selectedDuplicateBytes(in result: ScanResult) -> Int64 {
        result.duplicateGroups.reduce(Int64(0)) { total, group in
            total + Int64(group.paths.filter { selectedDuplicatePaths.contains($0) }.count) * group.fileSize
        }
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
        guard hasValidLicense else {
            appAlert = AppAlert(
                title: "License Required",
                message: "Moving duplicate files to SessionSweep Staging is a paid feature. Activate a valid license to use Move to Staging."
            )
            return
        }

        let paths = selectedDuplicatePaths.sorted()
        var movedOriginalPaths: Set<String> = []
        var failures: [String] = []

        for path in paths {
            do {
                let staged = try StagingManager.moveToStaging(originalPath: path)
                movedOriginalPaths.insert(staged.originalPath)
            } catch {
                failures.append(error.localizedDescription)
            }
        }

        if !movedOriginalPaths.isEmpty {
            applyMovedDuplicatePaths(movedOriginalPaths)
            selectedDuplicatePaths.subtract(movedOriginalPaths)
            refreshStaging()
        }

        if !failures.isEmpty {
            appAlert = AppAlert(
                title: "Some Files Could Not Be Moved",
                message: failures.prefix(4).joined(separator: "\n")
            )
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
        } catch {
            appAlert = AppAlert(title: "Could Not Restore File", message: error.localizedDescription)
        }
    }

    private func clearStaging() {
        do {
            try StagingManager.clearStaging()
            refreshStaging()
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
