import SwiftUI

struct ContentView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            StatusBar()
            Divider()
            if store.cards.isEmpty {
                LoadingView()
            } else {
                HSplitView {
                    ScenarioColumn()
                        .frame(minWidth: 220, idealWidth: 250, maxWidth: 320)
                    CenterColumn()
                        .frame(minWidth: 560)
                    SidePanel()
                        .frame(minWidth: 300, idealWidth: 340, maxWidth: 460)
                }
            }
        }
        .sheet(isPresented: $store.showingSetup) { SetupSheet() }
        .sheet(isPresented: $store.showingDeckImport) { DeckImportSheet() }
        .sheet(isPresented: $store.showingChaosBag) { ChaosBagSheet() }
        .sheet(isPresented: $store.showingCampaignLog) { CampaignLogSheet() }
        .sheet(isPresented: $store.showingMulligan) { MulliganSheet() }
        .sheet(item: $store.searchZone) { zone in ZoneSearchSheet(zone: zone) }
        .alert("MythosTable", isPresented: Binding(get: { store.alertMessage != nil }, set: { if !$0 { store.alertMessage = nil } })) {
            Button("OK") { store.alertMessage = nil }
        } message: {
            Text(store.alertMessage ?? "")
        }
    }
}

private struct LoadingView: View {
    @Environment(GameStore.self) private var store
    var body: some View {
        VStack(spacing: 12) {
            if store.isLoadingCards {
                ProgressView("Loading card data from ArkhamDB…")
            } else if let error = store.loadError {
                Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                Text(error).multilineTextAlignment(.center)
                Button("Try Again") { Task { await store.loadCards() } }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(store.state.scenarioName ?? "No scenario").font(.headline)
                Text(store.activeCampaign.map { "\($0.name) · \($0.difficulty.title)" } ?? "No campaign")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(minWidth: 150, alignment: .leading)

            Divider().frame(height: 30)

            HStack(spacing: 6) {
                Stepper("Round \(store.state.round)", value: $store.state.round, in: 1...99).fixedSize()
                Picker("Phase", selection: $store.state.phase) {
                    ForEach(Phase.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Button("Next Phase") { store.nextPhase() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .fixedSize()
            }

            Divider().frame(height: 30)

            HStack(spacing: 4) {
                Text("Actions").font(.caption).foregroundStyle(.secondary)
                ForEach(0..<max(3, store.state.actionsRemaining), id: \.self) { i in
                    Image(systemName: i < store.state.actionsRemaining ? "circle.fill" : "circle")
                        .foregroundStyle(i < store.state.actionsRemaining ? Color.accentColor : .secondary)
                        .onTapGesture { store.setActions(i < store.state.actionsRemaining ? i : i + 1) }
                }
                Stepper("", value: Binding(get: { store.state.actionsRemaining }, set: { store.setActions($0) }), in: 0...9)
                    .labelsHidden()
                Button("Reset") { store.setActions(3) }.buttonStyle(.borderless).font(.caption)
            }
            .help("Click a pip to spend or restore an action")

            Divider().frame(height: 30)

            HStack(spacing: 4) {
                Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.orange)
                Button { store.adjustResources(-1) } label: { Image(systemName: "minus") }.buttonStyle(.borderless)
                Text("\(store.state.resourcePool)").monospacedDigit().frame(minWidth: 20)
                Button { store.adjustResources(1) } label: { Image(systemName: "plus") }.buttonStyle(.borderless)
            }
            .help("Investigator resource pool")

            DoomMeter()

            Spacer()

            HStack(spacing: 8) {
                if let token = store.state.lastToken {
                    ChaosTokenView(token: token, size: 30).id(store.state.log.count)
                        .transition(.scale)
                }
                Button {
                    withAnimation(.spring(duration: 0.25)) { store.revealChaosToken() }
                } label: {
                    Label("Reveal Token", systemImage: "bag.fill")
                }
                .fixedSize()
                .keyboardShortcut("t", modifiers: .command)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct DoomMeter: View {
    @Environment(GameStore.self) private var store
    var body: some View {
        let doom = store.totalDoom
        let threshold = store.doomThreshold
        let reached = threshold.map { doom >= $0 } ?? false
        HStack(spacing: 4) {
            Image(systemName: "hourglass").foregroundStyle(.red)
            Text("Doom \(doom)\(threshold.map { " / \($0)" } ?? "")")
                .monospacedDigit()
                .fontWeight(reached ? .bold : .regular)
                .foregroundStyle(reached ? .red : .primary)
            if reached { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red) }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(reached ? Color.red.opacity(0.15) : .clear, in: Capsule())
        .help("Total doom in play vs. the current agenda's doom threshold")
    }
}

// MARK: - Columns

struct ScenarioColumn: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                PileView(zone: .agenda, cardWidth: 70) {
                    Button("Advance") { store.advance(.agenda) }.disabled(store.state[.agenda].isEmpty)
                    Button("Clear Doom") { store.clearAllDoom() }
                }
                PileView(zone: .act, cardWidth: 70) {
                    Button("Advance") { store.advance(.act) }.disabled(store.state[.act].isEmpty)
                }
                HStack(alignment: .top, spacing: 8) {
                    PileView(zone: .encounterDeck, cardWidth: 60) {
                        Button("Draw") { store.drawEncounterCard() }
                            .keyboardShortcut("e", modifiers: .command)
                        Button("Shuffle") { store.shuffle(.encounterDeck) }
                    }
                }
                PileView(zone: .encounterDiscard, cardWidth: 60) {
                    Button("Shuffle Back") { store.shuffleDiscard(into: .encounterDeck) }
                        .disabled(store.state[.encounterDiscard].isEmpty)
                }
                PileView(zone: .scenarioReference, cardWidth: 70) {
                    if let ref = store.state[.scenarioReference].first {
                        Button("Flip") { store.flip(ref.id) }
                    }
                }
                ChaosBagSummary()
            }
            .padding(8)
        }
    }
}

private struct ChaosBagSummary: View {
    @Environment(GameStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ZoneHeader(title: "Chaos Bag", count: store.activeCampaign?.chaosBag.count)
                Spacer()
                Button("Edit…") { store.showingChaosBag = true }.buttonStyle(.borderless).font(.caption)
            }
            let bag = store.activeCampaign?.chaosBag ?? []
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(bag.sortedForDisplay.enumerated()), id: \.offset) { _, token in
                    ChaosTokenView(token: token, size: 22)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
}

extension Array where Element == ChaosToken {
    var sortedForDisplay: [ChaosToken] {
        let order = ChaosToken.allCases
        return sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
    }
}

struct CenterColumn: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        VSplitView {
            MapCanvas()
                .frame(minHeight: 260)
                .padding([.horizontal, .top], 8)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ZoneStrip(zone: .threatArea, cardWidth: 64, minHeight: 96)
                    ZoneStrip(zone: .playArea, cardWidth: 64, minHeight: 96)
                }
                PlayerRow()
            }
            .padding(8)
            .frame(minHeight: 280)
        }
    }
}

struct PlayerRow: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                ZoneHeader(title: "Investigator")
                if let inv = store.state[.investigator].first {
                    CardThumb(instance: inv, width: 84).cardInteractions(inv, store: store)
                } else {
                    Button("Import Deck…") { store.showingDeckImport = true }
                        .frame(width: 120, height: 84)
                }
            }
            .padding(8)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            .acceptsCards(into: .investigator)

            VStack(spacing: 4) {
                ZoneStrip(zone: .hand, cardWidth: 72, minHeight: 104)
                HStack {
                    Button("Draw") { store.drawPlayerCard() }.keyboardShortcut("d", modifiers: .command)
                    Button("Opening Hand") { store.drawOpeningHand() }
                    Button("Mulligan…") { store.showingMulligan = true }.disabled(store.state[.hand].isEmpty)
                    Button("Ready All") { store.readyAll() }.keyboardShortcut("r", modifiers: [.command, .shift])
                    Spacer()
                }
                .controlSize(.small)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 260, maxWidth: .infinity)
            .layoutPriority(1)

            VStack(spacing: 8) {
                PileView(zone: .playerDeck, cardWidth: 46) {
                    Button("Shuffle") { store.shuffle(.playerDeck) }
                }
                PileView(zone: .playerDiscard, cardWidth: 46) {
                    Button("Shuffle Back") { store.shuffleDiscard(into: .playerDeck) }
                        .disabled(store.state[.playerDiscard].isEmpty)
                }
            }
            .frame(width: 160)
        }
    }
}

// MARK: - Side panel

enum SideTab: String, CaseIterable, Identifiable {
    case inspector = "Inspector", tray = "Locations", aside = "Set Aside", victory = "Victory", log = "Log"
    var id: String { rawValue }
}

struct SidePanel: View {
    @Environment(GameStore.self) private var store
    @State private var tab: SideTab = .inspector

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(SideTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(8)
            Divider()
            switch tab {
            case .inspector: InspectorView()
            case .tray: ZoneGrid(zone: .locationsTray)
            case .aside: ZoneGrid(zone: .setAside)
            case .victory: ZoneGrid(zone: .victory)
            case .log: LogView()
            }
        }
        .onChange(of: store.selectedID) { _, new in if new != nil { tab = .inspector } }
    }
}

/// Wrapping grid of cards for side zones; drag cards out onto the map or other zones.
struct ZoneGrid: View {
    @Environment(GameStore.self) private var store
    let zone: Zone

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Drag a card onto the map or another zone, or click it and use Move to….")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(store.state[zone]) { inst in
                        VStack(spacing: 2) {
                            CardThumb(instance: inst, width: 84).cardInteractions(inst, store: store)
                            Text(store.card(for: inst)?.name ?? inst.code).font(.caption2).lineLimit(1)
                        }
                    }
                }
                if store.state[zone].isEmpty {
                    Text("No cards in \(zone.title).").foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding()
                }
            }
            .padding(8)
        }
        .acceptsCards(into: zone)
    }
}

struct LogView: View {
    @Environment(GameStore.self) private var store
    var body: some View {
        List(store.state.log.reversed()) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text("R\(entry.round) · \(entry.phase.title) · \(entry.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(entry.text).font(.callout).textSelection(.enabled)
            }
        }
    }
}
