import Foundation
import Combine
import SwiftData

enum KnowledgeLibraryStoreError: LocalizedError {
    case libraryNotFound
    case activeLibraryUnavailable
    case persistenceFailure(operation: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .libraryNotFound:
            return "Knowledge library was not found."
        case .activeLibraryUnavailable:
            return "Active knowledge library is unavailable."
        case let .persistenceFailure(operation, underlying):
            return "\(operation) failed: \(underlying.localizedDescription)"
        }
    }
}

struct KnowledgeLibraryRecord: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    let createdAt: Date
    var archivedAt: Date?

    var isArchived: Bool {
        archivedAt != nil
    }
}

struct KnowledgeLibraryInsertionTarget {
    let library: KnowledgeLibraryRecord
    let didArchive: Bool
}

@MainActor
final class KnowledgeLibraryStore: ObservableObject {
    static let autoArchiveNodeLimit = 150

    @Published private(set) var libraries: [KnowledgeLibraryRecord] = []
    @Published private(set) var activeLibraryID: String = ""
    @Published private(set) var selectedLibraryID: String = ""

    init() {
        loadSelectionState()
    }

    var activeLibrary: KnowledgeLibraryRecord? {
        libraries.first(where: { $0.id == activeLibraryID })
    }

    var selectedLibrary: KnowledgeLibraryRecord? {
        libraries.first(where: { $0.id == selectedLibraryID }) ?? activeLibrary
    }

    var visibleLibraries: [KnowledgeLibraryRecord] {
        libraries.sorted { lhs, rhs in
            if lhs.id == activeLibraryID { return true }
            if rhs.id == activeLibraryID { return false }
            if lhs.isArchived != rhs.isArchived { return !lhs.isArchived }
            return (lhs.archivedAt ?? lhs.createdAt) > (rhs.archivedAt ?? rhs.createdAt)
        }
    }

    var isViewingArchivedLibrary: Bool {
        guard let selectedLibrary else { return false }
        return selectedLibrary.id != activeLibraryID && selectedLibrary.isArchived
    }

    nonisolated static func displayName(for library: KnowledgeLibraryRecord, region: SupportedRegionUI) -> String {
        guard library.archivedAt == nil, isDefaultActiveLibraryName(library.name) else {
            return library.name
        }
        return RegionUIStore.copy(for: region).defaultActiveLibraryName
    }

    func selectLibrary(id: String) {
        guard libraries.contains(where: { $0.id == id }) else { return }
        selectedLibraryID = id
        saveSelectionState()
    }

    func renameLibrary(id: String, to newName: String, modelContext: ModelContext, libraries: [KnowledgeLibrary]) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let library = libraries.first(where: { $0.id == id }) else {
            throw KnowledgeLibraryStoreError.libraryNotFound
        }
        let originalName = library.name
        library.name = trimmed
        do {
            try modelContext.save()
        } catch {
            library.name = originalName
            throw KnowledgeLibraryStoreError.persistenceFailure(
                operation: "Renaming knowledge library",
                underlying: error
            )
        }
    }

    func sync(with libraries: [KnowledgeLibrary]) {
        self.libraries = libraries.map {
            KnowledgeLibraryRecord(id: $0.id, name: $0.name, createdAt: $0.createdAt, archivedAt: $0.archivedAt)
        }
        ensureSelectionState()
    }

    func bootstrapIfNeeded(modelContext: ModelContext, libraries: [KnowledgeLibrary]) throws {
        guard libraries.isEmpty else {
            sync(with: libraries)
            return
        }

        let legacyLibraries = loadLegacyLibraries()
        var insertedLibraries: [KnowledgeLibrary] = []
        if legacyLibraries.isEmpty {
            let library = KnowledgeLibrary(name: Self.defaultActiveLibraryName)
            modelContext.insert(library)
            insertedLibraries.append(library)
        } else {
            for library in legacyLibraries {
                let storedLibrary = KnowledgeLibrary(
                    id: library.id,
                    name: library.name,
                    createdAt: library.createdAt,
                    archivedAt: library.archivedAt
                )
                modelContext.insert(storedLibrary)
                insertedLibraries.append(storedLibrary)
            }
        }

        do {
            try modelContext.save()
            clearLegacyLibraries()
        } catch {
            insertedLibraries.forEach { modelContext.delete($0) }
            throw KnowledgeLibraryStoreError.persistenceFailure(
                operation: "Bootstrapping knowledge libraries",
                underlying: error
            )
        }
    }

    @discardableResult
    func archiveCurrentLibraryAndCreateNew(modelContext: ModelContext, libraries: [KnowledgeLibrary]? = nil) throws -> KnowledgeLibraryRecord {
        let resolvedLibraries: [KnowledgeLibrary]
        if let libraries {
            resolvedLibraries = libraries
        } else {
            resolvedLibraries = try fetchLibraries(using: modelContext)
        }
        guard !resolvedLibraries.isEmpty else {
            throw KnowledgeLibraryStoreError.activeLibraryUnavailable
        }
        let now = Date()
        let currentLibrary = resolvedActiveLibrary(in: resolvedLibraries)
        let previousArchivedAt = currentLibrary?.archivedAt
        let previousName = currentLibrary?.name

        if let currentLibrary {
            currentLibrary.archivedAt = now
            if Self.isDefaultActiveLibraryName(currentLibrary.name) {
                currentLibrary.name = RegionUIStore.runtimeCopy().archivedLibraryName(dateText: Self.archiveNameFormatter.string(from: now))
            }
        }

        let newLibrary = KnowledgeLibrary(
            name: Self.defaultActiveLibraryName,
            createdAt: now
        )
        modelContext.insert(newLibrary)
        do {
            try modelContext.save()
        } catch {
            currentLibrary?.archivedAt = previousArchivedAt
            if let previousName {
                currentLibrary?.name = previousName
            }
            modelContext.delete(newLibrary)
            throw KnowledgeLibraryStoreError.persistenceFailure(
                operation: "Archiving knowledge library",
                underlying: error
            )
        }

        activeLibraryID = newLibrary.id
        selectedLibraryID = newLibrary.id
        saveSelectionState()
        return KnowledgeLibraryRecord(id: newLibrary.id, name: newLibrary.name, createdAt: newLibrary.createdAt, archivedAt: nil)
    }

    func prepareActiveLibraryForNextInsertion(
        currentNodeCount: Int,
        modelContext: ModelContext
    ) throws -> KnowledgeLibraryInsertionTarget {
        let libraries = try fetchLibraries(using: modelContext)
        guard let currentLibrary = resolvedActiveLibrary(in: libraries) else {
            throw KnowledgeLibraryStoreError.activeLibraryUnavailable
        }

        if currentNodeCount < Self.autoArchiveNodeLimit {
            return KnowledgeLibraryInsertionTarget(
                library: record(for: currentLibrary),
                didArchive: false
            )
        }

        let newLibrary = try archiveCurrentLibraryAndCreateNew(
            modelContext: modelContext,
            libraries: libraries
        )

        return KnowledgeLibraryInsertionTarget(library: newLibrary, didArchive: true)
    }

    private func ensureSelectionState() {
        if activeLibraryID.isEmpty || !libraries.contains(where: { $0.id == activeLibraryID }) {
            if let current = libraries.first(where: { !$0.isArchived }) ?? libraries.first {
                activeLibraryID = current.id
            }
        }

        if selectedLibraryID.isEmpty || !libraries.contains(where: { $0.id == selectedLibraryID }) {
            selectedLibraryID = activeLibraryID
        }

        saveSelectionState()
    }

    private func loadSelectionState() {
        let defaults = UserDefaults.standard
        activeLibraryID = defaults.string(forKey: Self.activeLibraryKey) ?? ""
        selectedLibraryID = defaults.string(forKey: Self.selectedLibraryKey) ?? ""
    }

    private func saveSelectionState() {
        let defaults = UserDefaults.standard
        defaults.set(activeLibraryID, forKey: Self.activeLibraryKey)
        defaults.set(selectedLibraryID, forKey: Self.selectedLibraryKey)
    }

    private func loadLegacyLibraries() -> [KnowledgeLibraryRecord] {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.legacyLibrariesKey),
              let decoded = try? JSONDecoder().decode([KnowledgeLibraryRecord].self, from: data) else {
            return []
        }
        return decoded
    }

    private func clearLegacyLibraries() {
        UserDefaults.standard.removeObject(forKey: Self.legacyLibrariesKey)
    }

    private static var defaultActiveLibraryName: String {
        RegionUIStore.runtimeCopy().defaultActiveLibraryName
    }

    private func resolvedActiveLibrary(in libraries: [KnowledgeLibrary]) -> KnowledgeLibrary? {
        if let active = libraries.first(where: { $0.id == activeLibraryID }) {
            return active
        }
        return libraries.filter { $0.archivedAt == nil }.first ?? libraries.first
    }

    private func record(for library: KnowledgeLibrary) -> KnowledgeLibraryRecord {
        KnowledgeLibraryRecord(
            id: library.id,
            name: library.name,
            createdAt: library.createdAt,
            archivedAt: library.archivedAt
        )
    }

    private func fetchLibraries(using modelContext: ModelContext) throws -> [KnowledgeLibrary] {
        let descriptor = FetchDescriptor<KnowledgeLibrary>(
            sortBy: [SortDescriptor(\KnowledgeLibrary.createdAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            throw KnowledgeLibraryStoreError.persistenceFailure(
                operation: "Fetching knowledge libraries",
                underlying: error
            )
        }
    }

    private nonisolated static func isDefaultActiveLibraryName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return Set(
            SupportedRegionUI.allCases.map { RegionUIStore.copy(for: $0).defaultActiveLibraryName }
        ).contains(trimmed)
    }

    private static let legacyLibrariesKey = "knowledgeLibraries.records"
    private static let activeLibraryKey = "knowledgeLibraries.activeID"
    private static let selectedLibraryKey = "knowledgeLibraries.selectedID"

    private static let archiveNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = RegionUIStore.runtimeLocale()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()
}
