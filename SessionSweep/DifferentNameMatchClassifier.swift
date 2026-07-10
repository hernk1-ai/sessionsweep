import Foundation

enum DifferentNameMatchKind: String, Sendable, Hashable {
    case likelyConsolidatedStems = "Likely Consolidated Stems"
    case possibleDuplicateTracks = "Possible Duplicate Tracks"
    case possibleAlternateVersions = "Possible Alternate Versions"
    case possibleSilentFiles = "Possible Silent / Empty Files"
    case repeatedExportCopies = "Repeated Export Copies"
    case unclear = "Unclear Match"
}

enum DifferentNameMatchConfidence: String, Sendable, Hashable {
    case modest = "Modest"
    case cautious = "Cautious"
    case uncertain = "Uncertain"
}

struct DifferentNameMatchClassification: Sendable, Hashable {
    let kind: DifferentNameMatchKind
    let title: String
    let explanation: String
    let confidence: DifferentNameMatchConfidence
    let reason: String?
    let showsCautionNote: Bool
}

enum DifferentNameMatchClassifier {
    static nonisolated func classify(paths: [String], fileSize: Int64) -> DifferentNameMatchClassification {
        let filenames = paths.map { URL(fileURLWithPath: $0).lastPathComponent }
        let parents = paths.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
        let lowerParents = parents.map { $0.lowercased() }
        let sameParent = Set(parents).count == 1
        let parentContext = lowerParents.joined(separator: " ")

        if sameParent,
           hasStemFolderContext(parentContext),
           hasTrackStylePrefixes(filenames),
           hasMultipleTrackRoles(filenames) {
            return DifferentNameMatchClassification(
                kind: .likelyConsolidatedStems,
                title: DifferentNameMatchKind.likelyConsolidatedStems.rawValue,
                explanation: "These files use different track-style names and appear to come from the same rendered or consolidated session folder. They may be intentional stems, including silent or empty regions created to preserve timeline alignment.",
                confidence: .modest,
                reason: "Track-style names in the same consolidated or rendered session folder.",
                showsCautionNote: true
            )
        }

        if hasRepeatedExportSignals(filenames: filenames, parentContext: parentContext) {
            return DifferentNameMatchClassification(
                kind: .repeatedExportCopies,
                title: DifferentNameMatchKind.repeatedExportCopies.rawValue,
                explanation: "These appear to be repeated exports with identical audio content. Review their locations and names before deciding whether they represent separate deliverables or repeated render attempts.",
                confidence: .cautious,
                reason: "Export-style folder or filename markers with copy, timestamp, or render-attempt naming.",
                showsCautionNote: true
            )
        }

        if sameParent, sharesNumberedBaseName(filenames) {
            return DifferentNameMatchClassification(
                kind: .possibleDuplicateTracks,
                title: DifferentNameMatchKind.possibleDuplicateTracks.rawValue,
                explanation: "These files share the same base name with numbered suffixes. They may be duplicate imports, repeated copies, or alternate track names.",
                confidence: .modest,
                reason: "Same folder and same base filename with numbered suffixes.",
                showsCautionNote: true
            )
        }

        if hasVersionStyleNames(filenames) {
            return DifferentNameMatchClassification(
                kind: .possibleAlternateVersions,
                title: DifferentNameMatchKind.possibleAlternateVersions.rawValue,
                explanation: "These files have version-style names but identical audio content. They may be alternate labels, exports, or copies created during a revision workflow.",
                confidence: .cautious,
                reason: "Version, mix, edit, master, or alternate-name markers appear in the filenames.",
                showsCautionNote: true
            )
        }

        return DifferentNameMatchClassification(
            kind: .unclear,
            title: DifferentNameMatchKind.unclear.rawValue,
            explanation: "These files contain identical audio data but have different names. SessionSweep cannot determine why they were created. Review them before making any changes.",
            confidence: .uncertain,
            reason: nil,
            showsCautionNote: true
        )
    }

    static nonisolated func sharedParent(paths: [String]) -> String? {
        let parents = paths.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
        guard let first = parents.first, parents.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private static nonisolated func hasStemFolderContext(_ parentContext: String) -> Bool {
        stemFolderMarkers.contains { parentContext.contains($0) }
    }

    private static nonisolated func hasTrackStylePrefixes(_ filenames: [String]) -> Bool {
        let matches = filenames.filter { filename in
            let stem = filenameStem(filename).lowercased()
            return stem.range(of: #"^\d{1,3}[\s._-]+"#, options: .regularExpression) != nil
        }
        return matches.count >= max(3, filenames.count / 2)
    }

    private static nonisolated func hasMultipleTrackRoles(_ filenames: [String]) -> Bool {
        let joined = filenames.map { filenameStem($0).lowercased() }.joined(separator: " ")
        let matches = trackRoleMarkers.filter { joined.contains($0) }
        return Set(matches).count >= 2
    }

    private static nonisolated func sharesNumberedBaseName(_ filenames: [String]) -> Bool {
        let bases = filenames.map { numberedBaseName(filenameStem($0)) }
        let grouped = Dictionary(grouping: bases, by: { $0 })
        return grouped.values.contains { $0.count >= max(2, filenames.count / 2) }
    }

    private static nonisolated func numberedBaseName(_ name: String) -> String {
        name
            .replacingOccurrences(of: #"(?i)[\s._-]+\d+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)[\s._-]+copy(?:\s+\d+)?$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static nonisolated func hasVersionStyleNames(_ filenames: [String]) -> Bool {
        let stems = filenames.map { filenameStem($0).lowercased() }
        let matches = stems.filter { stem in
            versionMarkers.contains { marker in
                stem.range(of: marker, options: .regularExpression) != nil
            }
        }
        return matches.count >= 1
    }

    private static nonisolated func hasRepeatedExportSignals(
        filenames: [String],
        parentContext: String
    ) -> Bool {
        let hasExportContext = exportFolderMarkers.contains { parentContext.contains($0) }
        let stems = filenames.map { filenameStem($0).lowercased() }
        let hasCopyOrTimestamp = stems.contains { stem in
            repeatedExportMarkers.contains { marker in
                stem.range(of: marker, options: .regularExpression) != nil
            }
        }
        return hasExportContext && hasCopyOrTimestamp
    }

    private static nonisolated func filenameStem(_ filename: String) -> String {
        (filename as NSString).deletingPathExtension
    }

    private nonisolated static let stemFolderMarkers = [
        "consolidated",
        "stems",
        "bounces",
        "bounce",
        "exports",
        "export",
        "rendered",
        "renders",
        "freeze",
        "processed",
    ]

    private nonisolated static let exportFolderMarkers = [
        "bounces",
        "bounce",
        "exports",
        "export",
        "rendered",
        "renders",
        "desktop",
        "downloads",
    ]

    private nonisolated static let trackRoleMarkers = [
        "kick",
        "snare",
        "hat",
        "hihat",
        "tom",
        "cowbell",
        "bass",
        "guitar",
        "vox",
        "vocal",
        "lead",
        "pad",
        "keys",
        "piano",
        "drum",
        "perc",
        "sub",
        "fx",
    ]

    private nonisolated static let versionMarkers = [
        #"(^|[\s._-])v\d+($|[\s._-])"#,
        #"(^|[\s._-])final\d*($|[\s._-])"#,
        #"(^|[\s._-])alt($|[\s._-])"#,
        #"(^|[\s._-])edit($|[\s._-])"#,
        #"(^|[\s._-])mix($|[\s._-])"#,
        #"(^|[\s._-])master($|[\s._-])"#,
        #"(^|[\s._-])clean($|[\s._-])"#,
        #"(^|[\s._-])instrumental($|[\s._-])"#,
    ]

    private nonisolated static let repeatedExportMarkers = [
        #"(?i)(^|[\s._-])copy(?:[\s._-]*\d+)?$"#,
        #"(?i)[\s._-]\d{4}[-_.]\d{2}[-_.]\d{2}"#,
        #"(?i)[\s._-]\d{8}($|[\s._-])"#,
        #"(?i)[\s._-]\d{6}($|[\s._-])"#,
        #"(?i)(^|[\s._-])bounce\d+($|[\s._-])"#,
        #"(?i)(^|[\s._-])render\d+($|[\s._-])"#,
    ]
}
