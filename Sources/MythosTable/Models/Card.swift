import Foundation

/// One card record as delivered by the ArkhamDB public API. Only the fields the
/// table needs are decoded; card text is never stored by the app beyond the raw
/// API cache in Application Support.
struct Card: Codable, Identifiable, Hashable {
    var code: String
    var name: String
    var subname: String?
    var typeCode: String
    var subtypeCode: String?
    var factionCode: String?
    var packCode: String?
    var encounterCode: String?
    var encounterName: String?
    var encounterPosition: Int?
    var stage: Int?
    var doom: Int?
    var clues: Int?
    var quantity: Int?
    var doubleSided: Bool?
    var imagesrc: String?
    var backimagesrc: String?
    var permanent: Bool?
    var health: Int?
    var sanity: Int?

    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code, name, subname, typeCode, subtypeCode, factionCode, packCode
        case encounterCode, encounterName, encounterPosition, stage, doom, clues
        case quantity, doubleSided, imagesrc, backimagesrc, permanent, health, sanity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        name = (try? c.decode(String.self, forKey: .name)) ?? code
        subname = try? c.decodeIfPresent(String.self, forKey: .subname)
        typeCode = (try? c.decode(String.self, forKey: .typeCode)) ?? "unknown"
        subtypeCode = try? c.decodeIfPresent(String.self, forKey: .subtypeCode)
        factionCode = try? c.decodeIfPresent(String.self, forKey: .factionCode)
        packCode = try? c.decodeIfPresent(String.self, forKey: .packCode)
        encounterCode = try? c.decodeIfPresent(String.self, forKey: .encounterCode)
        encounterName = try? c.decodeIfPresent(String.self, forKey: .encounterName)
        encounterPosition = c.lenientInt(.encounterPosition)
        stage = c.lenientInt(.stage)
        doom = c.lenientInt(.doom)
        clues = c.lenientInt(.clues)
        quantity = c.lenientInt(.quantity)
        doubleSided = try? c.decodeIfPresent(Bool.self, forKey: .doubleSided)
        imagesrc = try? c.decodeIfPresent(String.self, forKey: .imagesrc)
        backimagesrc = try? c.decodeIfPresent(String.self, forKey: .backimagesrc)
        permanent = try? c.decodeIfPresent(Bool.self, forKey: .permanent)
        health = c.lenientInt(.health)
        sanity = c.lenientInt(.sanity)
    }

    var displayName: String {
        if let subname, !subname.isEmpty { return "\(name): \(subname)" }
        return name
    }

    var isEncounterCard: Bool { encounterCode != nil }
    var isHorizontal: Bool { ["agenda", "act", "investigator"].contains(typeCode) }
    var hasBackImage: Bool { backimagesrc != nil }
}

extension KeyedDecodingContainer {
    /// ArkhamDB occasionally uses strings (e.g. "X") or nulls for numeric fields.
    func lenientInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s) }
        return nil
    }
}

extension String {
    /// Case- and diacritic-insensitive key used to match encounter set names.
    var folded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CardPool: String, Codable, CaseIterable, Identifiable {
    case core, rcore
    var id: String { rawValue }
    var title: String { self == .core ? "Core Set" : "Revised Core Set" }
    /// Revised core player cards live in "rcore"; its encounter cards share the
    /// original core codes, so both packs are loaded for the revised pool.
    var packs: [String] { self == .core ? ["core"] : ["rcore", "core"] }
}
