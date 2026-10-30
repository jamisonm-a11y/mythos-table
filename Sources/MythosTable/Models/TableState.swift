import Foundation

enum Zone: String, Codable, CaseIterable, Identifiable, CodingKeyRepresentable {
    case agenda, act, encounterDeck, encounterDiscard, scenarioReference
    case map, threatArea, playArea
    case investigator, hand, playerDeck, playerDiscard
    case locationsTray, setAside, victory, outOfPlay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agenda: "Agenda Deck"
        case .act: "Act Deck"
        case .encounterDeck: "Encounter Deck"
        case .encounterDiscard: "Encounter Discard"
        case .scenarioReference: "Scenario Reference"
        case .map: "Map"
        case .threatArea: "Threat Area"
        case .playArea: "Play Area"
        case .investigator: "Investigator"
        case .hand: "Hand"
        case .playerDeck: "Player Deck"
        case .playerDiscard: "Player Discard"
        case .locationsTray: "Locations Tray"
        case .setAside: "Set Aside"
        case .victory: "Victory Display"
        case .outOfPlay: "Out of Play"
        }
    }

    /// Ordered piles where index 0 is the top card.
    var isDeck: Bool { [.agenda, .act, .encounterDeck, .playerDeck].contains(self) }
    var isFaceDown: Bool { [.encounterDeck, .playerDeck].contains(self) }
    var isInPlay: Bool { [.agenda, .act, .map, .threatArea, .playArea, .investigator].contains(self) }
}

struct CardInstance: Identifiable, Codable, Hashable {
    var id = UUID()
    var code: String
    var showingBack = false
    var exhausted = false
    var clues = 0
    var doom = 0
    var damage = 0
    var horror = 0
    var resources = 0
    /// Center point on the map canvas; only meaningful in the map zone.
    var position = CGPoint(x: 120, y: 120)
}

enum Phase: String, Codable, CaseIterable, Identifiable {
    case mythos, investigation, enemy, upkeep
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var next: Phase {
        switch self {
        case .mythos: .investigation
        case .investigation: .enemy
        case .enemy: .upkeep
        case .upkeep: .mythos
        }
    }
}

struct LogEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var round: Int
    var phase: Phase
    var text: String
}

struct TableState: Codable {
    var version = 1
    var cardPool: CardPool = .core
    var campaignID: UUID?
    var scenarioID: String?
    var scenarioName: String?
    var zones: [Zone: [CardInstance]] = [:]
    var round = 1
    var phase: Phase = .investigation
    var actionsRemaining = 3
    var resourcePool = 5
    var lastToken: ChaosToken?
    var deck: DeckList?
    /// Notes the game master keeps for itself between runs.
    var autopilotNotes: [String]?
    /// The map location the investigator is currently at.
    var investigatorLocationID: UUID?
    var log: [LogEntry] = []

    subscript(zone: Zone) -> [CardInstance] {
        get { zones[zone] ?? [] }
        set { zones[zone] = newValue }
    }

    func locate(_ id: UUID) -> (zone: Zone, index: Int)? {
        for (zone, cards) in zones {
            if let i = cards.firstIndex(where: { $0.id == id }) { return (zone, i) }
        }
        return nil
    }

    func instance(_ id: UUID) -> CardInstance? {
        guard let loc = locate(id) else { return nil }
        return self[loc.zone][loc.index]
    }
}
