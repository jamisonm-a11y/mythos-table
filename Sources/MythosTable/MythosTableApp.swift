import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable rather than an .app bundle.
        if CommandLine.arguments.contains("--self-test") { SelfTest.runIfRequested(); return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MythosTableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: GameStore
    @State private var gameMaster: GameMaster

    init() {
        let store = GameStore()
        _store = State(initialValue: store)
        _gameMaster = State(initialValue: GameMaster(store: store))
    }

    var body: some Scene {
        WindowGroup("MythosTable", id: "table") {
            ContentView()
                .environment(store)
                .environment(gameMaster)
                .frame(minWidth: 1200, minHeight: 800)
                .task { await store.loadCards() }
        }
        .defaultSize(width: 1500, height: 940)
        .commands { TableCommands(store: store) }

        Window("How to Play", id: "how-to-play") {
            HowToPlayView()
        }
        .defaultSize(width: 980, height: 700)
    }
}

struct TableCommands: Commands {
    let store: GameStore
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(before: .windowList) {
            Button("Show Table") { openWindow(id: "table") }
                .keyboardShortcut("0")
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button("How to Play") { openWindow(id: "how-to-play") }
                .keyboardShortcut("?", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Table") { store.newTable() }
            Button("Open Table…") { store.openTable() }.keyboardShortcut("o")
            Divider()
            Button("Save Table…") { store.saveTable() }.keyboardShortcut("s")
        }
        CommandMenu("Table") {
            Button("Set Up Scenario…") { store.showingSetup = true }.keyboardShortcut("u", modifiers: [.command, .shift])
            Button("Import Deck…") { store.showingDeckImport = true }.keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Chaos Bag…") { store.showingChaosBag = true }.keyboardShortcut("b", modifiers: [.command, .shift])
            Button("Campaign Log…") { store.showingCampaignLog = true }.keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
            Button("Draw Player Card") { store.drawPlayerCard() }
            Button("Draw Encounter Card") { store.drawEncounterCard() }
            Button("Reveal Chaos Token") { store.revealChaosToken() }
            Button("Next Phase") { store.nextPhase() }
        }
        CommandGroup(before: .toolbar) {
            Button("Zoom Selected Card") { store.zoom(store.selectedID) }
                .keyboardShortcut("y")
            CardSizePicker()
            Divider()
        }
        CommandMenu("Data") {
            Picker("Card Pool", selection: Binding(get: { store.state.cardPool }, set: { store.setCardPool($0) })) {
                ForEach(CardPool.allCases) { Text($0.title).tag($0) }
            }
            Button("Refresh Card Data from ArkhamDB") { Task { await store.loadCards(forceRefresh: true) } }
            Divider()
            Button("Reload Scenario Config") { store.reloadConfig() }
            Button("Reset Scenario Config to Defaults") { ScenarioConfigStore.resetToDefaults(); store.reloadConfig() }
            Button("Show Data Folder in Finder") { store.revealDataFolder() }
        }
    }
}

struct CardSizePicker: View {
    @AppStorage("cardScale") private var cardScale = 1.0
    var body: some View {
        Picker("Card Size", selection: $cardScale) {
            Text("Small").tag(0.85)
            Text("Medium").tag(1.0)
            Text("Large").tag(1.3)
            Text("Extra Large").tag(1.6)
        }
    }
}
