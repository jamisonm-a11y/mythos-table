import Foundation

struct ImportedDeck: Decodable {
    var id: Int?
    var name: String
    var investigatorCode: String
    var investigatorName: String?
    var slots: [String: Int]
}

enum DeckSource: String, CaseIterable, Identifiable {
    case decklist, deck
    var id: String { rawValue }
    var title: String { self == .decklist ? "Published Decklist" : "Shared Deck" }
}

enum DeckImporter {
    enum ImportError: LocalizedError {
        case invalidID
        case notFound(String)
        var errorDescription: String? {
            switch self {
            case .invalidID: "Enter a numeric ArkhamDB ID or a deck URL."
            case .notFound(let id): "No public deck or decklist found for \(id). Shared decks must be marked public on ArkhamDB."
            }
        }
    }

    /// Accepts a bare ID or an ArkhamDB URL such as https://arkhamdb.com/decklist/view/123/name.
    static func parseID(_ input: String) -> (DeckSource?, String)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if Int(trimmed) != nil { return (nil, trimmed) }
        let parts = trimmed.split(separator: "/").map(String.init)
        for (i, part) in parts.enumerated() where part == "decklist" || part == "deck" {
            if let id = parts.dropFirst(i + 1).first(where: { Int($0) != nil }) {
                return (part == "decklist" ? .decklist : .deck, id)
            }
        }
        return nil
    }

    static func fetch(_ input: String, preferred: DeckSource) async throws -> ImportedDeck {
        guard let (detected, id) = parseID(input) else { throw ImportError.invalidID }
        let first = detected ?? preferred
        let order: [DeckSource] = first == .decklist ? [.decklist, .deck] : [.deck, .decklist]
        for source in order {
            let url = URL(string: "https://arkhamdb.com/api/public/\(source.rawValue)/\(id).json")!
            if let data = try? await ArkhamDB.get(url),
               let deck = try? Storage.apiDecoder.decode(ImportedDeck.self, from: data) {
                return deck
            }
        }
        throw ImportError.notFound(id)
    }
}
