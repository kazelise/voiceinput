import Foundation
import Combine

// MARK: - VocabularyEntry

struct VocabularyEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// Canonical spelling, e.g. "Claude Code".
    var term: String
    /// Common mishearings, comma-separated. May be empty.
    var hints: String
}

// MARK: - VocabularyStore

final class VocabularyStore: ObservableObject {
    static let shared = VocabularyStore()

    /// All entries, persisted to `AppSettings.shared.vocabularyJSON` on every change.
    @Published var entries: [VocabularyEntry] {
        didSet { save() }
    }

    private init() {
        entries = VocabularyStore.load()
    }

    // MARK: - Persistence

    private static func load() -> [VocabularyEntry] {
        let json = AppSettings.shared.vocabularyJSON
        guard
            let data = json.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([VocabularyEntry].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func save() {
        guard
            let data = try? JSONEncoder().encode(entries),
            let json = String(data: data, encoding: .utf8)
        else { return }
        AppSettings.shared.vocabularyJSON = json
    }

    // MARK: - Derived

    /// Non-empty canonical term strings, suitable for the Soniox `context.terms` array.
    var sonioxTerms: [String] {
        entries
            .map { $0.term.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Prompt section for the polish LLM. Empty string when there are no entries.
    /// Lines formatted as: - "cloud code" → "Claude Code"
    var promptSection: String {
        guard !entries.isEmpty else { return "" }

        var lines: [String] = []
        for entry in entries {
            let canonical = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !canonical.isEmpty else { continue }

            // Each mishearing produces its own bullet line.
            let mishearings = entry.hints
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if mishearings.isEmpty {
                // No hints → there is no left-side mishearing to match against, so
                // a bare term carries zero correction signal for this "left → right"
                // prompt. Skip it here; the canonical term is still sent to Soniox
                // via sonioxTerms for recognition biasing.
                continue
            }
            for mishearing in mishearings {
                lines.append("- \"\(mishearing)\" → \"\(canonical)\"")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Mutations

    func add(_ entry: VocabularyEntry) {
        entries.append(entry)
    }

    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
    }

    func update(_ entry: VocabularyEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx] = entry
    }
}
