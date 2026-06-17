import SwiftUI
import AppKit
import Observation

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

@MainActor
@Observable
final class ScanController {
    var isScanning = false
    var phase: ScanPhase = .scanning
    var liveCount = 0
    var liveBytes: Int64 = 0
    var liveItems = 0
    var liveLabel = ""
    var dupChecked = 0
    var dupTotal = 0
    var result: ScanResult?
    var scannedPath = ""
    var currentPath = ""
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
    @State private var controller = ScanController()

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
                card { duplicatesSection(r) }
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

    private func duplicatesSection(_ r: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 22) {
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
                    Text("Same filename and byte-for-byte identical. Review only — nothing is selected or deleted. Some identical copies are still needed (a plugin may require its own), so check each before acting.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(r.duplicateGroups.prefix(15)) { confidentRow($0) }
                    if r.duplicateGroups.count > 15 {
                        Text("+ \(r.duplicateGroups.count - 15) more groups")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
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
        VStack(alignment: .leading, spacing: 4) {
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
                Text(path).font(.caption2).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
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

#Preview { ContentView() }

