import Foundation

struct InvestigatorRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var code: String?
    var xpEarned = 0
    var xpSpent = 0
    var physicalTrauma = 0
    var mentalTrauma = 0
    var killed = false
    var insane = false
    var xpAvailable: Int { xpEarned - xpSpent }
}

struct ScenarioRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var scenarioID: String
    var name: String
    var resolution: String = ""
    var xpAwarded = 0
    var date = Date()
}

struct Campaign: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var definitionID: String
    var difficulty: Difficulty = .standard
    var chaosBag: [ChaosToken] = Difficulty.standard.preset
    var notes: String = ""
    var investigators: [InvestigatorRecord] = []
    var scenarios: [ScenarioRecord] = []
    var created = Date()
}

/// Encounter-set setup data, loaded from an editable JSON file in Application Support.
struct ScenarioConfigFile: Codable {
    var campaigns: [CampaignDefinition]
}

struct CampaignDefinition: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var scenarios: [ScenarioDefinition]
}

struct ScenarioDefinition: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// Sets whose cards are sorted into the agenda, act, encounter decks, etc.
    var encounterSets: [String]
    /// Whole sets placed in the set-aside zone instead of the encounter deck.
    var setAsideSets: [String]?
    /// One of these sets is chosen at random and added to `encounterSets`.
    var randomSetChoices: [String]?
    /// Individual card names pulled out of the encounter deck into the set-aside zone.
    var setAsideCards: [String]?

    static let defaultConfig = ScenarioConfigFile(campaigns: [
        CampaignDefinition(id: "notz", name: "Night of the Zealot", scenarios: [
            ScenarioDefinition(
                id: "the_gathering", name: "The Gathering",
                encounterSets: ["The Gathering", "Rats", "Ghouls", "Striking Fear", "Ancient Evils", "Chilling Cold"],
                setAsideSets: [], randomSetChoices: [],
                setAsideCards: ["Ghoul Priest", "Lita Chantler"]),
            ScenarioDefinition(
                id: "the_midnight_masks", name: "The Midnight Masks",
                encounterSets: ["The Midnight Masks", "Chilling Cold", "Nightgaunts", "Dark Cult", "Locked Doors"],
                setAsideSets: ["Cult of Umordhoth"], randomSetChoices: [],
                setAsideCards: []),
            ScenarioDefinition(
                id: "the_devourer_below", name: "The Devourer Below",
                encounterSets: ["The Devourer Below", "Ancient Evils", "Striking Fear", "Ghouls", "Dark Cult"],
                setAsideSets: [],
                randomSetChoices: ["Agents of Yog-Sothoth", "Agents of Shub-Niggurath", "Agents of Cthulhu", "Agents of Hastur"],
                setAsideCards: ["Umordhoth"]),
        ]),
    ])
}
