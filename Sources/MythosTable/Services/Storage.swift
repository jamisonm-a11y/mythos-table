import Foundation

/// File locations under ~/Library/Application Support/MythosTable.
enum Storage {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return makeDir(base.appendingPathComponent("MythosTable", isDirectory: true))
    }()

    static let cardsDir = makeDir(root.appendingPathComponent("cards", isDirectory: true))
    static let imagesDir = makeDir(root.appendingPathComponent("images", isDirectory: true))
    static let scenarioConfigURL = root.appendingPathComponent("scenarios.json")
    static let campaignsURL = root.appendingPathComponent("campaigns.json")
    static let autosaveURL = root.appendingPathComponent("autosave.json")
    static let extraCardsURL = cardsDir.appendingPathComponent("extra.json")

    static func packURL(_ pack: String) -> URL { cardsDir.appendingPathComponent("\(pack).json") }

    private static func makeDir(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static let apiEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    static let apiDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try decoder.decode(type, from: Data(contentsOf: url))
    }
}
