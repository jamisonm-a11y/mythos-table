import AppKit
import Foundation

/// `MythosTable --self-test`: loads card data, sets up each configured scenario,
/// and prints zone counts. Used to verify setup without the UI.
@MainActor
enum SelfTest {
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
