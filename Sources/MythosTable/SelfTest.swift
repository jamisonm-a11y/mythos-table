import AppKit
import Foundation

/// `MythosTable --self-test`: loads card data, sets up each configured scenario,
/// and prints zone counts. Used to verify setup without the UI.
@MainActor
enum SelfTest {
    /// `MythosTable --gm-test`: one real game master request through Claude Code (uses the Claude plan).
    static func runGameMasterTestIfRequested() {
        guard CommandLine.arguments.contains("--gm-test") else { return }
        GameStore.persistenceEnabled = false
        Task { @MainActor in
            let store = GameStore()
            store.state = TableState()
            await store.loadCards()
            guard let gathering = store.config.campaigns.flatMap(\.scenarios).first else { exit(1) }
            store.setUp(SetupPlan(scenario: gathering, deckSets: gathering.encounterSets,
                                  setAsideSets: [], setAsideCards: gathering.setAsideCards ?? []))
            let gm = GameMaster(store: store)
            UserDefaults.standard.set("claudeCode", forKey: "gameMasterBackend")
            gm.backend = .claudeCode
            gm.effort = "low"
            gm.submit(.setUpScenario)
            var printed = 0
            for _ in 0..<600 {
                try? await Task.sleep(for: .milliseconds(500))
                while printed < gm.entries.count { print("[\(gm.entries[printed].kind)] \(gm.entries[printed].text)"); printed += 1 }
                if let q = gm.pendingQuestion { print("QUESTION:", q.text, q.choices); gm.answer(q.choices.first ?? "yes") }
                if !gm.isRunning && printed > 1 { break }
            }
            if CommandLine.arguments.contains("--with-action"),
               let deck = try? await DeckImporter.fetch("1", preferred: .decklist) {
                await store.importDeck(deck)
                store.state.investigatorLocationID = store.state[.map].first?.id
                store.drawOpeningHand()
                gm.submit(.action("Investigate the Study."))
                for _ in 0..<600 {
                    try? await Task.sleep(for: .milliseconds(500))
                    while printed < gm.entries.count { print("[\(gm.entries[printed].kind)] \(gm.entries[printed].text)"); printed += 1 }
                    if let q = gm.pendingQuestion { print("QUESTION:", q.text, q.choices); gm.answer(q.choices.first ?? "yes") }
                    if !gm.isRunning { break }
                }
                let inv = store.state[.investigator].first
                print("ACTIONS LEFT:", store.state.actionsRemaining, "INVESTIGATOR CLUES:", inv?.clues ?? -1,
                      "STUDY CLUES:", store.state[.map].first?.clues ?? -1)
            }
            let map = store.state[.map].map { "\(store.card(for: $0)?.name ?? "?")\($0.showingBack ? " (unrevealed)" : "") clues=\($0.clues)" }
            print("MAP:", map)
            print("INVESTIGATOR AT:", store.state.investigatorLocationID.map { store.name(of: $0) } ?? "none")
            gm.stop()
            exit(0)
        }
    }

    /// `MythosTable --mcp-test`: serves the table tools and prints the endpoint for manual JSON-RPC calls.
    static func runMCPTestIfRequested() {
        guard CommandLine.arguments.contains("--mcp-test") else { return }
        GameStore.persistenceEnabled = false
        Task { @MainActor in
            let store = GameStore()
            store.state = TableState()
            await store.loadCards()
            if let gathering = store.config.campaigns.flatMap(\.scenarios).first {
                store.setUp(SetupPlan(scenario: gathering, deckSets: gathering.encounterSets,
                                      setAsideSets: [], setAsideCards: gathering.setAsideCards ?? []))
            }
            let server = MCPServer(tools: GameMasterTools.definitions) { name, arguments in
                await MainActor.run {
                    do { return (GameMaster.encode(try store.runTool(name, arguments)), false) }
                    catch { return (error.localizedDescription, true) }
                }
            }
            try? await server.start()
            print("URL \(server.url)")
            print("TOKEN \(server.token)")
            fflush(stdout)
            try? await Task.sleep(for: .seconds(30))
            exit(0)
        }
    }

    static func runIfRequested() {
        guard CommandLine.arguments.contains("--self-test") else { return }
        GameStore.persistenceEnabled = false
        Task { @MainActor in
            let store = GameStore()
            store.state = TableState()
            await store.loadCards()
            if let error = store.loadError { print("FAIL:", error); exit(1) }
            print("Loaded \(store.cards.count) cards (\(store.state.cardPool.title))")
            for scenario in store.config.campaigns.flatMap(\.scenarios) {
                let random = scenario.randomSetChoices?.first.map { [$0] } ?? []
                store.setUp(SetupPlan(scenario: scenario,
                                      deckSets: scenario.encounterSets + random,
                                      setAsideSets: scenario.setAsideSets ?? [],
                                      setAsideCards: scenario.setAsideCards ?? []))
                let names: (Zone) -> String = { zone in
                    store.state[zone].map { store.card(for: $0)?.name ?? $0.code }.joined(separator: ", ")
                }
                print("\n== \(scenario.name) ==")
                for zone in [Zone.agenda, .act, .scenarioReference, .locationsTray, .setAside] {
                    print("\(zone.title) (\(store.state[zone].count)): \(names(zone))")
                }
                print("Encounter Deck: \(store.state[.encounterDeck].count) cards")
                print("Doom threshold: \(store.doomThreshold.map(String.init) ?? "none")")
                if let alert = store.alertMessage { print("ALERT:", alert); store.alertMessage = nil }
            }
            let deck = try? await DeckImporter.fetch("https://arkhamdb.com/decklist/view/1/roland-banks-starter-deck", preferred: .deck)
            if let deck {
                await store.importDeck(deck)
                store.drawOpeningHand()
                print("\nDeck: \(deck.name) — investigator \(store.state[.investigator].first.flatMap { store.card(for: $0)?.name } ?? "?"), "
                      + "deck \(store.state[.playerDeck].count), hand \(store.state[.hand].count), play area \(store.state[.playArea].count)")
                store.mulligan(Set(store.state[.hand].prefix(2).map(\.id)))
                print("After mulligan: hand \(store.state[.hand].count), deck \(store.state[.playerDeck].count)")
            } else { print("FAIL: deck import") }
            // Game master tools against The Gathering, offline.
            if let gathering = store.config.campaigns.flatMap(\.scenarios).first {
                store.setUp(SetupPlan(scenario: gathering, deckSets: gathering.encounterSets,
                                      setAsideSets: [], setAsideCards: gathering.setAsideCards ?? []))
                @MainActor func call(_ name: String, _ input: [String: Any] = [:]) -> String {
                    do { return GameMaster.encode(try store.runTool(name, input)) } catch { return "ERROR \(error.localizedDescription)" }
                }
                let snapshot = call("get_table_state")
                let study = store.state[.locationsTray].first!
                let sid = store.shortID(study.id)
                print("\nGame master tools:")
                print(" state bytes:", snapshot.count, snapshot.contains("\"zones\"") ? "ok" : "BAD")
                print(" move:", call("move_card", ["id": sid, "zone": "map", "x": 300, "y": 300]))
                print(" flip:", call("flip_card", ["id": sid]).prefix(90))
                print(" location:", call("set_investigator_location", ["id": sid]))
                print(" clues:", call("adjust_tokens", ["id": sid, "token": "clues", "delta": 2]))
                print(" token:", call("reveal_chaos_token", ["test": "self-test"]))
                print(" encounter:", call("draw_encounter_card").prefix(90))
                print(" draw:", call("draw_player_cards", ["count": 2]).prefix(90))
                print(" action:", call("spend_action", ["description": "test"]))
                print(" advance:", call("advance", ["deck": "agenda"]).prefix(60))
                print(" phase:", call("next_phase"))
                print(" remember:", call("remember", ["note": "test note"]))
                print(" bad id:", call("flip_card", ["id": "zzzzzz"]))
                print(" state has location:", call("get_table_state").contains("investigator_location\":{"))
                let body: [String: Any] = ["system": GameMaster.systemPrompt, "tools": GameMasterTools.definitions,
                                           "messages": [["role": "user", "content": "x"]]]
                print(" request body valid JSON:", JSONSerialization.isValidJSONObject(body))
            }
            store.state.cardPool = .rcore
            await store.loadCards()
            print("Revised core pool: \(store.cards.count) cards, \(store.encounterSetNames.count) encounter sets")
            let data = try! Storage.encoder.encode(store.state)
            let back = try! Storage.decoder.decode(TableState.self, from: data)
            print("Save round-trip: \(back.zones.values.map(\.count).reduce(0, +)) cards, \(back.log.count) log entries")
            exit(0)
        }
    }
}
