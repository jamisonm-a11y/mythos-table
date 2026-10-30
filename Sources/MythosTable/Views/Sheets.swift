import SwiftUI

// MARK: - Scenario setup checklist

enum SetRole: String, CaseIterable, Identifiable {
    case off = "Off", deck = "Encounter Deck", aside = "Set Aside"
    var id: String { rawValue }
}

struct SetupSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var scenarioID: String = ""
    @State private var roles: [String: SetRole] = [:]   // keyed by display name
    @State private var randomPick: String?
    @State private var setAsideCards = ""
    @State private var showAll = false

    private var scenarios: [ScenarioDefinition] {
        let def = store.config.campaigns.first { $0.id == store.activeCampaign?.definitionID }
        return def?.scenarios ?? store.config.campaigns.flatMap(\.scenarios)
    }

    private var scenario: ScenarioDefinition? { scenarios.first { $0.id == scenarioID } }

    /// Names to list: every set referenced by the config plus, optionally, every set in the card pool.
    private var listedNames: [String] {
        var names = roles.keys.filter { roles[$0] != .off }
        if showAll { names += store.encounterSetNames }
        var seen = Set<String>()
        return names.filter { seen.insert($0.folded).inserted }.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set Up Scenario").font(.title2.weight(.semibold))
            Picker("Scenario", selection: $scenarioID) {
                ForEach(scenarios) { Text($0.name).tag($0.id) }
            }
            .onChange(of: scenarioID) { _, _ in loadDefaults() }

            if let choices = scenario?.randomSetChoices, !choices.isEmpty {
                HStack {
                    Text("Random set: **\(randomPick ?? "—")**")
                    Button("Reroll") { reroll(choices) }
                }
            }

            HStack {
                Text("Encounter sets").font(.headline)
                Spacer()
                Toggle("Show all sets", isOn: $showAll).toggleStyle(.checkbox)
            }
            List {
                ForEach(listedNames, id: \.self) { name in
                    HStack {
                        let found = store.canonicalSetName(name) != nil
                        Image(systemName: found ? "checkmark.seal" : "exclamationmark.triangle.fill")
                            .foregroundStyle(found ? .green : .orange)
                            .help(found ? "Matches cards in the loaded data" : "No cards match this set name")
                        Text(name)
                        Spacer()
                        Text("\(count(in: name)) cards").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: Binding(get: { roles[name] ?? .off }, set: { roles[name] = $0 })) {
                            ForEach(SetRole.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden().frame(width: 150)
                    }
                }
            }
            .frame(minHeight: 260)

            VStack(alignment: .leading, spacing: 4) {
                Text("Cards to set aside by name (comma-separated)").font(.headline)
                TextField("e.g. Ghoul Priest, Lita Chantler", text: $setAsideCards)
                Text("Agendas and acts are sorted by stage, locations go to the Locations tray, the scenario card goes to Scenario Reference, and everything else is shuffled into the encounter deck. Your imported deck is reshuffled.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Button("Reveal scenarios.json") { store.revealDataFolder() }
                Button("Reload Config") { store.reloadConfig(); loadDefaults() }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Set Up") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(scenario == nil || !roles.values.contains(.deck))
            }
        }
        .padding(20)
        .frame(width: 620, height: 640)
        .onAppear {
            scenarioID = store.state.scenarioID.flatMap { id in scenarios.first { $0.id == id }?.id } ?? scenarios.first?.id ?? ""
            loadDefaults()
        }
    }

    private func display(_ name: String) -> String { store.canonicalSetName(name) ?? name }

    private func count(in name: String) -> Int {
        let key = name.folded
        return store.cards.values.filter { $0.encounterName?.folded == key }.reduce(0) { $0 + max($1.quantity ?? 1, 1) }
    }

    private func loadDefaults() {
        guard let scenario else { return }
        roles = [:]
        for name in scenario.encounterSets { roles[display(name)] = .deck }
        for name in scenario.setAsideSets ?? [] { roles[display(name)] = .aside }
        randomPick = nil
        if let choices = scenario.randomSetChoices, !choices.isEmpty { reroll(choices) }
        setAsideCards = (scenario.setAsideCards ?? []).joined(separator: ", ")
    }

    private func reroll(_ choices: [String]) {
        if let old = randomPick { roles[old] = .off }
        let pick = display(choices.randomElement()!)
        randomPick = pick
        roles[pick] = .deck
    }

    private func apply() {
        guard let scenario else { return }
        let names = setAsideCards.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        store.setUp(SetupPlan(
            scenario: scenario,
            deckSets: roles.filter { $0.value == .deck }.map(\.key).sorted(),
            setAsideSets: roles.filter { $0.value == .aside }.map(\.key).sorted(),
            setAsideCards: names))
        if let randomPick { store.log("Random set chosen: \(randomPick).") }
        dismiss()
    }
}

// MARK: - Deck import

struct DeckImportSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var source: DeckSource = .decklist
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Deck from ArkhamDB").font(.title2.weight(.semibold))
            Picker("Type", selection: $source) {
                ForEach(DeckSource.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField("Deck ID or URL", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit(run)
            Text("Shared decks must be set to public in your ArkhamDB account settings. Importing replaces your investigator, deck, hand, and discard.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import", action: run).keyboardShortcut(.defaultAction).disabled(input.isEmpty || working)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func run() {
        working = true
        error = nil
        Task {
            do {
                let deck = try await DeckImporter.fetch(input, preferred: source)
                await store.importDeck(deck)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

// MARK: - Chaos bag editor

struct ChaosBagSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let bag = store.activeCampaign?.chaosBag ?? []
        VStack(alignment: .leading, spacing: 12) {
            Text("Chaos Bag").font(.title2.weight(.semibold))
            Text(store.activeCampaign?.name ?? "").foregroundStyle(.secondary)
            HStack {
                Text("Preset:")
                ForEach(Difficulty.allCases) { difficulty in
                    Button(difficulty.title) {
                        store.updateCampaign {
                            $0.difficulty = difficulty
                            $0.chaosBag = difficulty.preset
                        }
                        store.log("Chaos bag reset to \(difficulty.title) preset.")
                    }
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                ForEach(ChaosToken.allCases) { token in
                    let n = bag.filter { $0 == token }.count
                    GridRow {
                        ChaosTokenView(token: token, size: 24)
                        Text(token.label)
                        Stepper("\(n)", value: Binding(get: { n }, set: { set(token, count: $0) }), in: 0...20)
                    }
                }
            }
            HStack {
                Text("\(bag.count) tokens").foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func set(_ token: ChaosToken, count: Int) {
        store.updateCampaign { campaign in
            campaign.chaosBag.removeAll { $0 == token }
            campaign.chaosBag += Array(repeating: token, count: count)
        }
    }
}

// MARK: - Campaign log

struct CampaignLogSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var resolution = ""
    @State private var xpAward = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Campaign Log").font(.title2.weight(.semibold))
                Spacer()
                Picker("Campaign", selection: Binding(get: { store.activeCampaignID ?? UUID() }, set: { store.selectCampaign($0) })) {
                    ForEach(store.campaigns) { Text($0.name).tag($0.id) }
                }
                .frame(width: 260)
            }
            if store.activeCampaign != nil {
                Form {
                    Section("Campaign") {
                        TextField("Name", text: binding(\.name))
                        Picker("Scenario set", selection: binding(\.definitionID)) {
                            ForEach(store.config.campaigns) { Text($0.name).tag($0.id) }
                        }
                        Picker("Difficulty", selection: binding(\.difficulty)) {
                            ForEach(Difficulty.allCases) { Text($0.title).tag($0) }
                        }
                        .help("Changing difficulty here doesn't alter the chaos bag; use a preset in the chaos bag editor.")
                    }
                    Section("Investigators") { investigators }
                    Section("Scenarios Played") { scenarios }
                    Section("Notes") {
                        TextEditor(text: binding(\.notes))
                            .font(.body)
                            .frame(minHeight: 140)
                    }
                }
                .formStyle(.grouped)
            }
            HStack {
                TextField("New campaign name", text: $newName).frame(width: 220)
                Button("New Campaign") {
                    store.newCampaign(named: newName.isEmpty ? "Night of the Zealot" : newName, definitionID: "notz", difficulty: .standard)
                    newName = ""
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 760, height: 720)
    }

    private func binding<T>(_ key: WritableKeyPath<Campaign, T>) -> Binding<T> {
        Binding(get: { store.activeCampaign![keyPath: key] },
                set: { value in store.updateCampaign { $0[keyPath: key] = value } })
    }

    @ViewBuilder private var investigators: some View {
        let list = store.activeCampaign?.investigators ?? []
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                Text("Name"); Text("XP Earned"); Text("Spent"); Text("Available")
                Text("Physical"); Text("Mental"); Text("Killed"); Text("Insane"); Text("")
            }
            .font(.caption).foregroundStyle(.secondary)
            ForEach(list) { inv in
                GridRow {
                    TextField("", text: invBinding(inv.id, \.name)).frame(width: 140)
                    Stepper("\(inv.xpEarned)", value: invBinding(inv.id, \.xpEarned), in: 0...200)
                    Stepper("\(inv.xpSpent)", value: invBinding(inv.id, \.xpSpent), in: 0...200)
                    Text("\(inv.xpAvailable)").monospacedDigit()
                    Stepper("\(inv.physicalTrauma)", value: invBinding(inv.id, \.physicalTrauma), in: 0...20)
                    Stepper("\(inv.mentalTrauma)", value: invBinding(inv.id, \.mentalTrauma), in: 0...20)
                    Toggle("", isOn: invBinding(inv.id, \.killed)).labelsHidden()
                    Toggle("", isOn: invBinding(inv.id, \.insane)).labelsHidden()
                    Button(role: .destructive) {
                        store.updateCampaign { $0.investigators.removeAll { $0.id == inv.id } }
                    } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
            }
        }
        Button("Add Investigator") {
            store.updateCampaign { $0.investigators.append(InvestigatorRecord(name: "Investigator")) }
        }
    }

    private func invBinding<T>(_ id: UUID, _ key: WritableKeyPath<InvestigatorRecord, T>) -> Binding<T> {
        Binding(get: { store.activeCampaign!.investigators.first { $0.id == id }![keyPath: key] },
                set: { value in
                    store.updateCampaign { c in
                        if let i = c.investigators.firstIndex(where: { $0.id == id }) { c.investigators[i][keyPath: key] = value }
                    }
                })
    }

    @ViewBuilder private var scenarios: some View {
        ForEach(store.activeCampaign?.scenarios ?? []) { record in
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text(record.name).fontWeight(.medium)
                    if !record.resolution.isEmpty { Text(record.resolution).font(.callout) }
                    Text("\(record.xpAwarded) XP · \(record.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    store.updateCampaign { $0.scenarios.removeAll { $0.id == record.id } }
                } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
        }
        HStack {
            TextField("Resolution / outcome for \(store.state.scenarioName ?? "current scenario")", text: $resolution)
            Stepper("XP \(xpAward)", value: $xpAward, in: 0...50).fixedSize()
            Button("Record") {
                let record = ScenarioRecord(scenarioID: store.state.scenarioID ?? "custom",
                                            name: store.state.scenarioName ?? "Scenario",
                                            resolution: resolution, xpAwarded: xpAward)
                store.updateCampaign { c in
                    c.scenarios.append(record)
                    for i in c.investigators.indices where !c.investigators[i].killed && !c.investigators[i].insane {
                        c.investigators[i].xpEarned += xpAward
                    }
                }
                store.log("Recorded \(record.name) in the campaign log (\(xpAward) XP).")
                resolution = ""
                xpAward = 0
            }
        }
        Text("Recording adds the XP to every surviving investigator.").font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: - Mulligan

struct MulliganSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mulligan").font(.title2.weight(.semibold))
            Text("Select the cards to replace. They're set aside, replacements are drawn, then they're shuffled back into your deck.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(store.state[.hand]) { inst in
                        CardThumb(instance: inst, width: 110)
                            .opacity(selection.contains(inst.id) ? 0.45 : 1)
                            .overlay(alignment: .bottom) {
                                if selection.contains(inst.id) {
                                    Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                                        .padding(4).background(.thinMaterial, in: Capsule()).padding(6)
                                }
                            }
                            .onTapGesture {
                                if selection.contains(inst.id) { selection.remove(inst.id) } else { selection.insert(inst.id) }
                            }
                    }
                }
                .padding(4)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Replace \(selection.count)") {
                    store.mulligan(selection)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 760)
    }
}

// MARK: - Zone search

struct ZoneSearchSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let zone: Zone
    @State private var filter = ""

    var body: some View {
        let cards = store.state[zone].enumerated().filter { _, inst in
            filter.isEmpty || (store.card(for: inst)?.name.folded.contains(filter.folded) ?? false)
        }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Search \(zone.title)").font(.title2.weight(.semibold))
                Spacer()
                TextField("Filter by name", text: $filter).frame(width: 200)
            }
            if zone.isDeck { Text("Top of the deck is first.").font(.caption).foregroundStyle(.secondary) }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    ForEach(cards, id: \.element.id) { index, inst in
                        VStack(spacing: 4) {
                            CardFaceView(instance: inst, card: store.card(for: inst))
                                .frame(width: 110, height: 154)
                                .onTapGesture { store.selectedID = inst.id }
                            Text("\(index + 1). \(store.card(for: inst)?.name ?? inst.code)").font(.caption).lineLimit(1)
                            MoveMenu(id: inst.id).fixedSize().controlSize(.small)
                        }
                    }
                }
            }
            HStack {
                if zone.isDeck { Button("Shuffle") { store.shuffle(zone) } }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 720, height: 600)
    }
}
