import SwiftUI

/// You play the investigator; Claude runs the game around you.
struct GameMasterPanel: View {
    @Environment(GameMaster.self) private var gameMaster
    @Environment(GameStore.self) private var store
    @State private var keyInput = ""
    @State private var actionText = ""
    @State private var answerText = ""
    @FocusState private var actionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !gameMaster.isReady {
                connectView
            } else {
                header
                if let question = gameMaster.pendingQuestion {
                    questionCard(question)
                } else {
                    actionBox
                }
                Divider()
                transcript
                footer
            }
        }
        .padding(10)
    }

    // MARK: - Connect

    private var connectView: some View {
        @Bindable var gameMaster = gameMaster
        return VStack(alignment: .leading, spacing: 10) {
            Text("Game Master").font(.headline)
            Text("You play the investigator. Claude runs everything else: it resolves the actions you declare, encounter cards, enemies, doom, and the Mythos, Enemy, and Upkeep phases, and asks you whenever a choice is yours.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Run Claude with", selection: $gameMaster.backend) {
                ForEach(GameMaster.Backend.allCases) { Text($0.title).tag($0) }
            }
            if gameMaster.backend == .claudeCode {
                claudeCodeSetup
            } else {
                keyEntry
            }
        }
    }

    private var claudeCodeSetup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Uses your Claude subscription through Claude Code, with no API key or extra charges; games count toward your plan's usage limits.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("Claude Code wasn't found on this Mac. Install it, then open Terminal, run `claude`, and sign in with your Claude account.")
                .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            HStack {
                Link("Install Claude Code", destination: URL(string: "https://claude.com/claude-code")!)
                Spacer()
                Button("Check Again") { gameMaster.claudeCodeInstalled = ClaudeCodeSession.findExecutable() != nil }
            }
        }
    }

    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Uses the Anthropic API with your own key, billed per use to your account; the panel shows a running cost estimate.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            SecureField("Anthropic API key (sk-ant-…)", text: $keyInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit { gameMaster.saveKey(keyInput); keyInput = "" }
            HStack {
                Link("Get an API key", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)
                Spacer()
                Button("Save Key") { gameMaster.saveKey(keyInput); keyInput = "" }
                    .disabled(keyInput.isEmpty)
            }
            Text("The key is stored in your macOS keychain.").font(.caption).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Controls

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Game Master").font(.headline)
                Spacer()
                if gameMaster.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Stop", role: .destructive) { gameMaster.stop() }
                        .keyboardShortcut(".", modifiers: .command)
                }
            }
            if store.state.scenarioName == nil {
                Text("Set up a scenario (Table → Set Up Scenario…) and import a deck to begin.")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                HStack {
                    if store.state[.map].isEmpty {
                        Button("Place Starting Locations") { gameMaster.submit(.setUpScenario) }
                    }
                    if store.state.phase == .investigation {
                        Button("End Turn") { gameMaster.endTurn() }
                            .keyboardShortcut(.return, modifiers: [.command, .shift])
                            .help("Claude runs the Enemy, Upkeep, and next Mythos phases, then hands the turn back to you.")
                    } else {
                        Button("Run \(store.state.phase.title) Phase") { gameMaster.submit(.runPhases) }
                    }
                }
                .disabled(gameMaster.isRunning)
            }
        }
    }

    private var actionBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What do you do? (\(store.state.actionsRemaining) action\(store.state.actionsRemaining == 1 ? "" : "s") left)")
                .font(.caption).foregroundStyle(.secondary)
            TextField("e.g. Investigate the Study, committing Magnifying Glass", text: $actionText, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($actionFocused)
                .onSubmit(sendAction)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["Investigate", "Move to ", "Fight ", "Evade ", "Play ", "Draw a card", "Gain a resource", "Engage ", "Activate "], id: \.self) { verb in
                        Button(verb.trimmingCharacters(in: .whitespaces)) {
                            if verb.hasSuffix(" ") {
                                actionText = verb
                                actionFocused = true
                            } else {
                                actionText = verb
                                sendAction()
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Send", action: sendAction)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(actionText.trimmingCharacters(in: .whitespaces).isEmpty || gameMaster.isRunning)
            }
        }
        .disabled(store.state.scenarioName == nil)
    }

    private func sendAction() {
        let text = actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !gameMaster.isRunning else { return }
        gameMaster.submit(.action(text))
        actionText = ""
    }

    private func questionCard(_ question: GameMaster.Question) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your decision", systemImage: "questionmark.bubble.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
            Text(question.text).font(.callout).fixedSize(horizontal: false, vertical: true)
            if !question.choices.isEmpty {
                FlowButtons(choices: question.choices) { gameMaster.answer($0) }
            }
            HStack {
                TextField("Or type an answer", text: $answerText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitAnswer() }
                Button("Answer") { submitAnswer() }.disabled(answerText.isEmpty)
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func submitAnswer() {
        guard !answerText.isEmpty else { return }
        gameMaster.answer(answerText)
        answerText = ""
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if gameMaster.entries.isEmpty {
                        Text("Declare what your investigator does and Claude resolves it. When you're done with your actions, click End Turn.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(gameMaster.entries) { entry in
                        EntryRow(entry: entry).id(entry.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: gameMaster.entries.count) { _, _ in
                if let last = gameMaster.entries.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var footer: some View {
        @Bindable var gameMaster = gameMaster
        return HStack {
            Picker("Effort", selection: $gameMaster.effort) {
                Text("Low").tag("low")
                Text("Medium").tag("medium")
                Text("High").tag("high")
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("How carefully Claude thinks. Higher is slower and costs more.")
            .disabled(gameMaster.isRunning)
            Spacer()
            if gameMaster.backend == .api {
                Text(String(format: "≈ $%.2f", gameMaster.usage.estimatedDollars))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .help("Estimated API cost this session")
            } else {
                Text("On your Claude plan").font(.caption).foregroundStyle(.secondary)
            }
            Menu("More") {
                Picker("Run Claude with", selection: $gameMaster.backend) {
                    ForEach(GameMaster.Backend.allCases) { Text($0.title).tag($0) }
                }
                .disabled(gameMaster.isRunning)
                Divider()
                Button("Clear Transcript") { gameMaster.clearTranscript() }
                Button("Clear Game Master Notes") { store.state.autopilotNotes = nil }
                Divider()
                if gameMaster.hasAPIKey {
                    Button("Forget API Key", role: .destructive) { gameMaster.forgetKey() }
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            .font(.caption)
        }
    }
}

/// Choice buttons that wrap onto as many lines as needed.
private struct FlowButtons: View {
    let choices: [String]
    let action: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(choices, id: \.self) { choice in
                Button { action(choice) } label: {
                    Text(choice).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct EntryRow: View {
    let entry: GameMaster.Entry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 14)
            Text(entry.text)
                .font(entry.kind == .narration || entry.kind == .player ? .callout : .caption)
                .fontWeight(entry.kind == .player ? .semibold : .regular)
                .foregroundStyle(entry.kind == .action ? .secondary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var icon: String {
        switch entry.kind {
        case .player: "person.fill"
        case .narration: "text.bubble"
        case .action: "hand.point.right"
        case .result: "die.face.5"
        case .info: "info.circle"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch entry.kind {
        case .player: .primary
        case .narration: .accentColor
        case .action: .secondary
        case .result: .orange
        case .info: .secondary
        case .error: .red
        }
    }
}
