import Foundation

enum ArkhamDB {
    static let base = URL(string: "https://arkhamdb.com")!

    static func packURL(_ pack: String) -> URL {
        URL(string: "https://arkhamdb.com/api/public/cards/\(pack).json?encounter=1")!
    }

    static func cardURL(_ code: String) -> URL {
        URL(string: "https://arkhamdb.com/api/public/card/\(code).json")!
    }

    static func imageURL(_ path: String) -> URL? {
        URL(string: path, relativeTo: base)?.absoluteURL
    }

    static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("MythosTable (personal use)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse(url) }
        guard http.statusCode == 200 else { throw APIError.status(http.statusCode, url) }
        return data
    }

    enum APIError: LocalizedError {
        case badResponse(URL)
        case status(Int, URL)
        var errorDescription: String? {
            switch self {
            case .badResponse(let url): "No HTTP response from \(url.absoluteString)"
            case .status(let code, let url): "HTTP \(code) from \(url.absoluteString)"
            }
        }
    }
}

/// Loads card data from the ArkhamDB public API, caching raw JSON on disk.
enum CardRepository {
    static func load(pool: CardPool, forceRefresh: Bool) async throws -> [String: Card] {
        var cards: [String: Card] = [:]
        for card in loadExtras() { cards[card.code] = card }
        for pack in pool.packs {
            for card in try await loadPack(pack, forceRefresh: forceRefresh) {
                cards[card.code] = card
            }
        }
        return cards
    }

    static func loadPack(_ pack: String, forceRefresh: Bool) async throws -> [Card] {
        let url = Storage.packURL(pack)
        if !forceRefresh, let data = try? Data(contentsOf: url),
           let cards = try? Storage.apiDecoder.decode([Card].self, from: data) {
            return cards
        }
        do {
            let data = try await ArkhamDB.get(ArkhamDB.packURL(pack))
            let cards = try Storage.apiDecoder.decode([Card].self, from: data)
            try data.write(to: url, options: .atomic)
            return cards
        } catch {
            // Fall back to a stale cache when offline.
            if let data = try? Data(contentsOf: url),
               let cards = try? Storage.apiDecoder.decode([Card].self, from: data) {
                return cards
            }
            throw error
        }
    }

    /// Fetches individual cards (e.g. from a deck outside the loaded packs) and caches them.
    static func fetchMissing(_ codes: [String]) async -> [Card] {
        var extras = loadExtras()
        var fetched: [Card] = []
        for code in codes where !extras.contains(where: { $0.code == code }) {
            if let data = try? await ArkhamDB.get(ArkhamDB.cardURL(code)),
               let card = try? Storage.apiDecoder.decode(Card.self, from: data) {
                fetched.append(card)
            }
        }
        if !fetched.isEmpty {
            extras.append(contentsOf: fetched)
            if let data = try? Storage.apiEncoder.encode(extras) {
                try? data.write(to: Storage.extraCardsURL, options: .atomic)
            }
        }
        return fetched
    }

    static func loadExtras() -> [Card] {
        guard let data = try? Data(contentsOf: Storage.extraCardsURL) else { return [] }
        return (try? Storage.apiDecoder.decode([Card].self, from: data)) ?? []
    }
}

enum ScenarioConfigStore {
    static func load() -> (ScenarioConfigFile, String?) {
        let url = Storage.scenarioConfigURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Storage.write(ScenarioDefinition.defaultConfig, to: url)
            return (ScenarioDefinition.defaultConfig, nil)
        }
        do {
            return (try Storage.read(ScenarioConfigFile.self, from: url), nil)
        } catch {
            return (ScenarioDefinition.defaultConfig,
                    "Couldn't read scenarios.json (\(error.localizedDescription)). Using built-in defaults.")
        }
    }

    static func resetToDefaults() {
        try? Storage.write(ScenarioDefinition.defaultConfig, to: Storage.scenarioConfigURL)
    }
}
