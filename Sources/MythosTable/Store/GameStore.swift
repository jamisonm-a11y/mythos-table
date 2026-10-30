import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// What the setup checklist sheet hands back to the store.
struct SetupPlan {
    var scenario: ScenarioDefinition
    var deckSets: [String]
    var setAsideSets: [String]
    var setAsideCards: [String]
}

@MainActor
@Observable
final class GameStore {
    // Card data
    var cards: [String: Card] = [:]
    var isLoadingCards = false
    var loadError: String?

    // Table
    var state = TableState() { didSet { scheduleAutosave() } }
    var selectedID: UUID?
    /// Card shown in the full-window zoom overlay.
    var zoomedID: UUID?

    // Config & campaign
    var config: ScenarioConfigFile
    var configWarning: String?
    var campaigns: [Campaign] = [] { didSet { saveCampaigns() } }
    var activeCampaignID: UUID? {
        didSet { UserDefaults.standard.set(activeCampaignID?.uuidString, forKey: "activeCampaignID") }
    }

    // Presentation
    var alertMessage: String?
    var showingSetup = false
    var showingDeckImport = false
    var showingChaosBag = false
    var showingCampaignLog = false
    var showingMulligan = false
    var searchZone: Zone?

    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    /// Off during `--self-test` so test runs never touch saved campaigns or the autosave.
    static var persistenceEnabled = true

    init() {
        let (config, warning) = ScenarioConfigStore.load()
        self.config = config
        self.configWarning = warning
        campaigns = (try? Storage.read([Campaign].self, from: Storage.campaignsURL)) ?? []
        if campaigns.isEmpty {
            campaigns = [Campaign(name: "Night of the Zealot", definitionID: "notz")]
        }
        let savedID = UserDefaults.standard.string(forKey: "activeCampaignID").flatMap(UUID.init)
        activeCampaignID = campaigns.first(where: { $0.id == savedID })?.id ?? campaigns.first?.id
        if let saved = try? Storage.read(TableState.self, from: Storage.autosaveURL) {
            state = saved
        }
        state.campaignID = activeCampaignID
    }

    // MARK: - Card data

    func loadCards(forceRefresh: Bool = false) async {
        isLoadingCards = true
        loadError = nil
        defer { isLoadingCards = false }
        do {
            cards = try await CardRepository.load(pool: state.cardPool, forceRefresh: forceRefresh)
            let missing = Set(state.zones.values.flatMap { $0 }.map(\.code)).filter { cards[$0] == nil }
            for card in await CardRepository.fetchMissing(Array(missing)) { cards[card.code] = card }
            if forceRefresh { await ImageCache.shared.clearMemory() }
        } catch {
            loadError = "Couldn't load card data: \(error.localizedDescription)"
        }
    }

    func setCardPool(_ pool: CardPool) {
        guard pool != state.cardPool else { return }
        state.cardPool = pool
        Task { await loadCards() }
    }

    func card(_ code: String) -> Card? { cards[code] }
    func card(for instance: CardInstance) -> Card? { cards[instance.code] }

    var encounterSetNames: [String] {
        var seen: [String: String] = [:]
        for card in cards.values {
            if let name = card.encounterName, seen[name.folded] == nil { seen[name.folded] = name }
        }
        return seen.values.sorted()
    }

    func canonicalSetName(_ name: String) -> String? {
        encounterSetNames.first { $0.folded == name.folded }
    }

    func reloadConfig() {
        let (config, warning) = ScenarioConfigStore.load()
        self.config = config
        configWarning = warning
        if let warning { alertMessage = warning }
    }

    // MARK: - Logging

    func log(_ text: String) {
        state.log.append(LogEntry(round: state.round, phase: state.phase, text: text))
    }

    func name(of id: UUID) -> String {
        guard let inst = state.instance(id) else { return "card" }
        return card(for: inst)?.displayName ?? inst.code
    }

    // MARK: - Scenario setup

    func setUp(_ plan: SetupPlan) {
        let deckSets = Set(plan.deckSets.map(\.folded))
        let asideSets = Set(plan.setAsideSets.map(\.folded))
        let asideCards = Set(plan.setAsideCards.map(\.folded))
        let wanted = deckSets.union(asideSets)

        let missing = (plan.deckSets + plan.setAsideSets).filter { canonicalSetName($0) == nil }

        let chosen = cards.values
            .filter { $0.encounterName.map { wanted.contains($0.folded) } ?? false }
            .sorted { ($0.encounterPosition ?? 0, $0.code) < ($1.encounterPosition ?? 0, $1.code) }

        var agendas: [Card] = [], acts: [Card] = []
        var tray: [CardInstance] = [], reference: [CardInstance] = []
        var aside: [CardInstance] = [], encounter: [CardInstance] = []

        for card in chosen {
            let copies = (0..<max(card.quantity ?? 1, 1)).map { _ in CardInstance(code: card.code) }
            switch card.typeCode {
            case "agenda": agendas.append(card)
            case "act": acts.append(card)
            case "location": tray += copies.map { var c = $0; c.showingBack = card.hasBackImage; return c }
            case "scenario": reference += copies
            default:
                let setAside = asideSets.contains(card.encounterName?.folded ?? "") || asideCards.contains(card.name.folded)
                if setAside { aside += copies } else { encounter += copies }
            }
        }

        for zone in [Zone.agenda, .act, .encounterDeck, .encounterDiscard, .scenarioReference,
                     .map, .threatArea, .locationsTray, .setAside, .victory, .outOfPlay] {
            state[zone] = []
        }
        state[.agenda] = agendas.sorted { ($0.stage ?? 0) < ($1.stage ?? 0) }.map { CardInstance(code: $0.code) }
        state[.act] = acts.sorted { ($0.stage ?? 0) < ($1.stage ?? 0) }.map { CardInstance(code: $0.code) }
        state[.locationsTray] = tray
        state[.scenarioReference] = reference
        state[.setAside] = aside
        state[.encounterDeck] = encounter.shuffled()

        resetPlayerSide()
        state.scenarioID = plan.scenario.id
        state.scenarioName = plan.scenario.name
        state.round = 1
        state.phase = .investigation
        state.actionsRemaining = 3
        state.resourcePool = 5
        state.lastToken = nil
        selectedID = nil

        log("Set up \(plan.scenario.name): \(agendas.count) agendas, \(acts.count) acts, \(tray.count) locations, "
            + "\(encounter.count) encounter cards, \(aside.count) set aside. Sets: \(plan.deckSets.joined(separator: ", ")).")
        if !plan.setAsideSets.isEmpty { log("Set-aside sets: \(plan.setAsideSets.joined(separator: ", ")).") }
        if !missing.isEmpty {
            alertMessage = "No cards matched these encounter sets: \(missing.joined(separator: ", ")). Check the names in the setup checklist or scenarios.json."
            log("Warning: unmatched sets \(missing.joined(separator: ", ")).")
        }
    }

    /// Rebuilds investigator, deck, hand and discard from the imported deck list.
    func resetPlayerSide() {
        for zone in [Zone.investigator, .hand, .playerDeck, .playerDiscard] { state[zone] = [] }
        state[.playArea] = []
        guard let deck = state.deck else { return }
        state[.investigator] = [CardInstance(code: deck.investigatorCode)]
        var library: [CardInstance] = []
        for code in deck.cardCodes {
            if card(code)?.permanent == true {
                state[.playArea].append(CardInstance(code: code))
            } else {
                library.append(CardInstance(code: code))
            }
        }
        state[.playerDeck] = library.shuffled()
    }

    // MARK: - Deck import

    func importDeck(_ deck: ImportedDeck) async {
        var codes: [String] = []
        for (code, count) in deck.slots.sorted(by: { $0.key < $1.key }) where code != deck.investigatorCode {
            codes += Array(repeating: code, count: count)
        }
        let missing = Set(codes + [deck.investigatorCode]).filter { cards[$0] == nil }
        for card in await CardRepository.fetchMissing(Array(missing)) { cards[card.code] = card }

        state.deck = DeckList(name: deck.name, investigatorCode: deck.investigatorCode, cardCodes: codes)
        resetPlayerSide()
        let investigatorName = card(deck.investigatorCode)?.name ?? deck.investigatorName ?? deck.investigatorCode
        log("Imported deck “\(deck.name)” (\(investigatorName), \(codes.count) cards).")

        updateCampaign { campaign in
            if !campaign.investigators.contains(where: { $0.code == deck.investigatorCode }) {
                campaign.investigators.append(InvestigatorRecord(name: investigatorName, code: deck.investigatorCode))
            }
        }
    }

    // MARK: - Moving cards

    func move(_ id: UUID, to zone: Zone, bottom: Bool = false, position: CGPoint? = nil) {
        guard let loc = state.locate(id) else { return }
        var inst = state[loc.zone].remove(at: loc.index)
        if !zone.isInPlay && loc.zone.isInPlay {
            inst.exhausted = false
            inst.clues = 0; inst.doom = 0; inst.damage = 0; inst.horror = 0; inst.resources = 0
        }
        if zone.isFaceDown { inst.showingBack = false }
        if zone == .map {
            inst.position = position ?? (loc.zone == .map ? inst.position : nextMapPosition())
        }
        if zone.isDeck && !bottom {
            state[zone].insert(inst, at: 0)
        } else {
            state[zone].append(inst)
        }
        if loc.zone != zone {
            let where_ = zone.isDeck ? (bottom ? "bottom of \(zone.title)" : "top of \(zone.title)") : zone.title
            log("Moved \(card(for: inst)?.displayName ?? inst.code) from \(loc.zone.title) to \(where_).")
        }
    }

    /// Opens the zoom overlay; hidden deck cards stay hidden.
    func zoom(_ id: UUID?) {
        guard let id, let loc = state.locate(id), !loc.zone.isFaceDown else { return }
        zoomedID = id
    }

    func setPosition(_ id: UUID, _ point: CGPoint) {
        guard let loc = state.locate(id), loc.zone == .map else { return }
        state[.map][loc.index].position = point
    }

    func bringToFront(_ id: UUID) {
        guard let loc = state.locate(id), loc.zone == .map else { return }
        let inst = state[.map].remove(at: loc.index)
        state[.map].append(inst)
    }

    private func nextMapPosition() -> CGPoint {
        let n = state[.map].count
        return CGPoint(x: 110 + CGFloat(n % 6) * 150, y: 120 + CGFloat(n / 6) * 200)
    }

    func update(_ id: UUID, _ change: (inout CardInstance) -> Void) {
        guard let loc = state.locate(id) else { return }
        change(&state.zones[loc.zone]![loc.index])
    }

    func adjust(_ id: UUID, _ key: WritableKeyPath<CardInstance, Int>, by delta: Int, label: String) {
        update(id) { $0[keyPath: key] = max(0, $0[keyPath: key] + delta) }
        if let inst = state.instance(id) {
            log("\(name(of: id)): \(label) \(delta > 0 ? "+" : "")\(delta) → \(inst[keyPath: key]).")
        }
    }

    func flip(_ id: UUID) {
        update(id) { $0.showingBack.toggle() }
        log("Flipped \(name(of: id)).")
    }

    func toggleExhaust(_ id: UUID) {
        update(id) { $0.exhausted.toggle() }
        log("\(state.instance(id)?.exhausted == true ? "Exhausted" : "Readied") \(name(of: id)).")
    }

    func readyAll() {
        for zone in Zone.allCases where zone.isInPlay {
            for i in state[zone].indices { state.zones[zone]![i].exhausted = false }
        }
        log("Readied all cards.")
    }

    // MARK: - Decks

    func shuffle(_ zone: Zone) {
        state[zone].shuffle()
        log("Shuffled \(zone.title).")
    }

    func shuffleDiscard(into zone: Zone) {
        let discard: Zone = zone == .playerDeck ? .playerDiscard : .encounterDiscard
        var pile = state[discard]
        for i in pile.indices { pile[i].showingBack = false }
        state[zone] = (state[zone] + pile).shuffled()
        state[discard] = []
        log("Shuffled \(discard.title) into \(zone.title).")
    }

    func drawPlayerCard(silent: Bool = false) {
        if state[.playerDeck].isEmpty {
            guard !state[.playerDiscard].isEmpty else { alertMessage = "Player deck and discard are both empty."; return }
            shuffleDiscard(into: .playerDeck)
            log("Player deck was empty: reshuffled discard pile.")
        }
        let inst = state[.playerDeck].removeFirst()
        state[.hand].append(inst)
        if !silent { log("Drew \(card(for: inst)?.displayName ?? inst.code).") }
    }

    func drawOpeningHand() {
        for _ in 0..<5 { drawPlayerCard(silent: true) }
        log("Drew opening hand (5 cards).")
    }

    func drawEncounterCard() {
        if state[.encounterDeck].isEmpty {
            guard !state[.encounterDiscard].isEmpty else { alertMessage = "Encounter deck and discard are both empty."; return }
            shuffleDiscard(into: .encounterDeck)
            log("Encounter deck was empty: reshuffled discard pile.")
        }
        let inst = state[.encounterDeck].removeFirst()
        state[.threatArea].insert(inst, at: 0)
        selectedID = inst.id
        log("Drew encounter card: \(card(for: inst)?.displayName ?? inst.code).")
    }

    func mulligan(_ ids: Set<UUID>) {
        let chosen = state[.hand].filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return }
        state[.hand].removeAll { ids.contains($0.id) }
        for _ in chosen { drawPlayerCard(silent: true) }
        state[.playerDeck] = (state[.playerDeck] + chosen).shuffled()
        log("Mulligan: replaced \(chosen.count) card\(chosen.count == 1 ? "" : "s") and shuffled them back.")
    }

    /// Flips an agenda/act to its back, or removes it if already flipped.
    func advance(_ zone: Zone) {
        guard let top = state[zone].first else { return }
        let name = card(for: top)?.displayName ?? top.code
        if !top.showingBack, card(for: top)?.hasBackImage == true {
            state.zones[zone]![0].showingBack = true
            log("\(zone == .agenda ? "Agenda" : "Act") flipped: \(name).")
        } else {
            move(top.id, to: .outOfPlay)
            log("\(zone == .agenda ? "Agenda" : "Act") advanced past \(name).")
        }
    }

    func clearAllDoom() {
        for zone in Zone.allCases { for i in state[zone].indices { state.zones[zone]![i].doom = 0 } }
        log("Removed all doom from play.")
    }

    // MARK: - Doom

    var totalDoom: Int {
        Zone.allCases.filter(\.isInPlay).flatMap { state[$0] }.map(\.doom).reduce(0, +)
    }

    var doomThreshold: Int? { state[.agenda].first.flatMap { card(for: $0)?.doom } }

    // MARK: - Turn tracking

    func nextPhase() {
        let next = state.phase.next
        if next == .mythos { state.round += 1 }
        state.phase = next
        if next == .investigation { state.actionsRemaining = 3 }
        log("Round \(state.round): \(next.title) phase.")
    }

    func setActions(_ n: Int) { state.actionsRemaining = min(max(n, 0), 9) }

    func adjustResources(_ delta: Int) {
        state.resourcePool = max(0, state.resourcePool + delta)
        log("Resources \(delta > 0 ? "+" : "")\(delta) → \(state.resourcePool).")
    }

    // MARK: - Chaos bag

    var activeCampaign: Campaign? { campaigns.first { $0.id == activeCampaignID } }

    func updateCampaign(_ change: (inout Campaign) -> Void) {
        guard let i = campaigns.firstIndex(where: { $0.id == activeCampaignID }) else { return }
        change(&campaigns[i])
    }

    func revealChaosToken() {
        guard let bag = activeCampaign?.chaosBag, let token = bag.randomElement() else {
            alertMessage = "The chaos bag is empty."
            return
        }
        state.lastToken = token
        log("Revealed chaos token: \(token.label).")
    }

    func newCampaign(named name: String, definitionID: String, difficulty: Difficulty) {
        var campaign = Campaign(name: name, definitionID: definitionID)
        campaign.difficulty = difficulty
        campaign.chaosBag = difficulty.preset
        campaigns.append(campaign)
        activeCampaignID = campaign.id
        state.campaignID = campaign.id
    }

    func selectCampaign(_ id: UUID) {
        activeCampaignID = id
        state.campaignID = id
    }

    private func saveCampaigns() {
        guard Self.persistenceEnabled else { return }
        try? Storage.write(campaigns, to: Storage.campaignsURL)
    }

    // MARK: - Save / load

    private func scheduleAutosave() {
        guard Self.persistenceEnabled else { return }
        autosaveTask?.cancel()
        let snapshot = state
        autosaveTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            try? Storage.write(snapshot, to: Storage.autosaveURL)
        }
    }

    func saveTable() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(state.scenarioName ?? "Table") Round \(state.round).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Storage.write(state, to: url)
            log("Saved table to \(url.lastPathComponent).")
        } catch {
            alertMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }

    func openTable() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let loaded = try Storage.read(TableState.self, from: url)
            let poolChanged = loaded.cardPool != state.cardPool
            state = loaded
            selectedID = nil
            if let id = loaded.campaignID, campaigns.contains(where: { $0.id == id }) { activeCampaignID = id }
            log("Loaded table from \(url.lastPathComponent).")
            Task { if poolChanged || !missingCodes.isEmpty { await loadCards() } }
        } catch {
            alertMessage = "Couldn't open that file as a MythosTable save: \(error.localizedDescription)"
        }
    }

    private var missingCodes: [String] {
        state.zones.values.flatMap { $0 }.map(\.code).filter { cards[$0] == nil }
    }

    func newTable() {
        let pool = state.cardPool
        let deck = state.deck
        state = TableState()
        state.cardPool = pool
        state.deck = deck
        state.campaignID = activeCampaignID
        resetPlayerSide()
        selectedID = nil
    }

    func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([Storage.scenarioConfigURL])
    }
}

struct DeckList: Codable, Hashable {
    var name: String
    var investigatorCode: String
    var cardCodes: [String]
}
